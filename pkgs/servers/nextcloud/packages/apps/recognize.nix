{
  stdenv,
  fetchurl,
  lib,
  nodejs,
  python311,
  util-linux,
  ffmpeg,
}:
stdenv.mkDerivation rec {
  pname = "nextcloud-app-recognise";
  version = "8.1.1";

  srcs = [
    (fetchurl {
      inherit version;
      url = "https://github.com/nextcloud/recognize/releases/download/v${version}/recognize-${version}.tar.gz";
      hash = "sha256-RIa2HzX2hfgS7KHGGBsxEdUCqDqXeAs3Xi288qA1gU4=";
    })

    (fetchurl {
      inherit version;
      url = "https://github.com/nextcloud/recognize/archive/refs/tags/v${version}.tar.gz";
      hash = "sha256-op1Fdm40d8V6V+rfne0ECr60xRjBYrBPrCD3kaNeFfY=";
    })
    (fetchurl rec {
      # For version see LIBTENSORFLOW_VERSION in https://github.com/tensorflow/tfjs/blob/master/tfjs-node/scripts/deps-constants.js
      version = "2.9.1";
      url = "https://storage.googleapis.com/tensorflow/libtensorflow/libtensorflow-cpu-linux-x86_64-${version}.tar.gz";
      hash = "sha256-f1ENJUbj214QsdEZRjaJAD1YeEKJKtPJW8pRz4KCAXM=";
    })

  ];

  unpackPhase = ''
    # Merge the app and the models from github
    tar -xzpf "${builtins.elemAt srcs 0}" recognize;
    tar -xzpf "${builtins.elemAt srcs 1}" -C recognize --strip-components=1 recognize-${version}/models

    # Place the tensorflow lib at the right place for building
    tar -xzpf "${builtins.elemAt srcs 2}" -C recognize/node_modules/@tensorflow/tfjs-node/deps
  '';

  patchPhase = ''
    # Make it clear we are not reading the node in settings
    sed -i "/'node_binary'/s:'""':'Nix Controled':" recognize/lib/Service/SettingsService.php

    # Replace all occurences of node (and check that we actually remved them all)
    test "$(grep "get[a-zA-Z]*('node_binary'" recognize/lib/**/*.php | wc -l)" -gt 0
    substituteInPlace recognize/lib/**/*.php \
      --replace-quiet "\$this->settingsService->getSetting('node_binary')" "'${nodejs}/bin/node'" \
      --replace-quiet "\$this->config->getAppValueString('node_binary', '""')" "'${nodejs}/bin/node'" \
      --replace-quiet "\$this->config->getAppValueString('node_binary')" "'${nodejs}/bin/node'"
    test "$(grep "get[a-zA-Z]*('node_binary'" recognize/lib/**/*.php | wc -l)" -eq 0



    # Skip trying to install it... (less warnings in the log)
    sed  -i '/public function run/areturn ; //skip' recognize/lib/Migration/InstallDeps.php

    ln -s ${ffmpeg}/bin/ffmpeg recognize/node_modules/ffmpeg-static/ffmpeg
  '';

  buildInputs = [
    nodejs
    nodejs.pkgs.node-pre-gyp
    nodejs.pkgs.node-gyp
    python311
    util-linux
  ];
  buildPhase = ''
    cd recognize

    # Install tfjs dependency
    export CPPFLAGS="-I${nodejs}/include/node -Ideps/include"
    cd node_modules/@tensorflow/tfjs-node
    node-pre-gyp install --prefer-offline --build-from-source --nodedir=${nodejs}/include/node
    cd -

    # Test tfjs returns exit code 0
    ${nodejs}/bin/node src/test_libtensorflow.js
    cd ..
  '';
  installPhase = ''
    approot="$(dirname $(dirname $(find -path '*/appinfo/info.xml' | head -n 1)))"
    if [ -d "$approot" ];
    then
      mv "$approot/" $out
      chmod -R a-w $out
    fi
  '';

  meta = with lib; {
    license = licenses.agpl3Only;
    maintainers = with maintainers; [ beardhatcode ];
    longDescription = ''
      Nextcloud app that does Smart media tagging and face recognition with on-premises machine learning models.
      This app goes through your media collection and adds fitting tags, automatically categorizing your photos and music.
    '';
    homepage = "https://apps.nextcloud.com/apps/recognize";
  };
}
