import { Type } from "@sinclair/typebox";
import { readFile, unlink } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { homedir } from "node:os";
import { join } from "node:path";
import { run, text, SYSTEM_PATH } from "./helpers";
import { execFile } from "node:child_process";

// Read whisper config from the gateway's openclaw.json at import time.
// Returns { command, model, language } or null if whisper is not configured.
function getWhisperConfig(): { command: string; model: string; language: string } | null {
  try {
    const configPath = join(homedir(), ".openclaw", "openclaw.json");
    // Use require for sync read (jiti supports it)
    const fs = require("node:fs");
    const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
    const media = config?.tools?.media?.audio;
    if (!media?.enabled || !media?.models?.[0]) return null;
    const m = media.models[0];
    const modelArg = m.args?.[m.args.indexOf("-m") + 1];
    const langArg = m.args?.[m.args.indexOf("-l") + 1] ?? "auto";
    return { command: m.command, model: modelArg, language: langArg };
  } catch {
    return null;
  }
}

export default function (api: any) {
  api.registerTool({
    name: "audio_status",
    description:
      "List all PipeWire/WirePlumber audio devices, sinks, and sources. " +
      "Shows sink IDs needed for audio_set_default_sink.",
    parameters: Type.Object({}),
    async execute() {
      const { stdout } = await run("wpctl", ["status"]);
      return text(stdout);
    },
  });

  api.registerTool({
    name: "audio_get_volume",
    description:
      "Get the current volume level of the default audio sink. " +
      "Returns a value between 0.0 and 1.0 (plus mute status).",
    parameters: Type.Object({}),
    async execute() {
      const { stdout } = await run("wpctl", [
        "get-volume",
        "@DEFAULT_AUDIO_SINK@",
      ]);
      return text(stdout.trim());
    },
  });

  api.registerTool({
    name: "audio_set_volume",
    description:
      "Set the volume of the default audio sink. " +
      "Accepts a value between 0.0 (mute) and 1.0 (maximum).",
    parameters: Type.Object({
      level: Type.Number({
        description: "Volume level from 0.0 to 1.0",
        minimum: 0,
        maximum: 1,
      }),
    }),
    async execute(_id: string, params: { level: number }) {
      await run("wpctl", [
        "set-volume",
        "@DEFAULT_AUDIO_SINK@",
        String(params.level),
      ]);
      const { stdout } = await run("wpctl", [
        "get-volume",
        "@DEFAULT_AUDIO_SINK@",
      ]);
      return text(`Volume set. ${stdout.trim()}`);
    },
  });

  api.registerTool({
    name: "audio_test_tone",
    description:
      "Play a short test tone through the default audio sink to verify " +
      "audio output is working. Plays a 440 Hz sine wave for ~3 seconds.",
    parameters: Type.Object({
      frequency: Type.Optional(
        Type.Number({
          description: "Tone frequency in Hz (default: 440)",
          minimum: 20,
          maximum: 20000,
        }),
      ),
      duration: Type.Optional(
        Type.Number({
          description: "Duration in seconds (default: 3)",
          minimum: 1,
          maximum: 30,
        }),
      ),
    }),
    async execute(
      _id: string,
      params: { frequency?: number; duration?: number },
    ) {
      const freq = String(params.frequency ?? 440);
      const dur = String(params.duration ?? 3);
      await run("speaker-test", [
        "-D", "pipewire",
        "-t", "sine",
        "-f", freq,
        "-c", "2",
        "-l", "1",
        "-p", dur,
      ]);
      return text(`Test tone played (${freq} Hz, ${dur}s).`);
    },
  });

  api.registerTool({
    name: "audio_set_default_sink",
    description:
      "Set the default audio output sink by its WirePlumber sink ID. " +
      "Use audio_status first to find available sink IDs.",
    parameters: Type.Object({
      sink_id: Type.Number({
        description:
          "WirePlumber sink ID (from audio_status output, e.g. 54 for USB speaker, 73 for HDMI)",
      }),
    }),
    async execute(_id: string, params: { sink_id: number }) {
      await run("wpctl", ["set-default", String(params.sink_id)]);
      return text(`Default sink set to ${params.sink_id}.`);
    },
  });

  // ── Audio: get input volume ──────────────────────────────────────
  api.registerTool({
    name: "audio_get_input_volume",
    description:
      "Get the current volume level of the default audio source (microphone). " +
      "Returns a value between 0.0 and 1.0 (plus mute status).",
    parameters: Type.Object({}),
    async execute() {
      const { stdout } = await run("wpctl", [
        "get-volume",
        "@DEFAULT_AUDIO_SOURCE@",
      ]);
      return text(stdout.trim());
    },
  });

  // ── Audio: set input volume ──────────────────────────────────────
  api.registerTool({
    name: "audio_set_input_volume",
    description:
      "Set the volume of the default audio source (microphone). " +
      "Accepts a value between 0.0 (mute) and 1.0 (maximum).",
    parameters: Type.Object({
      level: Type.Number({
        description: "Input volume level from 0.0 to 1.0",
        minimum: 0,
        maximum: 1,
      }),
    }),
    async execute(_id: string, params: { level: number }) {
      await run("wpctl", [
        "set-volume",
        "@DEFAULT_AUDIO_SOURCE@",
        String(params.level),
      ]);
      const { stdout } = await run("wpctl", [
        "get-volume",
        "@DEFAULT_AUDIO_SOURCE@",
      ]);
      return text(`Input volume set. ${stdout.trim()}`);
    },
  });

  // ── Audio: set default source ────────────────────────────────────
  api.registerTool({
    name: "audio_set_default_source",
    description:
      "Set the default audio input source (microphone) by its WirePlumber source ID. " +
      "Use audio_status first to find available source IDs.",
    parameters: Type.Object({
      source_id: Type.Number({
        description:
          "WirePlumber source ID (from audio_status output, e.g. 46 for USB mic)",
      }),
    }),
    async execute(_id: string, params: { source_id: number }) {
      await run("wpctl", ["set-default", String(params.source_id)]);
      return text(`Default source set to ${params.source_id}.`);
    },
  });

  // ── Audio: record ────────────────────────────────────────────────
  api.registerTool({
    name: "audio_record",
    description:
      "Record audio from the default input source (microphone). " +
      "Returns the recording as a WAV file. " +
      "Before recording, ask the user how many seconds to record " +
      "unless they already specified a duration. Defaults to 5 seconds.",
    parameters: Type.Object({
      seconds: Type.Optional(
        Type.Number({
          description: "Recording duration in seconds (default: 5)",
          minimum: 1,
          maximum: 30,
        }),
      ),
    }),
    async execute(_id: string, params: { seconds?: number }) {
      const duration = params.seconds ?? 5;
      const tmpFile = `/tmp/clawpi-record-${randomBytes(4).toString("hex")}.wav`;
      try {
        // pw-record doesn't have a duration flag — we spawn it and kill after timeout.
        // When killed, execFile reports an error with killed=true or signal=SIGTERM.
        await new Promise<void>((resolve, reject) => {
          let killed = false;
          const child = execFile(
            "pw-record",
            ["--format", "s16", "--rate", "16000", "--channels", "1", tmpFile],
            {
              env: {
                ...process.env,
                PATH: SYSTEM_PATH,
                XDG_RUNTIME_DIR: `/run/user/${process.getuid?.() ?? 1000}`,
              },
            },
            (err) => {
              if (err && !killed) reject(err);
              else resolve();
            },
          );
          setTimeout(() => {
            killed = true;
            child.kill("SIGTERM");
          }, duration * 1000);
        });
        const data = await readFile(tmpFile);
        return {
          content: [
            { type: "text" as const, text: `Recorded ${duration}s of audio (WAV, 16kHz mono, ${data.length} bytes).` },
          ],
        };
      } finally {
        await unlink(tmpFile).catch(() => {});
      }
    },
  });

  // ── Audio: transcribe ──────────────────────────────────────────────
  api.registerTool({
    name: "audio_transcribe",
    description:
      "Record audio from the microphone and transcribe it locally using whisper.cpp. " +
      "Returns the transcription text. Useful for listening to what the user says, " +
      "capturing ambient speech, or taking voice notes. " +
      "Before recording, ask the user how many seconds to record " +
      "unless they already specified a duration. Defaults to 5 seconds. " +
      "Use auto language detection by default — only set a specific language " +
      "if the user explicitly asks to record in a particular language. " +
      "Requires services.clawpi.audio.enable = true.",
    parameters: Type.Object({
      seconds: Type.Optional(
        Type.Number({
          description: "Recording duration in seconds (default: 5)",
          minimum: 1,
          maximum: 60,
        }),
      ),
      language: Type.Optional(
        Type.String({
          description:
            'Language code for transcription (e.g. "en", "de"). ' +
            "Defaults to the configured language (usually auto-detect).",
        }),
      ),
    }),
    async execute(
      _id: string,
      params: { seconds?: number; language?: string },
    ) {
      const whisper = getWhisperConfig();
      if (!whisper) {
        return text(
          "Error: whisper.cpp is not configured. Enable it with services.clawpi.audio.enable = true.",
        );
      }

      const duration = params.seconds ?? 5;
      const lang = params.language ?? whisper.language;
      const tmpFile = `/tmp/clawpi-transcribe-${randomBytes(4).toString("hex")}.wav`;

      try {
        // Step 1: Record audio
        await new Promise<void>((resolve, reject) => {
          let killed = false;
          const child = execFile(
            "pw-record",
            ["--format", "s16", "--rate", "16000", "--channels", "1", tmpFile],
            {
              env: {
                ...process.env,
                PATH: SYSTEM_PATH,
                XDG_RUNTIME_DIR: `/run/user/${process.getuid?.() ?? 1000}`,
              },
            },
            (err) => {
              if (err && !killed) reject(err);
              else resolve();
            },
          );
          setTimeout(() => {
            killed = true;
            child.kill("SIGTERM");
          }, duration * 1000);
        });

        // Step 2: Transcribe with whisper-cli
        const { stdout } = await run(whisper.command, [
          "-m", whisper.model,
          "-l", lang,
          "-np",
          "--no-gpu",
          "-f", tmpFile,
        ]);

        // whisper-cli outputs timestamps + text, extract just the text
        const lines = stdout.trim().split("\n");
        const transcript = lines
          .map((line: string) => line.replace(/^\[.*?\]\s*/, "").trim())
          .filter(Boolean)
          .join(" ");

        return text(
          transcript
            ? `Transcription (${duration}s, lang=${lang}):\n\n${transcript}`
            : `No speech detected in ${duration}s recording.`,
        );
      } finally {
        await unlink(tmpFile).catch(() => {});
      }
    },
  });
}
