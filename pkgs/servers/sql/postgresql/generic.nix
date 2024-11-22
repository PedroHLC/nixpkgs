let

  generic =
      # utils
      { stdenv
      , fetchpatch
      , fetchurl
      , lib
      , substituteAll
      , writeShellScriptBin

      # source specification
      , hash
      , muslPatches ? {}
      , version

      # runtime dependencies
      , darwin
      , glibc
      , libuuid
      , libxml2
      , lz4
      , openssl
      , readline
      , tzdata
      , zlib
      , zstd

      # build dependencies
      , bison
      , docbook-xsl-nons
      , docbook_xml_dtd_45
      , flex
      , libxslt
      , makeWrapper
      , pkg-config
      , removeReferencesTo

      # passthru
      , buildEnv
      , newScope
      , nixosTests
      , postgresqlTestHook
      , self
      , stdenvNoCC
      , testers

      # GSSAPI
      , gssSupport ? with stdenv.hostPlatform; !isWindows && !isStatic
      , libkrb5

      # icu
      , icuSupport ? true
      , icu

      # JIT
      , jitSupport # not default on purpose, this is set via "_jit or not" attributes
      , llvmPackages
      , nukeReferences
      , overrideCC

      # LDAP
      , ldapSupport ? false
      , openldap

      # PAM
      , pamSupport ? stdenv.hostPlatform.isLinux
      , linux-pam

      # PL/Perl
      , perlSupport ? false
      , perl

      # PL/Python
      , pythonSupport ? false
      , python3

      # Systemd
      , systemdSupport ? lib.meta.availableOn stdenv.hostPlatform systemdLibs
      , systemdLibs
    } @args:
  let
    atLeast = lib.versionAtLeast version;
    olderThan = lib.versionOlder version;
    lz4Enabled = atLeast "14";
    zstdEnabled = atLeast "15";

    dlSuffix = if olderThan "16" then ".so" else stdenv.hostPlatform.extensions.sharedLibrary;

    pname = "postgresql";

    stdenv' =
      if jitSupport && !stdenv.cc.isClang then
        overrideCC llvmPackages.stdenv (llvmPackages.stdenv.cc.override {
          # LLVM bintools are not used by default, but are needed to make -flto work below.
          bintools = llvmPackages.bintools;
        })
      else
        stdenv;

    pg_config = writeShellScriptBin "pg_config" (builtins.readFile ./pg_config.sh);
  in stdenv'.mkDerivation (finalAttrs: {
    inherit version;
    pname = pname + lib.optionalString jitSupport "-jit";

    src = fetchurl {
      url = "mirror://postgresql/source/v${version}/${pname}-${version}.tar.bz2";
      inherit hash;
    };

    __structuredAttrs = true;

    hardeningEnable = lib.optionals (!stdenv'.cc.isClang) [ "pie" ];

    outputs = [ "out" "dev" "doc" "lib" "man" ];
    outputChecks.out = {
      disallowedReferences = [ "dev" "doc" "man" ];
      disallowedRequisites = [
        stdenv'.cc
      ] ++ (
        map lib.getDev (builtins.filter (drv: drv ? "dev") finalAttrs.buildInputs)
      ) ++ lib.optionals jitSupport [
        llvmPackages.llvm.out
      ];
    };
    outputChecks.lib = {
      disallowedReferences = [ "out" "dev" "doc" "man" ];
      disallowedRequisites = [
        stdenv'.cc
      ] ++ (
        map lib.getDev (builtins.filter (drv: drv ? "dev") finalAttrs.buildInputs)
      ) ++ lib.optionals jitSupport [
        llvmPackages.llvm.out
      ];
    };

    buildInputs = [
      zlib
      readline
      openssl
      (libxml2.override {enableHttp = true;})
      libuuid
    ]
      ++ lib.optionals icuSupport [ icu ]
      ++ lib.optionals jitSupport [ llvmPackages.llvm ]
      ++ lib.optionals lz4Enabled [ lz4 ]
      ++ lib.optionals zstdEnabled [ zstd ]
      ++ lib.optionals systemdSupport [ systemdLibs ]
      ++ lib.optionals pythonSupport [ python3 ]
      ++ lib.optionals gssSupport [ libkrb5 ]
      ++ lib.optionals pamSupport [ linux-pam ]
      ++ lib.optionals perlSupport [ perl ]
      ++ lib.optionals ldapSupport [ openldap ];

    nativeBuildInputs = [
      makeWrapper
      pkg-config
      removeReferencesTo
    ]
      ++ lib.optionals jitSupport [ llvmPackages.llvm.dev nukeReferences ]
      ++ lib.optionals (atLeast "17") [ bison flex perl docbook_xml_dtd_45 docbook-xsl-nons libxslt ];

    enableParallelBuilding = true;

    separateDebugInfo = true;

    buildFlags = [ "world" ];

    # libpgcommon.a and libpgport.a contain all paths returned by pg_config and are linked
    # into all binaries. However, almost no binaries actually use those paths. The following
    # flags will remove unused sections from all shared libraries and binaries - including
    # those paths. This avoids a lot of circular dependency problems with different outputs,
    # and allows splitting them cleanly.
    env.CFLAGS = "-fdata-sections -ffunction-sections"
      + (if stdenv'.cc.isClang then " -flto" else " -fmerge-constants -Wl,--gc-sections");

    configureFlags = let inherit (lib) withFeature; in [
      "--with-openssl"
      "--with-libxml"
      (withFeature icuSupport "icu")
      "--sysconfdir=/etc"
      "--with-system-tzdata=${tzdata}/share/zoneinfo"
      "--enable-debug"
      (lib.optionalString systemdSupport "--with-systemd")
      "--with-uuid=e2fs"
    ] ++ lib.optionals lz4Enabled [ "--with-lz4" ]
      ++ lib.optionals zstdEnabled [ "--with-zstd" ]
      ++ lib.optionals gssSupport [ "--with-gssapi" ]
      ++ lib.optionals pythonSupport [ "--with-python" ]
      ++ lib.optionals jitSupport [ "--with-llvm" ]
      ++ lib.optionals pamSupport [ "--with-pam" ]
      # This could be removed once the upstream issue is resolved:
      # https://postgr.es/m/flat/427c7c25-e8e1-4fc5-a1fb-01ceff185e5b%40technowledgy.de
      ++ lib.optionals (stdenv'.hostPlatform.isDarwin && atLeast "16") [ "LDFLAGS_EX_BE=-Wl,-export_dynamic" ]
      ++ lib.optionals (atLeast "17" && !perlSupport) [ "--without-perl" ]
      ++ lib.optionals ldapSupport [ "--with-ldap" ];

    patches = [
      (if atLeast "16" then ./patches/relative-to-symlinks-16+.patch else ./patches/relative-to-symlinks.patch)
      (if atLeast "15" then ./patches/empty-pg-config-view-15+.patch else ./patches/empty-pg-config-view.patch)
      ./patches/less-is-more.patch
      ./patches/paths-for-split-outputs.patch
      ./patches/paths-with-postgresql-suffix.patch

      (substituteAll {
        src = ./patches/locale-binary-path.patch;
        locale = "${if stdenv.hostPlatform.isDarwin then darwin.adv_cmds else lib.getBin stdenv.cc.libc}/bin/locale";
      })
    ] ++ lib.optionals stdenv'.hostPlatform.isMusl (
      # Using fetchurl instead of fetchpatch on purpose: https://github.com/NixOS/nixpkgs/issues/240141
      map fetchurl (lib.attrValues muslPatches)
    ) ++ lib.optionals stdenv'.hostPlatform.isLinux [
    ./patches/socketdir-in-run-13+.patch
    ] ++ lib.optionals (stdenv'.hostPlatform.isDarwin && olderThan "16") [
      ./patches/export-dynamic-darwin-15-.patch
    ];

    installTargets = [ "install-world" ];

    postPatch = ''
      substituteInPlace "src/Makefile.global.in" --subst-var out
      # Hardcode the path to pgxs so pg_config returns the path in $dev
      substituteInPlace "src/common/config_info.c" --subst-var dev
    '';

    postInstall =
      ''
        moveToOutput "bin/ecpg" "$dev"
        moveToOutput "lib/pgxs" "$dev"

        # Pretend pg_config is located in $out/bin to return correct paths, but
        # actually have it in -dev to avoid pulling in all other outputs. See the
        # pg_config.sh script's comments for details.
        moveToOutput "bin/pg_config" "$dev"
        install -c -m 755 "${pg_config}"/bin/pg_config "$out/bin/pg_config"
        wrapProgram "$dev/bin/pg_config" --argv0 "$out/bin/pg_config"

        # postgres exposes external symbols get_pkginclude_path and similar. Those
        # can't be stripped away by --gc-sections/LTO, because they could theoretically
        # be used by dynamically loaded modules / extensions. To avoid circular dependencies,
        # references to -dev, -doc and -man are removed here. References to -lib must be kept,
        # because there is a realistic use-case for extensions to locate the /lib directory to
        # load other shared modules.
        remove-references-to -t "$dev" -t "$doc" -t "$man" "$out/bin/postgres"

        if [ -z "''${dontDisableStatic:-}" ]; then
          # Remove static libraries in case dynamic are available.
          for i in $lib/lib/*.a; do
            name="$(basename "$i")"
            ext="${stdenv'.hostPlatform.extensions.sharedLibrary}"
            if [ -e "$lib/lib/''${name%.a}$ext" ] || [ -e "''${i%.a}$ext" ]; then
              rm "$i"
            fi
          done
        fi
        # The remaining static libraries are libpgcommon.a, libpgport.a and related.
        # Those are only used when building e.g. extensions, so go to $dev.
        moveToOutput "lib/*.a" "$dev"
      '' + lib.optionalString jitSupport ''
        # In the case of JIT support, prevent useless dependencies on header files
        find "$out/lib" -iname '*.bc' -type f -exec nuke-refs '{}' +

        # Stop lib depending on the -dev output of llvm
        remove-references-to -t ${llvmPackages.llvm.dev} "$out/lib/llvmjit${dlSuffix}"
      '';

    postFixup = lib.optionalString stdenv'.hostPlatform.isGnu
      ''
        # initdb needs access to "locale" command from glibc.
        wrapProgram $out/bin/initdb --prefix PATH ":" ${glibc.bin}/bin
      '';

    doCheck = !stdenv'.hostPlatform.isDarwin;
    # autodetection doesn't seem to able to find this, but it's there.
    checkTarget = "check-world";

    passthru = let
      this = self.callPackage generic args;
      jitToggle = this.override {
        jitSupport = !jitSupport;
      };
    in
    {
      inherit dlSuffix;

      psqlSchema = lib.versions.major version;

      withJIT = if jitSupport then this else jitToggle;
      withoutJIT = if jitSupport then jitToggle else this;

      pkgs = let
        scope = {
          inherit jitSupport;
          inherit (llvmPackages) llvm;
          postgresql = this;
          stdenv = stdenv';
          postgresqlTestExtension = { finalPackage, withPackages ? [], ... } @ extraArgs:
            stdenvNoCC.mkDerivation ({
              name = "${finalPackage.name}-test-extension";
              dontUnpack = true;
              doCheck = true;
              nativeCheckInputs = [
                postgresqlTestHook
                (this.withPackages (ps: [ finalPackage ] ++ (map (p: ps."${p}") withPackages)))
              ];
              failureHook = "postgresqlStop";
              postgresqlTestUserOptions = "LOGIN SUPERUSER";
              passAsFile = [ "sql" ];
              checkPhase = ''
                runHook preCheck
                psql -a -v ON_ERROR_STOP=1 -f "$sqlPath"
                runHook postCheck
              '';
              installPhase = "touch $out";
            } // extraArgs);
          buildPostgresqlExtension = newSuper.callPackage ./buildPostgresqlExtension.nix {};
        };
        newSelf = self // scope;
        newSuper = { callPackage = newScope (scope // this.pkgs); };
      in import ./ext newSelf newSuper;

      withPackages = postgresqlWithPackages {
                       inherit buildEnv;
                       postgresql = this;
                     };

      tests = {
        postgresql = nixosTests.postgresql.postgresql.passthru.override finalAttrs.finalPackage;
        postgresql-tls-client-cert = nixosTests.postgresql.postgresql-tls-client-cert.passthru.override finalAttrs.finalPackage;
        postgresql-wal-receiver = nixosTests.postgresql.postgresql-wal-receiver.passthru.override finalAttrs.finalPackage;
        pkg-config = testers.testMetaPkgConfig finalAttrs.finalPackage;
      } // lib.optionalAttrs jitSupport {
        postgresql-jit = nixosTests.postgresql.postgresql-jit.passthru.override finalAttrs.finalPackage;
      };
    };

    meta = with lib; {
      homepage    = "https://www.postgresql.org";
      description = "Powerful, open source object-relational database system";
      license     = licenses.postgresql;
      changelog   = "https://www.postgresql.org/docs/release/${finalAttrs.version}/";
      maintainers = with maintainers; [ globin ivan ] ++ teams.postgres.members;
      pkgConfigModules = [ "libecpg" "libecpg_compat" "libpgtypes" "libpq" ];
      platforms   = platforms.unix;

      # JIT support doesn't work with cross-compilation. It is attempted to build LLVM-bytecode
      # (`%.bc` is the corresponding `make(1)`-rule) for each sub-directory in `backend/` for
      # the JIT apparently, but with a $(CLANG) that can produce binaries for the build, not the
      # host-platform.
      #
      # I managed to get a cross-build with JIT support working with
      # `depsBuildBuild = [ llvmPackages.clang ] ++ buildInputs`, but considering that the
      # resulting LLVM IR isn't platform-independent this doesn't give you much.
      # In fact, I tried to test the result in a VM-test, but as soon as JIT was used to optimize
      # a query, postgres would coredump with `Illegal instruction`.
      broken = jitSupport && !stdenv.hostPlatform.canExecute stdenv.buildPlatform;
    };
  });

  postgresqlWithPackages = { postgresql, buildEnv }: f: let
    installedExtensions = f postgresql.pkgs;
  in buildEnv {
    name = "${postgresql.pname}-and-plugins-${postgresql.version}";
    paths = installedExtensions ++ [
        postgresql
        postgresql.man   # in case user installs this into environment
    ];

    pathsToLink = ["/"];

    passthru = {
      inherit installedExtensions;
      inherit (postgresql)
        psqlSchema
        version
      ;

      withJIT = postgresqlWithPackages {
        inherit buildEnv;
        postgresql = postgresql.withJIT;
      } f;
      withoutJIT = postgresqlWithPackages {
        inherit buildEnv;
        postgresql = postgresql.withoutJIT;
      } f;
    };
  };

in
# passed by <major>.nix
versionArgs:
# passed by default.nix
{ self, ... } @defaultArgs:
self.callPackage generic (defaultArgs // versionArgs)
