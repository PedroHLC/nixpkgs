{
  appdirs,
  appnope,
  black,
  build,
  clang-tools,
  click,
  colorama,
  coloredlogs,
  coverage,
  cryptography,
  diskcache,
  fetchFromGitHub,
  glib,
  gn,
  googleapis-common-protos,
  google-cloud-storage,
  ipython,
  jinja2,
  json5,
  jsonschema,
  lark,
  lib,
  libnl,
  mobly,
  mypy,
  mypy-extensions,
  mypy-protobuf,
  ninja,
  openssl,
  packaging,
  parameterized,
  pip-tools,
  pkg-config,
  prompt-toolkit,
  protobuf,
  psutil,
  ptpython,
  pyelftools,
  pygments,
  pykwalify,
  pylint,
  pyperclip,
  pyserial,
  python3,
  python-daemon,
  pyyaml,
  requests,
  setuptools,
  six,
  sphinx,
  sphinx-argparse,
  sphinx-design,
  stdenv,
  stringcase,
  toml,
  tornado,
  types-protobuf,
  types-pyyaml,
  types-requests,
  types-setuptools,
  watchdog,
  websockets,
  wheel,
  yapf,
  zap-chip,
}:

stdenv.mkDerivation rec {
  pname = "home-assistant-chip-wheels";
  version = "2024.9.0";
  src = fetchFromGitHub {
    owner = "home-assistant-libs";
    repo = "chip-wheels";
    rev = version;
    fetchSubmodules = false;
    leaveDotGit = true;
    hash = "sha256-T0G6mxb/5wFOxPLL92Ay34oP+9Xvk9w0YV9VSzWJuzw=";
    postFetch = ''
      cd $out
      # Download connectedhomeip.
      git fetch
      git reset --hard HEAD
      git submodule update --init --depth 1 connectedhomeip

      # Initialize only necessary submodules.
      cd connectedhomeip
      ${python3}/bin/python3 scripts/checkout_submodules.py --platform linux --shallow

      # Keep the output deterministic.
      cd $out
      # in case python decided to leave a .pyc file, for example
      git clean -fxd
      rm -rf .git/
    '';
  };

  strictDeps = true;

  nativeBuildInputs = [
    gn
    pkg-config
    ninja
    clang-tools
    zap-chip
    # gdbus-codegen
    glib
    python3
    # dependencies of build scripts
    click
    jinja2
    lark
    setuptools
    stringcase
    build
    pip-tools
    black
    yapf
  ];

  propagatedBuildInputs = [
    openssl
    glib
    libnl
  ];

  postPatch = ''
    cd connectedhomeip
    export HOME=$(mktemp -d)

    patchShebangs --build scripts

    for patch in ../*.patch; do
      patch -p1 < $patch
    done

    # unpin dependencies
    # there are many files to modify, in different formats
    sed -i 's/==.*$//' third_party/pigweed/repo/pw_env_setup/py/pw_env_setup/virtualenv_setup/python_base_requirements.txt
    sed -i 's/==[^;]*//' scripts/setup/constraints.txt
    sed -i 's/\(^ \+[a-zA-Z0-9-]*\)[=~><]=[^;]*/\1/' third_party/pigweed/repo/pw_protobuf_compiler/py/setup.cfg third_party/pigweed/repo/pw_protobuf/py/setup.cfg third_party/pigweed/repo/pw_protobuf_compiler/py/setup.cfg
    # remove a few dependencies not packaged in nixpkgs and which are apparently
    # not needed to build the python bindings of chip
    sed -i -e '/sphinxcontrib-mermaid/d' -e '/types-six/d' -e '/types-pygment/d' -e '/types-pyserial/d' third_party/pigweed/repo/*/py/setup.cfg

    # obtained by running a build in nix-shell with internet access
    cp ${./pigweed_environment.gni} build_overrides/pigweed_environment.gni

    # some code is generated by a templating tool (zap-cli)
    scripts/codepregen.py ./zzz_pregenerated/
  '';

  # the python parts of the build system work as follows
  # gn calls pigweed to read a dozen different files to generate
  # a file looking like requirements.txt. It then calls pip
  # to install this computed list of dependencies into a virtualenv.
  # Of course, pip fails in the sandbox, because it cannot download
  # the python packages.
  # The documented way of doing offline builds is to create a folder
  # with wheel files for all dependencies and point pip to it
  # via its configuration file or environment variables.
  # https://pigweed.dev/python_build.html#installing-offline
  # The wheel of a python package foo is available as foo.dist.
  # So that would be easy, but we also need wheels for transitive dependencies.
  # the function saturateDependencies below computes this transitive closure.
  #
  # yes this list of dependencies contains both build tools and proper dependencies.
  env.PIP_NO_INDEX = "1";
  env.PIP_FIND_LINKS =
    let
      dependencies = [
        appdirs
        appnope
        black
        build
        colorama
        coloredlogs
        coverage
        click
        cryptography
        diskcache
        googleapis-common-protos
        google-cloud-storage
        ipython
        jinja2
        json5
        jsonschema
        lark
        mobly
        mypy
        mypy-extensions
        mypy-protobuf
        packaging
        parameterized
        pip-tools
        prompt-toolkit
        protobuf
        psutil
        ptpython
        pyelftools
        pygments
        pykwalify
        pylint
        pyperclip
        pyserial
        python-daemon
        pyyaml
        requests
        setuptools
        six
        sphinx
        sphinx-argparse
        sphinx-design
        stringcase
        toml
        tornado
        types-protobuf
        types-pyyaml
        types-requests
        types-setuptools
        watchdog
        websockets
        wheel
        yapf
      ];
      depListToAttrs =
        list:
        builtins.listToAttrs (
          map (dep: {
            name = dep.name;
            value = dep;
          }) (lib.filter (x: x != null) list)
        );
      saturateDependencies =
        deps:
        let
          before = deps;
          new = lib.mergeAttrsList (
            map (dep: depListToAttrs (dep.propagatedBuildInputs or [ ])) (lib.attrValues before)
          );
          after = before // new;
        in
        if lib.attrNames before != lib.attrNames after then saturateDependencies after else before;
      saturateDependencyList = list: lib.attrValues (saturateDependencies (depListToAttrs list));
      saturatedDependencyList = lib.filter (drv: drv ? dist) (saturateDependencyList dependencies);
    in
    lib.concatMapStringsSep " " (dep: "file://${dep.dist}") saturatedDependencyList;

  gnFlags = [
    ''chip_project_config_include_dirs=["//.."]''
    ''chip_crypto="openssl"''
    ''enable_rtti=true''
    ''chip_config_memory_debug_checks=false''
    ''chip_config_memory_debug_dmalloc=false''
    ''chip_mdns="minimal"''
    ''chip_minmdns_default_policy="libnl"''
    ''chip_python_version="${lib.versions.majorMinor python3.version}"''
    ''chip_python_platform_tag="any"''
    ''chip_python_package_prefix="home-assistant-chip"''
    ''custom_toolchain="custom"''
    ''target_cc="${stdenv.cc.targetPrefix}cc"''
    ''target_cxx="${stdenv.cc.targetPrefix}c++"''
    ''target_ar="${stdenv.cc.targetPrefix}ar"''
  ];

  preBuild = ''
    export NIX_CFLAGS_COMPILE="$($PKG_CONFIG --cflags glib-2.0) -O2 -Wno-error"
    export NIX_CFLAGS_LINK="$($PKG_CONFIG --libs gio-2.0) $($PKG_CONFIG --libs gobject-2.0) $($PKG_CONFIG --libs glib-2.0)"
  '';

  ninjaFlags = [ "chip-repl" ];

  installPhase = ''
    runHook preInstall

    cp -r controller/python $out

    runHook postInstall
  '';

  meta = {
    description = "Python wheels for APIs and tools related to CHIP";
    homepage = "https://github.com/home-assistant-libs/chip-wheels";
    changelog = "https://github.com/home-assistant-libs/chip-wheels/releases/tag/${version}";
    license = lib.licenses.asl20;
    maintainers = lib.teams.home-assistant.members;
  };

}
