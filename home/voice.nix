{ pkgs, osConfig, lib, ... }:
let
  voiceCfg = osConfig.services.clawpi.voice;
  gatewayCfg = osConfig.services.clawpi.gateway;
  audioCfg = osConfig.services.clawpi.audio;
  groqCfg = osConfig.services.clawpi.audio.groq;
  debugCfg = osConfig.services.clawpi.debug;

  # Resolve wake word model path: explicit model > assistantName lookup > none
  assistantModels = {
    claw = "${pkgs.hey-claw-model}/share/openwakeword/models/hey_claw.onnx";
    jarvis = null;  # uses bundled model in openwakeword package
  };
  resolvedModel =
    if voiceCfg.wakewordModel != null then voiceCfg.wakewordModel
    else assistantModels.${voiceCfg.assistantName} or null;

  whisperModel = pkgs.whisper-model.override { model = audioCfg.model; };

  log = msg: lib.optionalString debugCfg
    ''echo "[voice-whisper] ${msg}" >&2'';

  # Groq cloud transcription
  groqTranscribe = ''
    groq_key=""
    if [ -f "${toString groqCfg.apiKeyFile}" ]; then
      groq_key="$(${pkgs.coreutils}/bin/cat "${toString groqCfg.apiKeyFile}")"
    fi
    if [ -n "$groq_key" ]; then
      groq_result="$(${pkgs.curl}/bin/curl -sf \
        --max-time ${toString audioCfg.timeoutSeconds} \
        https://api.groq.com/openai/v1/audio/transcriptions \
        -H "Authorization: Bearer $groq_key" \
        -F "file=@$input" \
        -F "model=${groqCfg.model}" \
        -F "response_format=text"${lib.optionalString (audioCfg.language != "auto") ''
        -F "language=${audioCfg.language}"''} 2>/dev/null)" && \
      [ -n "$groq_result" ] && {
        echo "$groq_result"
        rc=0
      }
    fi
  '';

  # Local whisper-cli fallback
  localTranscribe = ''
    wav="''${input%.*}.wav"
    ${pkgs.ffmpeg-headless}/bin/ffmpeg -y -i "$input" -ar 16000 -ac 1 -c:a pcm_s16le "$wav" 2>/dev/null
    ${pkgs.whisper-cpp}/bin/whisper-cli \
      -m "${whisperModel}" \
      -l "${audioCfg.language}" \
      -np --no-gpu \
      "$wav" 2>/dev/null
    rc=$?
    ${pkgs.coreutils}/bin/rm -f "$wav"
  '';

  whisperCmd = pkgs.writeShellScript "voice-whisper" ''
    input="$1"
    rc=1
    ${log "input=$input"}
    ${lib.optionalString groqCfg.enable ''
    ${log "trying Groq (${groqCfg.model})..."}
    ${groqTranscribe}
    if [ "$rc" -eq 0 ]; then
      ${log "Groq succeeded"}
      :
    else
      ${log "Groq failed, falling back to local whisper"}
      :
    fi
    ''}
    if [ "$rc" -ne 0 ]; then
      ${log "using local whisper-cli (model=${audioCfg.model})"}
      ${localTranscribe}
      ${log "local whisper-cli exited with rc=$rc"}
    fi
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
      ] ++ lib.optional (resolvedModel != null)
        "CLAWPI_WAKEWORD_MODEL=${resolvedModel}"
      ++ lib.optional debugCfg "CLAWPI_DEBUG=true";
    };
  };
}
