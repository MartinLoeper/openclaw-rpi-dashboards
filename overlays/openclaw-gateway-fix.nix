final: prev:
let
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
