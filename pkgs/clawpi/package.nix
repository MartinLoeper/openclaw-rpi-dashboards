{ lib, buildGoModule, eww, makeWrapper }:

buildGoModule {
  pname = "clawpi";
  version = "0.2.0";

  src = lib.cleanSource ./.;

  vendorHash = "sha256-0Qxw+MUYVgzgWB8vi3HBYtVXSq/btfh4ZfV/m1chNrA=";

  nativeBuildInputs = [ makeWrapper ];

  ldflags = [ "-s" "-w" ];

  postInstall = ''
    mkdir -p $out/share/clawpi
    cp -r ${./eww} $out/share/clawpi/eww
    wrapProgram $out/bin/clawpi \
      --prefix PATH : ${lib.makeBinPath [ eww ]}
  '';

  meta = {
    description = "ClawPi overlay daemon — connects to OpenClaw gateway and drives Eww status overlays";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
