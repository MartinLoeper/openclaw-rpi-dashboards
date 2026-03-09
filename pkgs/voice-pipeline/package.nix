{ lib
, python3
, makeWrapper
, pipewire
, callPackage
, stdenvNoCC
}:

let
  openwakeword = callPackage ./openwakeword.nix { };

  pythonEnv = python3.withPackages (ps: [
    openwakeword
    ps.numpy
    ps.websockets
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "clawpi-voice-pipeline";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 voice-pipeline.py $out/bin/clawpi-voice-pipeline
    wrapProgram $out/bin/clawpi-voice-pipeline \
      --prefix PATH : "${lib.makeBinPath [ pipewire ]}" \
      --set PYTHONPATH "${pythonEnv}/${python3.sitePackages}"
    # Fix shebang to use the wrapped python
    substituteInPlace $out/bin/.clawpi-voice-pipeline-wrapped \
      --replace-fail "#!/usr/bin/env python3" "#!${pythonEnv}/bin/python3"
    runHook postInstall
  '';

  meta = {
    description = "ClawPi voice pipeline — hotword detection and speech-to-text";
    license = lib.licenses.mit;
    mainProgram = "clawpi-voice-pipeline";
  };
}
