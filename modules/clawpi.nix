{ lib, pkgs, config, ... }:
let
  cfg = config.services.clawpi;
in
{
  options.services.clawpi = {
    skills.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the ClawPi skill bundle (video-watcher and more).";
    };

    debug = lib.mkEnableOption "extra debugging tools and verbose logging";

    gateway = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "ws://localhost:18789";
        description = "OpenClaw gateway WebSocket URL.";
      };
      tokenFile = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/kiosk/.openclaw/gateway-token.env";
        description = ''
          Path to the gateway token file. The file should contain a line
          `OPENCLAW_GATEWAY_TOKEN=<hex>`. Generated automatically on first boot.
        '';
      };
    };

    web = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 3100;
        description = "Port for the ClawPi landing page HTTP server.";
      };
    };

    agent.documents = {
      hardwareAwareness = {
        enable = lib.mkEnableOption "hardware description in the agent's AGENTS.md";

        spec = lib.mkOption {
          type = lib.types.lines;
          default = ''
            ## Hardware

            - **Device:** Raspberry Pi 5B (8GB RAM, Cortex-A76 quad-core)
            - **Display:** 10-inch IPS touchscreen, 1280x800, connected via HDMI
            - **Audio output:** HDMI audio via PipeWire (speaker bar)
            - **Microphone:** USB microphone on the speaker bar (low gain — best for close range)
            - **Browser:** Chromium in kiosk mode (labwc Wayland compositor), controlled via CDP on port 9222
            - **Network:** Ethernet and Wi-Fi, discoverable as `openclaw-rpi5.local` via mDNS

            You are in app mode — always use the browser `navigate` action to change pages. Never open new windows (this stacks windows inside the compositor and is not recoverable without restart).
          '';
          description = ''
            Markdown text describing the hardware setup. Injected into the
            agent's AGENTS.md when hardwareAwareness is enabled.
          '';
        };
      };
    };

    allowedModels = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          id = lib.mkOption {
            type = lib.types.str;
            description = ''
              Fully qualified model ID including provider prefix.
              Examples: "anthropic/claude-haiku-4-5", "openrouter/moonshotai/kimi-k2.5".
            '';
          };
          name = lib.mkOption {
            type = lib.types.str;
            description = "Human-readable model alias.";
          };
        };
      });
      default = [];
      description = ''
        Models to allow in the agent's allowlist (agents.defaults.models in openclaw.json).
        Use the full provider/model-id format. When non-empty, only these models can be used.
        See https://docs.openclaw.ai/concepts/models#model-is-not-allowed
      '';
    };

    canvas = {
      tmpfs = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether the canvas workspace lives on tmpfs (cleared on reboot)
          or inside the agent's persistent workspace directory.

          - true  → /tmp/clawpi-canvas (volatile, auto-cleaned)
          - false → /var/lib/kiosk/.openclaw/canvas (survives reboots)
        '';
      };
    };

    audio = {
      enable = lib.mkEnableOption "audio transcription via whisper.cpp";

      model = lib.mkOption {
        type = lib.types.enum [ "tiny" "base" "small" ];
        default = "tiny";
        description = ''
          Whisper model size. Trade-offs on RPi 5:
          - tiny:  fast (~0.3x real-time), good enough for voice commands
          - base:  balanced (~0.7x real-time), better accuracy
          - small: slow (~2-3x real-time), best accuracy
        '';
      };

      language = lib.mkOption {
        type = lib.types.str;
        default = "auto";
        description = "Spoken language code (e.g. 'en', 'de') or 'auto' for auto-detect.";
      };

      timeoutSeconds = lib.mkOption {
        type = lib.types.int;
        default = 60;
        description = "Timeout in seconds for transcription.";
      };

      groq = {
        enable = lib.mkEnableOption "Groq cloud transcription (whisper-large-v3-turbo) with local fallback";

        apiKeyFile = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/clawpi/groq-api-key";
          description = ''
            Path to a file containing the Groq API key.
            Provision with: ./scripts/provision-groq.sh
          '';
        };

        model = lib.mkOption {
          type = lib.types.str;
          default = "whisper-large-v3-turbo";
          description = "Groq transcription model.";
        };
      };
    };

    elevenlabs = {
      enable = lib.mkEnableOption "ElevenLabs cloud TTS (tts_hq tool)";

      apiKeyFile = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/clawpi/elevenlabs-api-key";
        description = ''
          Path to a file containing the ElevenLabs API key.
          Provision with: ./scripts/provision-elevenlabs.sh
        '';
      };

      voice = lib.mkOption {
        type = lib.types.str;
        default = "eokb0hhuVX3JuAiUKucB";
        description = ''
          Default ElevenLabs voice ID.
        '';
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "eleven_v3";
        description = ''
          ElevenLabs model ID.
        '';
      };
    };

    powerControl = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Allow the agent to control display power (on/off) and shut down
          the system. Grants the kiosk user passwordless sudo for poweroff
          and exposes the display_power and system_poweroff tools.
        '';
      };
    };

    matrix = {
      enable = lib.mkEnableOption "Matrix channel for the OpenClaw agent";

      homeserver = lib.mkOption {
        type = lib.types.str;
        default = "https://matrix.org";
        description = "Homeserver URL (e.g. https://matrix.example.org).";
      };

      accessTokenFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/clawpi/matrix-access-token";
        description = ''
          Path to a file containing the Matrix access token.
          Provision with: ./scripts/provision-matrix.sh
        '';
      };

      encryption = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable end-to-end encryption (E2EE).";
      };

      dm = {
        policy = lib.mkOption {
          type = lib.types.enum [ "pairing" "allowlist" "open" "disabled" ];
          default = "pairing";
          description = "DM acceptance policy.";
        };

        allowFrom = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Matrix user IDs allowed to DM the bot (e.g. "@user:example.org").
            Only used when dm.policy is "allowlist".
          '';
        };
      };

      groupPolicy = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "allowlist" "open" "disabled" ]);
        default = null;
        description = "Group/room message policy. null uses the gateway default.";
      };

      groupAllowFrom = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Matrix user IDs allowed to trigger the bot in rooms.";
      };

      groups = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            allow = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Allow the bot in this room.";
            };
            requireMention = lib.mkOption {
              type = lib.types.nullOr lib.types.bool;
              default = null;
              description = "Require @bot mention in this room. null uses global default.";
            };
          };
        });
        default = { };
        description = ''
          Per-room settings keyed by room ID (!id:server) or alias (#alias:server).
        '';
      };

      autoJoin = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "always" "allowlist" "off" ]);
        default = null;
        description = "Auto-join behaviour for room invites. null uses the gateway default.";
      };

      autoJoinAllowlist = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Room IDs/aliases the bot may auto-join (when autoJoin is 'allowlist').";
      };

      threadReplies = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "off" "inbound" "always" ]);
        default = null;
        description = "Thread reply behaviour. null uses the gateway default.";
      };

      replyToMode = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "off" "first" "all" ]);
        default = null;
        description = "Whether the bot replies to the original message. null uses the gateway default.";
      };

      actions = {
        reactions = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Allow the bot to react to messages.";
        };
        sendMessage = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Allow the bot to send messages.";
        };
      };
    };

    telegram = {
      enable = lib.mkEnableOption "Telegram channel for the OpenClaw agent";

      tokenFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/clawpi/telegram-bot-token";
        description = ''
          Path to a file containing the Telegram bot token.
          Create the bot via @BotFather on Telegram.
          Provision with: ./scripts/provision-telegram.sh
        '';
      };

      allowFrom = lib.mkOption {
        type = lib.types.listOf (lib.types.oneOf [ lib.types.str lib.types.int ]);
        default = [ ];
        description = ''
          Telegram user or group IDs allowed to interact with the bot.
          Get your user ID from @userinfobot on Telegram.
        '';
      };

      requireMentionInGroups = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Require @bot mention in group chats before the agent responds.";
      };

      groupPolicy = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "allowlist" "open" "disabled" ]);
        default = null;
        description = "Group message policy. null uses the gateway default (allowlist).";
      };

      streaming = lib.mkOption;
        type = lib.types.nullOr (lib.types.oneOf [
          lib.types.bool
          (lib.types.enum [ "off" "partial" "block" "progress" ])
        ]);
        default = null;
        description = "Streaming mode for responses. null uses the gateway default.";
      };

      blockStreaming = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Enable block streaming. null uses the gateway default.";
      };

      replyToMode = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "off" "first" "all" ]);
        default = null;
        description = "Whether the bot replies to the original message. null uses the gateway default.";
      };

      reactionLevel = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "off" "ack" "minimal" "extensive" ]);
        default = null;
        description = "Emoji reaction level on incoming messages. null uses the gateway default.";
      };

      reactionNotifications = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "off" "own" "all" ]);
        default = null;
        description = "Which reaction notifications to show. null uses the gateway default.";
      };

      ackReaction = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Emoji reaction sent when the bot acknowledges an incoming message.";
      };

      actions = {
        reactions = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Allow the bot to react to messages.";
        };
        sendMessage = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Allow the bot to send messages.";
        };
        sticker = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Allow the bot to send stickers.";
        };
      };
    };
  };

  config = lib.mkMerge [
    {
      # alsa-utils provides speaker-test, used by the audio_test_tone plugin tool
      # wf-recorder provides Wayland screen recording, used by screen_record_start/stop
      # wlr-randr provides Wayland output control, used by display_power tool
      # git is used by the agent for version-controlling canvas projects
      environment.systemPackages = [ pkgs.alsa-utils pkgs.wf-recorder pkgs.wlr-randr pkgs.git ];
    }
    (lib.mkIf cfg.audio.enable {
      environment.systemPackages = [ pkgs.whisper-cpp pkgs.file pkgs.ffmpeg-headless ]
        ++ lib.optionals cfg.audio.groq.enable [ pkgs.curl ];
    })
    (lib.mkIf cfg.skills.enable {
      # video-watcher skill needs yt-dlp and python3
      environment.systemPackages = [ pkgs.yt-dlp pkgs.python3 ];
    })
    (lib.mkIf cfg.powerControl.enable {
      # Allow kiosk user to run poweroff without a password
      security.sudo.extraRules = [
        {
          users = [ "kiosk" ];
          commands = [
            { command = "/run/current-system/sw/bin/poweroff"; options = [ "NOPASSWD" ]; }
            { command = "/run/current-system/sw/bin/reboot"; options = [ "NOPASSWD" ]; }
          ];
        }
      ];
    })
  ];
}
