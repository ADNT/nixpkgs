{ lib
, stdenv
, fetchFromGitHub
, makeWrapper
, makeDesktopItem
, fixup_yarn_lock
, yarn
, nodejs
, fetchYarnDeps
, electron
, element-web
, sqlcipher
, callPackage
, Security
, AppKit
, CoreServices
, desktopToDarwinBundle
, useKeytar ? true
}:

let
  pinData = lib.importJSON ./pin.json;
  executableName = "element-desktop";
  keytar = callPackage ./keytar { inherit Security AppKit; };
  seshat = callPackage ./seshat { inherit CoreServices; };
in
stdenv.mkDerivation rec {
  pname = "element-desktop";
  inherit (pinData) version;
  name = "${pname}-${version}";
  src = fetchFromGitHub {
    owner = "vector-im";
    repo = "element-desktop";
    rev = "v${version}";
    sha256 = pinData.desktopSrcHash;
  };

  offlineCache = fetchYarnDeps {
    yarnLock = src + "/yarn.lock";
    sha256 = pinData.desktopYarnHash;
  };

  nativeBuildInputs = [ yarn fixup_yarn_lock nodejs makeWrapper ]
    ++ lib.optionals stdenv.isDarwin [ desktopToDarwinBundle ];

  inherit seshat;

  configurePhase = ''
    runHook preConfigure

    export HOME=$(mktemp -d)
    yarn config --offline set yarn-offline-mirror $offlineCache
    fixup_yarn_lock yarn.lock
    yarn install --offline --frozen-lockfile --ignore-platform --ignore-scripts --no-progress --non-interactive
    patchShebangs node_modules/

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    yarn --offline run build:ts
    yarn --offline run i18n
    yarn --offline run build:res

    rm -rf node_modules/matrix-seshat node_modules/keytar
    ${lib.optionalString useKeytar "ln -s ${keytar} node_modules/keytar"}
    ln -s $seshat node_modules/matrix-seshat

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # resources
    mkdir -p "$out/share/element"
    ln -s '${element-web}' "$out/share/element/webapp"
    cp -r '.' "$out/share/element/electron"
    cp -r './res/img' "$out/share/element"
    rm -rf "$out/share/element/electron/node_modules"
    cp -r './node_modules' "$out/share/element/electron"
    cp $out/share/element/electron/lib/i18n/strings/en_EN.json $out/share/element/electron/lib/i18n/strings/en-us.json
    ln -s $out/share/element/electron/lib/i18n/strings/en{-us,}.json

    # icons
    for icon in $out/share/element/electron/build/icons/*.png; do
      mkdir -p "$out/share/icons/hicolor/$(basename $icon .png)/apps"
      ln -s "$icon" "$out/share/icons/hicolor/$(basename $icon .png)/apps/element.png"
    done

    # desktop item
    mkdir -p "$out/share"
    ln -s "${desktopItem}/share/applications" "$out/share/applications"

    # executable wrapper
    # LD_PRELOAD workaround for sqlcipher not found: https://github.com/matrix-org/seshat/issues/102
    makeWrapper '${electron}/bin/electron' "$out/bin/${executableName}" \
      --set LD_PRELOAD ${sqlcipher}/lib/libsqlcipher.so \
      --add-flags "$out/share/element/electron" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--enable-features=UseOzonePlatform --ozone-platform=wayland}}"

    runHook postInstall
  '';

  # The desktop item properties should be kept in sync with data from upstream:
  # https://github.com/vector-im/element-desktop/blob/develop/package.json
  desktopItem = makeDesktopItem {
    name = "element-desktop";
    exec = "${executableName} %u";
    icon = "element";
    desktopName = "Element";
    genericName = "Matrix Client";
    comment = meta.description;
    categories = [ "Network" "InstantMessaging" "Chat" ];
    startupWMClass = "element";
    mimeTypes = [ "x-scheme-handler/element" ];
  };

  passthru = {
    updateScript = ./update.sh;

    # TL;DR: keytar is optional while seshat isn't.
    #
    # This prevents building keytar when `useKeytar` is set to `false`, because
    # if libsecret is unavailable (e.g. set to `null` or fails to build), then
    # this package wouldn't even considered for building because
    # "one of the dependencies failed to build",
    # although the dependency wouldn't even be used.
    #
    # It needs to be `passthru` anyways because other packages do depend on it.
    inherit keytar;
  };

  meta = with lib; {
    description = "A feature-rich client for Matrix.org";
    homepage = "https://element.io/";
    changelog = "https://github.com/vector-im/element-desktop/blob/v${version}/CHANGELOG.md";
    license = licenses.asl20;
    maintainers = teams.matrix.members;
    inherit (electron.meta) platforms;
  };
}
