{ lib, buildGoModule, makeWrapper }:

buildGoModule {
  pname = "clawpi";
  version = "0.4.4";

  src = lib.cleanSource ./.;

  vendorHash = "sha256-0Qxw+MUYVgzgWB8vi3HBYtVXSq/btfh4ZfV/m1chNrA=";

  nativeBuildInputs = [ makeWrapper ];

  ldflags = [ "-s" "-w" ];

  postInstall = ''
    mkdir -p $out/share/clawpi
    cp -r ${./quickshell} $out/share/clawpi/quickshell
    wrapProgram $out/bin/clawpi
  '';

  meta = {
    description = "ClawPi overlay daemon — connects to OpenClaw gateway and drives Quickshell border animations";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
