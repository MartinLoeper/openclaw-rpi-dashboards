{ lib, ... }:
{
  options.services.clawpi = {
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
    };
  };
}
