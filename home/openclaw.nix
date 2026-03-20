{ pkgs, osConfig, lib, ... }:
let
  skillsCfg = osConfig.services.clawpi.skills;
  audioCfg = osConfig.services.clawpi.audio;
  groqCfg = osConfig.services.clawpi.audio.groq;
  debugCfg = osConfig.services.clawpi.debug;
  canvasCfg = osConfig.services.clawpi.canvas;
  canvasDir = if canvasCfg.tmpfs then "/tmp/clawpi-canvas" else "/var/lib/kiosk/.openclaw/canvas";
  canvasArchiveDir = "/var/lib/kiosk/.openclaw/canvas-archive";
  cartesiaCfg = osConfig.services.clawpi.cartesia;
  elevenlabsCfg = osConfig.services.clawpi.elevenlabs;
  powerCfg = osConfig.services.clawpi.powerControl;
  mxCfg = osConfig.services.clawpi.matrix;
  tgCfg = osConfig.services.clawpi.telegram;
  allowedModelsCfg = osConfig.services.clawpi.allowedModels;

  # Append ClawPi-specific instructions to the agent's AGENTS.md at service start.
  # Uses a marker comment so the block is only injected once and updated in-place on redeploy.
  hwCfg = osConfig.services.clawpi.agent.documents.hardwareAwareness;
  clawpiAgentsExtra = builtins.readFile ../documents/AGENTS.md;
  clawpiBlock = lib.concatStringsSep "\n" (
    [ clawpiAgentsExtra ]
    ++ lib.optional hwCfg.enable hwCfg.spec
  );
  clawpiBlockFile = pkgs.writeText "clawpi-agents-block.md" ''
    <!-- BEGIN CLAWPI — managed by Nix, do NOT edit or remove this block -->
    ${clawpiBlock}
    <!-- END CLAWPI -->
  '';
  patchAgentsScript = pkgs.writeShellScript "patch-agents-md" ''
    agentsFile="$HOME/.openclaw/workspace/AGENTS.md"
    # Recreate AGENTS.md if the agent (or something else) deleted it
    if [ ! -f "$agentsFile" ]; then
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$agentsFile")"
      ${pkgs.coreutils}/bin/echo "# AGENTS" > "$agentsFile"
    fi
    # Strip old block (handles both intact markers and orphaned single markers)
    ${pkgs.gnused}/bin/sed -i '/<!-- BEGIN CLAWPI -->/,/<!-- END CLAWPI -->/d' "$agentsFile"
    ${pkgs.gnused}/bin/sed -i '/<!-- BEGIN CLAWPI/d;/<!-- END CLAWPI/d' "$agentsFile"
    ${pkgs.coreutils}/bin/cat ${clawpiBlockFile} >> "$agentsFile"
  '';

  whisperModel = pkgs.whisper-model.override { model = audioCfg.model; };

  # Local transcription: convert to WAV then run whisper-cli
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

  # Groq cloud transcription: send audio directly (supports .ogg natively)
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

  log = msg: lib.optionalString debugCfg
    ''echo "[whisper-transcribe] ${msg}" >&2'';

  # Wrapper that transcribes audio. Tries Groq first (if enabled), falls back to local whisper.
  whisperWrapper = pkgs.writeShellScript "whisper-transcribe" ''
    input="$1"
    rc=1
    ${log "input=$input"}
    # Show transcribing indicator (ignore errors if eww isn't running)
    ${pkgs.eww}/bin/eww update clawpi_state=transcribing 2>/dev/null || true
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
    # Fall back to local whisper-cli if Groq failed or is disabled
    if [ "$rc" -ne 0 ]; then
      ${log "using local whisper-cli (model=${audioCfg.model})"}
      ${localTranscribe}
      ${log "local whisper-cli exited with rc=$rc"}
    fi
    # Clear indicator (the clawpi daemon will take over with "thinking" once the agent starts)
    ${pkgs.eww}/bin/eww update clawpi_state=idle 2>/dev/null || true
    exit $rc
  '';

  # JSON snippet to inject tools.media config for whisper-cli transcription.
  # The typed Nix config schema doesn't expose tools.media.models, so we
  # patch openclaw.json via ExecStartPre before the gateway reads it.
  whisperMediaConfig = builtins.toJSON {
    tools.media.audio = {
      enabled = true;
      language = audioCfg.language;
      models = [
        {
          type = "cli";
          command = "${whisperWrapper}";
          args = [
            "{{MediaPath}}"
          ];
          timeoutSeconds = audioCfg.timeoutSeconds;
        }
      ];
    };
  };

  whisperMediaConfigFile = pkgs.writeText "openclaw-media-config.json" whisperMediaConfig;

  # Build the agents.defaults.models allowlist for openclaw.json.
  # See https://docs.openclaw.ai/concepts/models#model-is-not-allowed
  modelsAllowlist = lib.optionalAttrs (allowedModelsCfg != []) {
    agents.defaults.models = builtins.listToAttrs (map (m: {
      name = m.id;
      value = { alias = m.name; };
    }) allowedModelsCfg);
  };

  modelsAllowlistFile = pkgs.writeText "openclaw-models-allowlist.json"
    (builtins.toJSON modelsAllowlist);

  patchModelsScript = pkgs.writeShellScript "patch-openclaw-models" ''
    configFile="$HOME/.openclaw/openclaw.json"
    if [ -f "$configFile" ]; then
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$configFile" "${modelsAllowlistFile}" > "$configFile.tmp" \
        && ${pkgs.coreutils}/bin/mv "$configFile.tmp" "$configFile"
    fi
  '';

  patchConfigScript = pkgs.writeShellScript "patch-openclaw-audio" ''
    configFile="$HOME/.openclaw/openclaw.json"
    if [ -f "$configFile" ]; then
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$configFile" "${whisperMediaConfigFile}" > "$configFile.tmp" \
        && ${pkgs.coreutils}/bin/mv "$configFile.tmp" "$configFile"
    fi
  '';

  # Build the channels.matrix config as JSON for runtime patching.
  # Matrix is not yet in the upstream nix-openclaw Zod schema, so we
  # inject it via jq in ExecStartPre (same pattern as tools.media.audio).
  matrixChannelConfig = lib.optionalAttrs mxCfg.enable ({
    channels.matrix = {
      enabled = true;
      homeserver = mxCfg.homeserver;
    }
    // lib.optionalAttrs mxCfg.encryption { encryption = true; }
    // { dm = { policy = mxCfg.dm.policy; }
         // lib.optionalAttrs (mxCfg.dm.allowFrom != [ ]) { allowFrom = mxCfg.dm.allowFrom; };
       }
    // lib.optionalAttrs (mxCfg.requireMention != null) { requireMention = mxCfg.requireMention; }
    // lib.optionalAttrs (mxCfg.groupPolicy != null) { groupPolicy = mxCfg.groupPolicy; }
    // lib.optionalAttrs (mxCfg.groupAllowFrom != [ ]) { groupAllowFrom = mxCfg.groupAllowFrom; }
    // lib.optionalAttrs (mxCfg.groups != { }) { groups = mxCfg.groups; }
    // lib.optionalAttrs (mxCfg.autoJoin != null) { autoJoin = mxCfg.autoJoin; }
    // lib.optionalAttrs (mxCfg.autoJoinAllowlist != [ ]) { autoJoinAllowlist = mxCfg.autoJoinAllowlist; }
    // lib.optionalAttrs (mxCfg.threadReplies != null) { threadReplies = mxCfg.threadReplies; }
    // lib.optionalAttrs (mxCfg.replyToMode != null) { replyToMode = mxCfg.replyToMode; }
    // lib.optionalAttrs (mxCfg.actions.reactions != null || mxCfg.actions.sendMessage != null) {
      actions = {}
        // lib.optionalAttrs (mxCfg.actions.reactions != null) { reactions = mxCfg.actions.reactions; }
        // lib.optionalAttrs (mxCfg.actions.sendMessage != null) { sendMessage = mxCfg.actions.sendMessage; };
    };
  });

  matrixConfigFile = pkgs.writeText "openclaw-matrix-config.json"
    (builtins.toJSON matrixChannelConfig);

  patchMatrixScript = pkgs.writeShellScript "patch-openclaw-matrix" ''
    configFile="$HOME/.openclaw/openclaw.json"
    tokenFile="${toString mxCfg.accessTokenFile}"
    if [ -f "$configFile" ] && [ -f "$tokenFile" ]; then
      token="$(${pkgs.coreutils}/bin/cat "$tokenFile")"
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$configFile" "${matrixConfigFile}" \
        | ${pkgs.jq}/bin/jq --arg tok "$token" '.channels.matrix.accessToken = $tok' \
        > "$configFile.tmp" \
        && ${pkgs.coreutils}/bin/mv "$configFile.tmp" "$configFile"
    fi
  '';

  # Build the channels.telegram attrset only when enabled.
  telegramChannel = lib.mkIf tgCfg.enable {
    tokenFile = tgCfg.tokenFile;
    allowFrom = lib.mkIf (tgCfg.allowFrom != [ ]) tgCfg.allowFrom;
    groupPolicy = lib.mkIf (tgCfg.groupPolicy != null) tgCfg.groupPolicy;
    groups."*".requireMention = tgCfg.requireMentionInGroups;
    replyToMode = lib.mkIf (tgCfg.replyToMode != null) tgCfg.replyToMode;
    reactionLevel = lib.mkIf (tgCfg.reactionLevel != null) tgCfg.reactionLevel;
    reactionNotifications = lib.mkIf (tgCfg.reactionNotifications != null) tgCfg.reactionNotifications;
    ackReaction = lib.mkIf (tgCfg.ackReaction != null) tgCfg.ackReaction;
    actions = lib.mkIf (tgCfg.actions.reactions != null || tgCfg.actions.sendMessage != null || tgCfg.actions.sticker != null) {
      reactions = lib.mkIf (tgCfg.actions.reactions != null) tgCfg.actions.reactions;
      sendMessage = lib.mkIf (tgCfg.actions.sendMessage != null) tgCfg.actions.sendMessage;
      sticker = lib.mkIf (tgCfg.actions.sticker != null) tgCfg.actions.sticker;
    };
    streaming = lib.mkIf (tgCfg.streaming != null) tgCfg.streaming;
    blockStreaming = lib.mkIf (tgCfg.blockStreaming != null) tgCfg.blockStreaming;
  };

  # Runtime patching: append user IDs from allowFromFile to channels.telegram.allowFrom.
  patchTelegramAllowFromScript = pkgs.writeShellScript "patch-openclaw-telegram-allowfrom" ''
    configFile="$HOME/.openclaw/openclaw.json"
    allowFile="${toString tgCfg.allowFromFile}"
    if [ -f "$configFile" ] && [ -f "$allowFile" ]; then
      ids="$(${pkgs.coreutils}/bin/cat "$allowFile" | ${pkgs.gnused}/bin/sed '/^$/d' | ${pkgs.jq}/bin/jq -R 'tonumber' | ${pkgs.jq}/bin/jq -s '.')"
      ${pkgs.jq}/bin/jq --argjson ids "$ids" '.channels.telegram.allowFrom = ((.channels.telegram.allowFrom // []) + $ids | unique)' \
        "$configFile" > "$configFile.tmp" \
        && ${pkgs.coreutils}/bin/mv "$configFile.tmp" "$configFile"
    fi
  '';
in
{
  # The gateway overwrites openclaw.json at runtime, which conflicts with
  # Home Manager's file management. Force overwrite to prevent activation failures.
  home.file.".openclaw/openclaw.json".force = true;

  programs.openclaw = {
    enable = true;
    package = pkgs.openclaw-gateway;
    skills = lib.optionals skillsCfg.enable [
      {
        name = "video-watcher";
        description = "Fetch and read transcripts from YouTube and Bilibili videos.";
        mode = "copy";
        source = "${pkgs.clawpi-skills}/share/clawpi-skills/video-watcher";
      }
    ];
    config = {
      gateway = {
        mode = "local";
      };
      channels.telegram = telegramChannel;
      browser = {
        attachOnly = true;
        defaultProfile = "kiosk";
        profiles = {
          kiosk = {
            cdpUrl = "http://127.0.0.1:9222";
            driver = "clawd";
            color = "#FF4500";
          };
        };
      };
      # Disable built-in canvas; we include our own canvas implementation via clawpi-tools
      canvasHost.enabled = false;
      plugins = {
        enabled = true;
        allow = [ "clawpi-tools" "memory-core" ];
        load.paths = [
          "${pkgs.clawpi-tools}/lib/clawpi-tools"
        ];
        entries.clawpi-tools = {
          enabled = true;
          config = {};
        };
      };
    };
  };

  systemd.user.services.openclaw-gateway-token = {
    Unit.Description = "Generate OpenClaw gateway token";
    Install.WantedBy = [ "default.target" ];
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = toString (pkgs.writeShellScript "gen-openclaw-token" ''
        tokenFile="$HOME/.openclaw/gateway-token.env"
        mkdir -p "$HOME/.openclaw"
        if [ ! -f "$tokenFile" ]; then
          echo "OPENCLAW_GATEWAY_TOKEN=$(${pkgs.openssl}/bin/openssl rand -hex 32)" > "$tokenFile"
          chmod 600 "$tokenFile"
        fi
      '');
    };
  };

  systemd.user.services.openclaw-gateway = {
    Unit = {
      After = [ "openclaw-gateway-token.service" ];
      Requires = [ "openclaw-gateway-token.service" ];
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      EnvironmentFile = "/var/lib/kiosk/.openclaw/gateway-token.env";
      Environment =
        [ "CLAWPI_CANVAS_DIR=${canvasDir}" "CLAWPI_CANVAS_ARCHIVE_DIR=${canvasArchiveDir}" ]
        ++ lib.optional debugCfg "OPENCLAW_LOG_LEVEL=debug"
        ++ lib.optionals cartesiaCfg.enable [
          "CLAWPI_CARTESIA_API_KEY_FILE=${toString cartesiaCfg.apiKeyFile}"
          "CLAWPI_CARTESIA_VOICE=${cartesiaCfg.voice}"
          "CLAWPI_CARTESIA_MODEL=${cartesiaCfg.model}"
        ]
        ++ lib.optionals elevenlabsCfg.enable [
          "CLAWPI_ELEVENLABS_API_KEY_FILE=${toString elevenlabsCfg.apiKeyFile}"
          "CLAWPI_ELEVENLABS_VOICE=${elevenlabsCfg.voice}"
          "CLAWPI_ELEVENLABS_MODEL=${elevenlabsCfg.model}"
        ]
        ++ lib.optional powerCfg.enable "CLAWPI_POWER_CONTROL=1";
      ExecStartPre = [ (toString patchAgentsScript) ]
        ++ lib.optional audioCfg.enable (toString patchConfigScript)
        ++ lib.optional (allowedModelsCfg != []) (toString patchModelsScript)
        ++ lib.optional mxCfg.enable (toString patchMatrixScript)
        ++ lib.optional (tgCfg.enable && tgCfg.allowFromFile != null) (toString patchTelegramAllowFromScript);
    };
  };

  # The HM openclaw module generates the gateway unit without [Install],
  # so our Install.WantedBy above doesn't take effect. Work around by
  # creating a helper service that is properly enabled and starts the gateway.
  systemd.user.services.openclaw-gateway-start = {
    Unit = {
      Description = "Start OpenClaw gateway";
      Wants = [ "openclaw-gateway.service" ];
      After = [ "openclaw-gateway-token.service" ];
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = toString (pkgs.writeShellScript "start-openclaw-gateway" ''
        ${pkgs.systemd}/bin/systemctl --user start openclaw-gateway.service
      '');
    };
  };
}
