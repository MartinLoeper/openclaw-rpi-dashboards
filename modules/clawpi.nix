{ lib, pkgs, config, ... }:
let
  cfg = config.services.clawpi;
in
{
  options.services.clawpi = {
    debug = lib.mkEnableOption "extra debugging tools (speaker-test, etc.)";

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

    audio = {
      enable = lib.mkEnableOption "audio transcription via whisper.cpp";

      model = lib.mkOption {
        type = lib.types.enum [ "tiny" "base" "small" ];
        default = "base";
        description = ''
          Whisper model size. Trade-offs on RPi 5:
          - tiny:  fast (~0.3x real-time), lower accuracy
          - base:  balanced (~0.7x real-time), good for commands + sentences
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

      streaming = lib.mkOption {
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
    (lib.mkIf cfg.debug {
      environment.systemPackages = [ pkgs.alsa-utils ];
    })
    (lib.mkIf cfg.audio.enable {
      environment.systemPackages = [ pkgs.whisper-cpp pkgs.file pkgs.ffmpeg-headless ];
    })
  ];
}
