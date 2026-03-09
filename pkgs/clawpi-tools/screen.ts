import { Type } from "@sinclair/typebox";
import { stat } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { execFile } from "node:child_process";
import { text, SYSTEM_PATH } from "./helpers";
import type { ChildProcess } from "node:child_process";

const DEBUG = process.env.OPENCLAW_LOG_LEVEL === "debug" || process.env.CLAWPI_DEBUG === "1";

// Module-level state for the active recording
let activeRecording: {
  process: ChildProcess;
  file: string;
  startedAt: number;
} | null = null;

export default function (api: any) {
  // ── Screen recording: start ─────────────────────────────────────
  api.registerTool({
    name: "screen_record_start",
    description:
      "Start recording the Wayland display to a video file using wf-recorder. " +
      "Only one recording can be active at a time — calling this while a " +
      "recording is already in progress will return an error. " +
      "Use screen_record_stop to stop the recording and get the output file path.",
    parameters: Type.Object({
      filename: Type.Optional(
        Type.String({
          description:
            "Output filename (default: auto-generated). " +
            "Use .mp4, .mkv, or .webm extension to select container format.",
        }),
      ),
      audio: Type.Optional(
        Type.Boolean({
          description: "Also record audio from the default PipeWire source (default: false)",
        }),
      ),
    }),
    async execute(
      _id: string,
      params: { filename?: string; audio?: boolean },
    ) {
      if (activeRecording) {
        const elapsed = Math.round((Date.now() - activeRecording.startedAt) / 1000);
        return text(
          `Error: A recording is already in progress (${elapsed}s, file: ${activeRecording.file}). ` +
          `Stop it first with screen_record_stop.`,
        );
      }

      const outFile = params.filename ??
        `/tmp/clawpi-screenrec-${randomBytes(4).toString("hex")}.mp4`;

      const args = ["-f", outFile];
      if (params.audio) {
        args.push("--audio");
      }

      if (DEBUG) {
        console.error(`[screen_record] starting: wf-recorder ${args.join(" ")}`);
      }

      const child = execFile("wf-recorder", args, {
        env: {
          ...process.env,
          PATH: SYSTEM_PATH,
          XDG_RUNTIME_DIR: `/run/user/${process.getuid?.() ?? 1000}`,
          WAYLAND_DISPLAY: "wayland-0",
        },
      });

      // Give wf-recorder a moment to start and check for immediate failure
      const earlyError = await new Promise<string | null>((resolve) => {
        let errOutput = "";
        child.stderr?.on("data", (chunk: Buffer) => {
          errOutput += chunk.toString();
        });
        child.on("error", (err) => resolve(err.message));
        child.on("exit", (code) => {
          if (code !== null && code !== 0) {
            resolve(errOutput || `wf-recorder exited with code ${code}`);
          }
        });
        setTimeout(() => resolve(null), 500);
      });

      if (earlyError) {
        if (DEBUG) {
          console.error(`[screen_record] failed to start: ${earlyError}`);
        }
        return text(`Error: Failed to start recording: ${earlyError}`);
      }

      activeRecording = {
        process: child,
        file: outFile,
        startedAt: Date.now(),
      };

      // Clean up state if the process exits unexpectedly
      child.on("exit", () => {
        if (activeRecording?.process === child) {
          activeRecording = null;
        }
      });

      return text(
        `Recording started.\n` +
        `File: ${outFile}\n` +
        `Use screen_record_stop to stop and finalize the recording.`,
      );
    },
  });

  // ── Screen recording: stop ──────────────────────────────────────
  api.registerTool({
    name: "screen_record_stop",
    description:
      "Stop the active screen recording started by screen_record_start. " +
      "Returns the path and size of the recorded video file.",
    parameters: Type.Object({}),
    async execute() {
      if (!activeRecording) {
        return text("Error: No recording is currently in progress.");
      }

      const { process: child, file, startedAt } = activeRecording;
      const elapsed = Math.round((Date.now() - startedAt) / 1000);

      if (DEBUG) {
        console.error(`[screen_record] stopping after ${elapsed}s`);
      }

      // Send SIGINT to wf-recorder so it finalizes the file properly
      await new Promise<void>((resolve) => {
        child.on("exit", () => resolve());
        child.kill("SIGINT");
        // Safety timeout in case SIGINT doesn't work
        setTimeout(() => {
          if (activeRecording?.process === child) {
            child.kill("SIGTERM");
          }
          resolve();
        }, 5000);
      });

      activeRecording = null;

      // Check output file
      try {
        const info = await stat(file);
        return text(
          `Recording stopped after ${elapsed}s.\n` +
          `File: ${file} (${(info.size / 1024 / 1024).toFixed(1)} MB)`,
        );
      } catch {
        return text(
          `Recording stopped after ${elapsed}s but output file not found: ${file}`,
        );
      }
    },
  });
}
