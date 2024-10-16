{
  lib,
  stdenv,
  alsa-lib,
  config,
  darwin,
  dbus,
  fetchFromGitHub,
  libpulseaudio,
  libxcb,
  ncspot,
  ncurses,
  nix-update-script,
  openssl,
  pkg-config,
  portaudio,
  python3,
  rustPlatform,
  testers,
  ueberzug,
  withALSA ? stdenv.hostPlatform.isLinux,
  withClipboard ? true,
  withCover ? false,
  withCrossterm ? true,
  withMPRIS ? stdenv.hostPlatform.isLinux,
  withNotify ? true,
  withPortAudio ? stdenv.hostPlatform.isDarwin,
  withPulseAudio ? config.pulseaudio or stdenv.hostPlatform.isLinux,
}:

rustPlatform.buildRustPackage rec {
  pname = "ncspot";
  version = "1.1.2";

  src = fetchFromGitHub {
    owner = "hrkfdn";
    repo = "ncspot";
    rev = "refs/tags/v${version}";
    hash = "sha256-Lt2IuoiXYgSVPi4u8y16u9m5ya4HdpQme6snvNJrwso=";
  };

  cargoHash = "sha256-JJTnaq0JLWHQxAbDpzDRPi5B+ePlQNlDOAsugPah7j4=";

  nativeBuildInputs = [ pkg-config ] ++ lib.optional withClipboard python3;

  buildInputs =
    [ ncurses ]
    ++ lib.optional stdenv.hostPlatform.isLinux openssl
    ++ lib.optional withALSA alsa-lib
    ++ lib.optional withClipboard libxcb
    ++ lib.optional withCover ueberzug
    ++ lib.optional withPulseAudio libpulseaudio
    ++ lib.optional withPortAudio portaudio
    ++ lib.optional (withMPRIS || withNotify) dbus
    ++ lib.optional stdenv.hostPlatform.isDarwin darwin.apple_sdk.frameworks.Cocoa;

  env.NIX_CFLAGS_COMPILE = lib.optionalString stdenv.hostPlatform.isDarwin "-DNCURSES_UNCTRL_H_incl";

  buildNoDefaultFeatures = true;

  buildFeatures =
    [ "cursive/pancurses-backend" ]
    ++ lib.optional withALSA "alsa_backend"
    ++ lib.optional withClipboard "share_clipboard"
    ++ lib.optional withCover "cover"
    ++ lib.optional withCrossterm "crossterm_backend"
    ++ lib.optional withMPRIS "mpris"
    ++ lib.optional withNotify "notify"
    ++ lib.optional withPortAudio "portaudio_backend"
    ++ lib.optional withPulseAudio "pulseaudio_backend";

  postInstall = ''
    install -D --mode=444 $src/misc/ncspot.desktop $out/share/applications/nscpot.desktop
    install -D --mode=444 $src/images/logo.svg $out/share/icons/hicolor/scalable/apps/nscpot.png
  '';

  passthru = {
    tests.version = testers.testVersion { package = ncspot; };
    updateScript = nix-update-script { };
  };

  meta = {
    description = "Cross-platform ncurses Spotify client written in Rust, inspired by ncmpc and the likes";
    homepage = "https://github.com/hrkfdn/ncspot";
    changelog = "https://github.com/hrkfdn/ncspot/releases/tag/v${version}";
    license = lib.licenses.bsd2;
    maintainers = with lib.maintainers; [ liff ];
    mainProgram = "ncspot";
  };
}
