{ lib, stdenvNoCC }:

stdenvNoCC.mkDerivation {
  pname = "hey-claw-model";
  version = "0.1.0";

  srcs = [
    ./hey_claw.onnx
    ./hey_claw.onnx.data
  ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/share/openwakeword/models
    for src in $srcs; do
      local name="$(stripHash "$src")"
      cp "$src" "$out/share/openwakeword/models/$name"
    done
  '';

  meta = {
    description = "Custom 'hey claw' wake word model for openWakeWord";
    license = lib.licenses.asl20;
  };
}
