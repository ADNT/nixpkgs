{ lib
, stdenv
, buildGoModule
, fetchFromGitHub
}:

buildGoModule rec {
  pname = "cdk-go";
  version = "1.4.1";

  src = fetchFromGitHub {
    owner = "cdk-team";
    repo = "CDK";
    rev = "v${version}";
    sha256 = "sha256-OeQlepdHu5+rGEhw3x0uM1wy7/8IkA5Lh5k3yhytXwY=";
  };

  vendorSha256 = "sha256-aJN/d/BxmleRXKw6++k6e0Vb0Gs5zg1QfakviABYTog=";

  # At least one test is outdated
  doCheck = false;

  meta = with lib; {
    description = "Container penetration toolkit";
    homepage = "https://github.com/cdk-team/CDK";
    license = with licenses; [ gpl2Only ];
    maintainers = with maintainers; [ fab ];
    mainProgram = "cdk";
    broken = stdenv.isDarwin; # needs to update gopsutil to at least v3.21.3 to include https://github.com/shirou/gopsutil/pull/1042
  };
}
