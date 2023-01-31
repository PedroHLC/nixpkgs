{ config
, elk7Version
, enableUnfree ? true
, lib
, stdenv
, fetchurl
, makeWrapper
, nixosTests
, jre
}:

let
  info = lib.splitString "-" stdenv.hostPlatform.system;
  arch = lib.elemAt info 0;
  plat = lib.elemAt info 1;
  hashes =
    if enableUnfree
    then {
      x86_64-linux  = "sha256-+WTecRHm+wT5JGnk0kMqqaJgQqsUkOquGMgNIwIzEys=";
      x86_64-darwin = "sha256-DeadBeeFDeadBeeFCoFeeC0feeDeadBeefC0feeAAAB=";
      aarch64-linux = "sha256-IPpf/d5iASPIWTHfw5KnUBsAZ0mSwGm8R48BbVIPUAY=";
    }
    else {
      x86_64-linux  = "sha256-PdYulR0kIkjDv9inmjkM9fLfDG53jmLmLs0sjRtBPCs=";
      x86_64-darwin = "sha256-DeadBeeFDeadBeeFCoFeeC0feeDeadBeefC0feeAAAE=";
      aarch64-linux = "sha256-9Vfuqoo75yYapuYofVbTVdZzOJdSOjuwAjPRQ7YnD1E=";
    };
  this = stdenv.mkDerivation rec {
    version = elk7Version;
    pname = "logstash${lib.optionalString (!enableUnfree) "-oss"}";


    src = fetchurl {
      url = "https://artifacts.elastic.co/downloads/logstash/${pname}-${version}-${plat}-${arch}.tar.gz";
      hash = hashes.${stdenv.hostPlatform.system} or (throw "Unknown architecture");
    };

    dontBuild = true;
    dontPatchELF = true;
    dontStrip = true;
    dontPatchShebangs = true;

    nativeBuildInputs = [
      makeWrapper
    ];

    buildInputs = [
      jre
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r {Gemfile*,modules,vendor,lib,bin,config,data,logstash-core,logstash-core-plugin-api} $out

      patchShebangs $out/bin/logstash
      patchShebangs $out/bin/logstash-plugin

      wrapProgram $out/bin/logstash \
         --set JAVA_HOME "${jre}"

      wrapProgram $out/bin/logstash-plugin \
         --set JAVA_HOME "${jre}"
      runHook postInstall
    '';

    meta = with lib; {
      description = "Logstash is a data pipeline that helps you process logs and other event data from a variety of systems";
      homepage = "https://www.elastic.co/products/logstash";
      sourceProvenance = with sourceTypes; [
        fromSource
        binaryBytecode  # source bundles dependencies as jars
        binaryNativeCode  # bundled jruby includes native code
      ];
      license = if enableUnfree then licenses.elastic else licenses.asl20;
      platforms = platforms.unix;
      maintainers = with maintainers; [ wjlroe offline basvandijk ];
    };
    passthru.tests =
      lib.optionalAttrs (config.allowUnfree && enableUnfree) (
        assert this.drvPath == nixosTests.elk.unfree.ELK-7.elkPackages.logstash.drvPath;
        {
          elk = nixosTests.elk.unfree.ELK-7;
        }
      );
  };
in
this
