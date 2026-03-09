{ lib, stdenvNoCC, openclaw-gateway }:

stdenvNoCC.mkDerivation {
  pname = "clawpi-tools";
  version = "0.2.1";

  src = lib.cleanSource ./.;

  # No build step — jiti loads TypeScript directly at runtime.
  # We just need @sinclair/typebox available from the gateway's node_modules.
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/clawpi-tools
    cp openclaw.plugin.json *.ts $out/lib/clawpi-tools/

    # Symlink the gateway's node_modules so jiti can resolve @sinclair/typebox
    ln -s ${openclaw-gateway}/lib/openclaw/node_modules $out/lib/clawpi-tools/node_modules
    runHook postInstall
  '';

  meta = {
    description = "OpenClaw plugin — hardware control tools for ClawPi (audio, display, overlays)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
