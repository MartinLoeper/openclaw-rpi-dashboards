final: prev:
let
  # Pre-built native crypto library for Matrix E2EE (aarch64-linux, glibc).
  # The npm package tries to download this at runtime, which fails in the Nix store.
  matrixCryptoNative = prev.fetchurl {
    url = "https://github.com/matrix-org/matrix-rust-sdk-crypto-nodejs/releases/download/v0.4.0/matrix-sdk-crypto.linux-arm64-gnu.node";
    hash = "sha256-DcHFgxVYDNDO85wuHsKOHjiFajN28ll9oa4gOI8k0PQ=";
  };

  fixDeps = drv: drv.overrideAttrs (old: {
    postPhases = (old.postPhases or []) ++ [ "fixMissingDeps" ];
    fixMissingDeps = ''
      # Work around missing 'long' dependency for @whiskeysockets/baileys in pnpm layout.
      long_src="$(find "$out/lib/openclaw/node_modules/.pnpm" -path "*/long@5.*/node_modules/long" -print | head -n 1)"
      baileys_pkgs="$(find "$out/lib/openclaw/node_modules/.pnpm" -path "*/@whiskeysockets+baileys*/node_modules/@whiskeysockets/baileys" -print)"
      if [ -n "$long_src" ] && [ -n "$baileys_pkgs" ]; then
        for pkg in $baileys_pkgs; do
          if [ ! -e "$pkg/node_modules/long" ]; then
            mkdir -p "$pkg/node_modules"
            ln -s "$long_src" "$pkg/node_modules/long"
          fi
        done
      fi

      # Install pre-built native crypto library for Matrix.
      # The npm package tries to download it at runtime, which fails in the Nix store.
      crypto_pkg="$(find "$out/lib/openclaw/node_modules/.pnpm" \
        -path "*/@matrix-org+matrix-sdk-crypto-nodejs@*/node_modules/@matrix-org/matrix-sdk-crypto-nodejs" \
        -print | head -n 1)"
      if [ -n "$crypto_pkg" ]; then
        cp "${matrixCryptoNative}" "$crypto_pkg/matrix-sdk-crypto.linux-arm64-gnu.node"
      fi

      # Work around missing dependencies for the Matrix extension.
      # The packages are in the pnpm store but the extension's createRequire() can't resolve them.
      matrix_extension="$out/lib/openclaw/extensions/matrix"
      if [ -d "$matrix_extension" ]; then
        for dep in \
          "@vector-im/matrix-bot-sdk:@vector-im+matrix-bot-sdk" \
          "@matrix-org/matrix-sdk-crypto-nodejs:@matrix-org+matrix-sdk-crypto-nodejs" \
          "markdown-it:markdown-it" \
          "music-metadata:music-metadata" \
          "zod:zod"; do
          pkg_name="''${dep%%:*}"
          pnpm_name="''${dep##*:}"
          scope_dir=""
          if [[ "$pkg_name" == @*/* ]]; then
            scope_dir="$(dirname "$pkg_name")"
          fi
          src="$(find "$out/lib/openclaw/node_modules/.pnpm" \
            -path "*/$pnpm_name@*/node_modules/$pkg_name" \
            -print | head -n 1)"
          if [ -n "$src" ] && [ ! -e "$matrix_extension/node_modules/$pkg_name" ]; then
            if [ -n "$scope_dir" ]; then
              mkdir -p "$matrix_extension/node_modules/$scope_dir"
            else
              mkdir -p "$matrix_extension/node_modules"
            fi
            ln -s "$src" "$matrix_extension/node_modules/$pkg_name"
          fi
        done
      fi
    '';
  });
in {
  openclaw-gateway = fixDeps prev.openclaw-gateway;
}
