{
  description = "ClawPi — AI-powered smart display appliance for Raspberry Pi 5";

  inputs = {
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
    nix-openclaw.url = "github:MartinLoeper/nix-openclaw/main";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nix-openclaw/nixpkgs";
  };

  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs =
    {
      self,
      nixos-raspberrypi,
      nix-openclaw,
      home-manager,
      ...
    }:
    let
      # Hardware-independent application modules shared by all configs
      commonModules = [
        {
          nixpkgs.overlays = [
            nix-openclaw.overlays.default
            (import ./overlays/openclaw-gateway-fix.nix)
            (import ./overlays/clawpi.nix)
          ];
        }
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.users.kiosk = {
            imports = [
              nix-openclaw.homeManagerModules.openclaw
              ./home/openclaw.nix
              ./home/clawpi.nix
              ./home/labwc.nix
              ./home/voice.nix
            ];
            home.stateVersion = "25.05";
          };
        }
        ./modules/base.nix
        ./modules/kiosk.nix
        ./modules/clawpi.nix
        ./modules/voice.nix
      ];

      # Raspberry Pi 5 hardware modules
      pi5Modules = [
        {
          imports = with nixos-raspberrypi.nixosModules; [
            raspberry-pi-5.base
            raspberry-pi-5.page-size-16k
            raspberry-pi-5.display-vc4
          ];
          boot.loader.raspberry-pi.bootloader = "kernel";
          networking.hostName = "openclaw-rpi5";
        }
      ];

      # Raspberry Pi 4 hardware modules
      pi4Modules = [
        {
          imports = with nixos-raspberrypi.nixosModules; [
            raspberry-pi-4.base
            raspberry-pi-4.display-vc4
          ];
          boot.loader.raspberry-pi.bootloader = "uboot";
          networking.hostName = "openclaw-rpi4";
        }
      ];

      specialArgs = { inherit nixos-raspberrypi; };

      # Installer-specific modules (shared between Pi 4 and Pi 5 installer configs)
      installerModules = [
        nixos-raspberrypi.nixosModules.sd-image
        "${nixos-raspberrypi.inputs.nixpkgs}/nixos/modules/profiles/installation-device.nix"
        {
          boot.swraid.enable = nixos-raspberrypi.inputs.nixpkgs.lib.mkForce false;
          installer.cloneConfig = false;
        }
      ];
    in
    {
      # For ongoing deploys via nixos-rebuild (./deploy.sh)
      nixosConfigurations.rpi5 = nixos-raspberrypi.lib.nixosSystem {
        inherit specialArgs;
        modules = pi5Modules ++ commonModules;
      };

      # Raspberry Pi 4B — for ongoing deploys
      nixosConfigurations.rpi4 = nixos-raspberrypi.lib.nixosSystem {
        inherit specialArgs;
        modules = pi4Modules ++ commonModules;
      };

      # With Telegram channel + audio transcription enabled
      nixosConfigurations.rpi5-telegram = nixos-raspberrypi.lib.nixosSystem {
        inherit specialArgs;
        modules =
          pi5Modules
          ++ commonModules
          ++ [
            {
              services.clawpi.agent.documents.hardwareAwareness.enable = true;
              services.clawpi.canvas.tmpfs = false;
              services.clawpi.audio.enable = true;
              services.clawpi.audio.groq.enable = true;
              services.clawpi.elevenlabs.enable = true;
              services.clawpi.voice.enable = true;
              services.clawpi.voice.threshold = 0.25;
              services.clawpi.allowedModels = [
                # Anthropic
                {
                  id = "anthropic/claude-sonnet-4-5";
                  name = "Sonnet 4.5";
                }
                {
                  id = "anthropic/claude-haiku-4-5";
                  name = "Haiku 4.5";
                }
                # OpenRouter
                {
                  id = "openrouter/moonshotai/kimi-k2.5";
                  name = "Kimi K2.5";
                }
                {
                  id = "openrouter/minimax/minimax-m2.5";
                  name = "MiniMax M2.5";
                }
                {
                  id = "openrouter/google/gemini-2.5-flash-lite";
                  name = "Gemini 2.5 Flash Lite";
                }
              ];
              services.clawpi.telegram = {
                enable = true;

                # Workaround for https://github.com/openclaw/openclaw/issues/34790
                # Both properties prevent partial message edits in Telegram.
                # Revert streaming to "partial" and blockStreaming to null once fixed.
                streaming = "block";
                blockStreaming = true;

                # Personal preference: full reactions and reply-to-all
                replyToMode = "all";
                ackReaction = "👀";
                reactionLevel = "extensive";
                reactionNotifications = "all";
                actions = {
                  reactions = true;
                  sendMessage = true;
                  sticker = true;
                };
              };
            }
          ];
      };

      # Raspberry Pi 4B with Telegram channel + audio transcription
      nixosConfigurations.rpi4-telegram = nixos-raspberrypi.lib.nixosSystem {
        inherit specialArgs;
        modules =
          pi4Modules
          ++ commonModules
          ++ [
            {
              services.clawpi.agent.documents.hardwareAwareness.enable = true;
              services.clawpi.canvas.tmpfs = false;
              services.clawpi.audio.enable = true;
              services.clawpi.audio.groq.enable = true;
              services.clawpi.elevenlabs.enable = true;
              # Voice pipeline disabled — too heavy for Pi 4B (continuous ONNX hotword detection)
              # services.clawpi.voice.enable = true;
              # services.clawpi.voice.threshold = 0.25;
              services.clawpi.allowedModels = [
                # Anthropic
                {
                  id = "anthropic/claude-sonnet-4-5";
                  name = "Sonnet 4.5";
                }
                {
                  id = "anthropic/claude-haiku-4-5";
                  name = "Haiku 4.5";
                }
                # OpenRouter
                {
                  id = "openrouter/moonshotai/kimi-k2.5";
                  name = "Kimi K2.5";
                }
                {
                  id = "openrouter/minimax/minimax-m2.5";
                  name = "MiniMax M2.5";
                }
                {
                  id = "openrouter/google/gemini-2.5-flash-lite";
                  name = "Gemini 2.5 Flash Lite";
                }
              ];
              services.clawpi.telegram = {
                enable = true;
                streaming = "block";
                blockStreaming = true;
                replyToMode = "all";
                ackReaction = "👀";
                reactionLevel = "extensive";
                reactionNotifications = "all";
                actions = {
                  reactions = true;
                  sendMessage = true;
                  sticker = true;
                };
              };
            }
          ];
      };

      # Telegram + debug tools (speaker-test, etc.)
      nixosConfigurations.rpi5-telegram-debug = nixos-raspberrypi.lib.nixosSystem {
        inherit specialArgs;
        modules =
          pi5Modules
          ++ commonModules
          ++ [
            {
              services.clawpi.debug = true;
              services.clawpi.agent.documents.hardwareAwareness.enable = true;
              services.clawpi.canvas.tmpfs = false;
              services.clawpi.audio.enable = true;
              services.clawpi.audio.groq.enable = true;
              services.clawpi.elevenlabs.enable = true;
              services.clawpi.voice.enable = true;
              services.clawpi.voice.threshold = 0.25;
              services.clawpi.allowedModels = [
                # Anthropic
                {
                  id = "anthropic/claude-sonnet-4-5";
                  name = "Sonnet 4.5";
                }
                {
                  id = "anthropic/claude-haiku-4-5";
                  name = "Haiku 4.5";
                }
                # OpenRouter
                {
                  id = "openrouter/moonshotai/kimi-k2.5";
                  name = "Kimi K2.5";
                }
                {
                  id = "openrouter/minimax/minimax-m2.5";
                  name = "MiniMax M2.5";
                }
                {
                  id = "openrouter/google/gemini-2.5-flash-lite";
                  name = "Gemini 2.5 Flash Lite";
                }
              ];
              services.clawpi.telegram = {
                enable = true;

                # Workaround for https://github.com/openclaw/openclaw/issues/34790
                streaming = "block";
                blockStreaming = true;

                # Personal preference
                replyToMode = "all";
                ackReaction = "👀";
                reactionLevel = "extensive";
                reactionNotifications = "all";
                actions = {
                  reactions = true;
                  sendMessage = true;
                  sticker = true;
                };
              };
            }
          ];
      };

      # Matrix + debug tools
      nixosConfigurations.rpi5-matrix-debug = nixos-raspberrypi.lib.nixosSystem {
        inherit specialArgs;
        modules =
          pi5Modules
          ++ commonModules
          ++ [
            {
              services.clawpi.debug = true;
              services.clawpi.agent.documents.hardwareAwareness.enable = true;
              services.clawpi.canvas.tmpfs = false;
              services.clawpi.audio.enable = true;
              services.clawpi.audio.groq.enable = true;
              services.clawpi.elevenlabs.enable = true;
              services.clawpi.voice.enable = true;
              services.clawpi.voice.threshold = 0.25;
              services.clawpi.allowedModels = [
                # Anthropic
                {
                  id = "anthropic/claude-sonnet-4-5";
                  name = "Sonnet 4.5";
                }
                {
                  id = "anthropic/claude-haiku-4-5";
                  name = "Haiku 4.5";
                }
                # OpenRouter
                {
                  id = "openrouter/moonshotai/kimi-k2.5";
                  name = "Kimi K2.5";
                }
                {
                  id = "openrouter/minimax/minimax-m2.5";
                  name = "MiniMax M2.5";
                }
                {
                  id = "openrouter/google/gemini-2.5-flash-lite";
                  name = "Gemini 2.5 Flash Lite";
                }
              ];
              services.clawpi.matrix = {
                enable = true;
                homeserver = "https://matrix.glinq.org";
                encryption = true;
                dm.policy = "pairing";
                requireMention = true;
                groupPolicy = "open";
                replyToMode = "all";
                actions = {
                  reactions = true;
                  sendMessage = true;
                };
              };
            }
          ];
      };

      # Raspberry Pi 4B — Matrix + Telegram + debug tools
      nixosConfigurations.rpi4-matrix-debug = nixos-raspberrypi.lib.nixosSystem {
        inherit specialArgs;
        modules =
          pi4Modules
          ++ commonModules
          ++ [
            {
              services.clawpi.debug = true;
              services.clawpi.agent.documents.hardwareAwareness.enable = true;
              services.clawpi.canvas.tmpfs = false;
              services.clawpi.audio.enable = true;
              services.clawpi.audio.groq.enable = true;
              services.clawpi.elevenlabs.enable = true;
              # Voice pipeline disabled — too heavy for Pi 4B
              services.clawpi.allowedModels = [
                # Anthropic
                {
                  id = "anthropic/claude-sonnet-4-5";
                  name = "Sonnet 4.5";
                }
                {
                  id = "anthropic/claude-haiku-4-5";
                  name = "Haiku 4.5";
                }
                # OpenRouter
                {
                  id = "openrouter/moonshotai/kimi-k2.5";
                  name = "Kimi K2.5";
                }
                {
                  id = "openrouter/minimax/minimax-m2.5";
                  name = "MiniMax M2.5";
                }
                {
                  id = "openrouter/google/gemini-2.5-flash-lite";
                  name = "Gemini 2.5 Flash Lite";
                }
              ];
              services.clawpi.matrix = {
                enable = true;
                homeserver = "https://matrix.glinq.org";
                encryption = true;
                dm.policy = "pairing";
                requireMention = true;
                groupPolicy = "open";
                replyToMode = "all";
                actions = {
                  reactions = true;
                  sendMessage = true;
                };
              };
              services.clawpi.telegram = {
                enable = true;
                streaming = "block";
                blockStreaming = true;
                groupPolicy = "open";
                requireMentionInGroups = true;
                replyToMode = "all";
                ackReaction = "👀";
                reactionLevel = "extensive";
                reactionNotifications = "all";
                actions = {
                  reactions = true;
                  sendMessage = true;
                  sticker = true;
                };
              };
            }
          ];
      };

      # For building flashable SD images (./build.sh)
      nixosConfigurations.rpi5-installer = nixos-raspberrypi.lib.nixosSystem {
        inherit specialArgs;
        modules = pi5Modules ++ commonModules ++ installerModules;
      };

      # Raspberry Pi 4B installer image
      nixosConfigurations.rpi4-installer = nixos-raspberrypi.lib.nixosSystem {
        inherit specialArgs;
        modules = pi4Modules ++ commonModules ++ installerModules;
      };

      installerImages.rpi5 = self.nixosConfigurations.rpi5-installer.config.system.build.sdImage;

      installerImages.rpi4 = self.nixosConfigurations.rpi4-installer.config.system.build.sdImage;

      devShells.x86_64-linux.default =
        let
          pkgs = import nixos-raspberrypi.inputs.nixpkgs { system = "x86_64-linux"; };
          python = pkgs.python3.withPackages (p: [ p.websockets ]);
          screenshot = pkgs.writeShellScriptBin "clawpi-screenshot" ''
            ${python}/bin/python3 ${./scripts/screenshot.py} "$@"
          '';
        in
        pkgs.mkShell {
          packages = [
            python
            screenshot
          ];
        };

      # Wake word model training (GPU-accelerated via ROCm)
      # Usage: nix develop .#training
      devShells.x86_64-linux.training =
        let
          pkgs = import nixos-raspberrypi.inputs.nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
            config.rocmSupport = true;
          };
          python = pkgs.python3.withPackages (ps: [
            # PyTorch with ROCm for GPU-accelerated training
            ps.torchWithRocm
            ps.torchaudio
            ps.torch-audiomentations
            ps.torchinfo
            ps.torchmetrics

            # openWakeWord dependencies
            ps.onnxruntime
            ps.onnx
            ps.numpy
            ps.scipy
            ps.scikit-learn
            ps.tqdm
            ps.requests

            # TTS and audio processing
            ps.piper-phonemize
            ps.espeak-phonemizer
            ps.torchaudio
            ps.webrtcvad

            # Training data (soundfile for audio decoding)
            ps.soundfile
            ps.speechbrain
            ps.mutagen

            # General
            ps.pyyaml
            ps.pip
            ps.setuptools
          ]);
        in
        pkgs.mkShell {
          packages = [
            python
            pkgs.git
            pkgs.wget
            pkgs.ffmpeg-headless
          ];
          shellHook = ''
            echo "openWakeWord training shell (ROCm GPU enabled)"
            echo ""
            echo "First time setup:"
            echo "  cd training && bash setup.sh"
            echo ""
            echo "Train 'hey claw' model:"
            echo "  cd training && bash train.sh"
            echo ""
            export PIP_PREFIX="$PWD/training/.pip"
            export PYTHONPATH="$PIP_PREFIX/lib/python${pkgs.python3.pythonVersion}/site-packages:$PYTHONPATH"
            export PATH="$PIP_PREFIX/bin:$PATH"
            mkdir -p "$PIP_PREFIX"
          '';
        };
    };
}
