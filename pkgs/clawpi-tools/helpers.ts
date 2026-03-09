import { execFile } from "node:child_process";
import { promisify } from "node:util";

const exec = promisify(execFile);

// NixOS system PATH — the gateway process may not inherit the full system path,
// so we ensure common NixOS bin dirs are included.
// Build a PATH that includes NixOS system bins AND the kiosk user's Home Manager
// profile (where packages like grim are installed via home.packages).
export const SYSTEM_PATH = [
  process.env.PATH,
  "/run/current-system/sw/bin",
  "/run/wrappers/bin",
  `/etc/profiles/per-user/kiosk/bin`,
].filter(Boolean).join(":");

// Run a command with the correct runtime dir and PATH.
export async function run(
  cmd: string,
  args: string[],
): Promise<{ stdout: string; stderr: string }> {
  return exec(cmd, args, {
    env: {
      ...process.env,
      PATH: SYSTEM_PATH,
      XDG_RUNTIME_DIR: `/run/user/${process.getuid?.() ?? 1000}`,
    },
  });
}

// Run a command with Wayland display access (for grim, wlr-randr, etc.)
export async function runWayland(
  cmd: string,
  args: string[],
): Promise<{ stdout: string; stderr: string }> {
  return exec(cmd, args, {
    env: {
      ...process.env,
      PATH: SYSTEM_PATH,
      XDG_RUNTIME_DIR: `/run/user/${process.getuid?.() ?? 1000}`,
      WAYLAND_DISPLAY: "wayland-0",
    },
  });
}

export function text(t: string) {
  return { content: [{ type: "text" as const, text: t }] };
}

export function image(base64Data: string, mimeType: string = "image/png") {
  return {
    content: [
      {
        type: "image" as const,
        data: base64Data,
        mimeType,
      },
    ],
  };
}
