{
  autoreconfHook,
  coreutils,
  fetchFromGitHub,
  gnugrep,
  gnused,
  lib,
  makeWrapper,
  perlPackages,
  stdenv,
}:

let
  generic =
    {
      pname,
      version,
      src,
      description,
      buildInputs,
    }:
    stdenv.mkDerivation {
      inherit pname version src;

      buildInputs = [ perlPackages.perl ] ++ buildInputs;

      nativeBuildInputs = [
        autoreconfHook
        makeWrapper
      ];

      postPatch = ''
        substituteInPlace plugins-scripts/Makefile.am \
          --replace-fail /bin/cat  ${lib.getExe' coreutils "cat"} \
          --replace-fail /bin/echo ${lib.getExe' coreutils "echo"} \
          --replace-fail /bin/grep ${lib.getExe gnugrep} \
          --replace-fail /bin/sed  ${lib.getExe gnused}
      '';

      postInstall = ''
        if [[ -d $out/libexec ]]; then
          ln -sr $out/libexec $out/bin
        fi
      '';

      postFixup = ''
        for f in $out/bin/* ; do
          wrapProgram $f --prefix PERL5LIB : $PERL5LIB
        done
      '';

      meta = {
        homepage = "https://labs.consol.de/";
        license = lib.licenses.gpl2Only;
        maintainers = with lib.maintainers; [ peterhoeg ];
        inherit description;
      };
    };

in
{
  check_mssql_health = generic rec {
    pname = "check-mssql-health";
    version = "2.7.7";

    src = fetchFromGitHub {
      owner = "lausser";
      repo = "check_mssql_health";
      rev = "refs/tags/${version}";
      hash = "sha256-K6sGrms9z59a9rkZNulwKBexGF2Nkqqak/cRg12ynxc=";
      fetchSubmodules = true;
    };

    description = "Check plugin for Microsoft SQL Server";
    buildInputs = [ perlPackages.DBDsybase ];
  };

  check_nwc_health = generic {
    pname = "check-nwc-health";
    version = "7.10.0.6";
    sha256 = "092rhaqnk3403z0y60x38vgh65gcia3wrd6gp8mr7wszja38kxv2";
    description = "Check plugin for network equipment";
    buildInputs = [ perlPackages.NetSNMP ];
  };

  check_ups_health = generic {
    pname = "check-ups-health";
    version = "2.8.3.3";
    sha256 = "0qc2aglppwr9ms4p53kh9nr48625sqrbn46xs0k9rx5sv8hil9hm";
    description = "Check plugin for UPSs";
    buildInputs = [ perlPackages.NetSNMP ];
  };
}
