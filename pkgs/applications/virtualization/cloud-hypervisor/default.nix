{ lib, stdenv, fetchFromGitHub, rustPlatform, pkg-config, dtc, openssl }:

rustPlatform.buildRustPackage rec {
  pname = "cloud-hypervisor";
  version = "28.1";

  src = fetchFromGitHub {
    owner = "cloud-hypervisor";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-cAQWtud38TtDxxcb7eGpbtBDuvlSTYCk8jjgeZWo5QY=";
  };

  separateDebugInfo = true;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ] ++ lib.optional stdenv.isAarch64 dtc;

  cargoSha256 = "sha256-lo5FxiKGpJpDiai+n31K52VDGjA1d+RDjgtUW999Oag=";

  OPENSSL_NO_VENDOR = true;

  # Integration tests require root.
  cargoTestFlags = [ "--bins" ];

  meta = with lib; {
    homepage = "https://github.com/cloud-hypervisor/cloud-hypervisor";
    description = "Open source Virtual Machine Monitor (VMM) that runs on top of KVM";
    changelog = "https://github.com/cloud-hypervisor/cloud-hypervisor/releases/tag/v${version}";
    license = with licenses; [ asl20 bsd3 ];
    maintainers = with maintainers; [ offline qyliss ];
    platforms = [ "aarch64-linux" "x86_64-linux" ];
  };
}
