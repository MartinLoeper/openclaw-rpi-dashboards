{ pkgs, osConfig, lib, ... }:
let
  voiceCfg = osConfig.services.clawpi.voice;
  gatewayCfg = osConfig.services.clawpi.gateway;
  audioCfg = osConfig.services.clawpi.audio;
  debugCfg = osConfig.services.clawpi.debug;

  whisperModel = pkgs.whisper-model.override { model = audioCfg.model; };

  whisperCmd = pkgs.writeShellScript "voice-whisper" ''
    input="$1"
    wav="''${input%.*}.wav"
    ${pkgs.ffmpeg-headless}/bin/ffmpeg -y -i "$input" -ar 16000 -ac 1 -c:a pcm_s16le "$wav" 2>/dev/null
    ${pkgs.whisper-cpp}/bin/whisper-cli \
      -m "${whisperModel}" \
      -l "${audioCfg.language}" \
      -np --no-gpu \
      "$wav" 2>/dev/null
    rc=$?
    ${pkgs.coreutils}/bin/rm -f "$wav"
    exit $rc
  '';
in
lib.mkIf voiceCfg.enable {
  systemd.user.services.clawpi-voice-pipeline = {
    Unit = {
      Description = "ClawPi voice pipeline (hotword + STT)";
      After = [ "pipewire.service" "openclaw-gateway.service" ];
      Requires = [ "pipewire.service" ];
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStart = "${pkgs.clawpi-voice-pipeline}/bin/clawpi-voice-pipeline";
      Restart = "always";
      RestartSec = 5;
      EnvironmentFile = "/var/lib/kiosk/.openclaw/gateway-token.env";
      Environment = [
        "CLAWPI_GATEWAY_URL=${gatewayCfg.url}"
        "CLAWPI_WAKEWORD_THRESHOLD=${toString voiceCfg.threshold}"
        "CLAWPI_SILENCE_TIMEOUT=${toString voiceCfg.silenceTimeout}"
        "CLAWPI_MAX_RECORD_SECS=${toString voiceCfg.maxRecordSeconds}"
        "CLAWPI_WHISPER_CMD=${whisperCmd}"
      ] ++ lib.optional (voiceCfg.wakewordModel != null)
        "CLAWPI_WAKEWORD_MODEL=${voiceCfg.wakewordModel}"
      ++ lib.optional debugCfg "CLAWPI_DEBUG=true";
    };
  };
}
