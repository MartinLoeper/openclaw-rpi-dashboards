{ lib, pkgs, config, ... }:
let
  cfg = config.services.clawpi.voice;
in
{
  options.services.clawpi.voice = {
    enable = lib.mkEnableOption "voice pipeline (hotword detection + speech-to-text)";

    wakewordModel = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a custom wake word model file (.onnx or .tflite).
        When null, the bundled "hey jarvis" ONNX model is used.
      '';
    };

    threshold = lib.mkOption {
      type = lib.types.float;
      default = 0.8;
      description = "Wake word detection threshold (0.0–1.0). Lower = more sensitive.";
    };

    silenceTimeout = lib.mkOption {
      type = lib.types.float;
      default = 1.5;
      description = "Seconds of silence before stopping speech recording.";
    };

    maxRecordSeconds = lib.mkOption {
      type = lib.types.float;
      default = 15.0;
      description = "Maximum speech recording duration in seconds.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.clawpi-voice-pipeline ];
  };
}
