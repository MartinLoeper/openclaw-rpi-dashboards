final: prev:
let
  fixLongDep = drv: drv.overrideAttrs (old: {
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
    '';
  });
in {
  openclaw-gateway = fixLongDep prev.openclaw-gateway;
}
