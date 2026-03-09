import { Type } from "@sinclair/typebox";
import { readFile, writeFile, unlink, mkdir } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { homedir } from "node:os";
import { join } from "node:path";
import { run, text, SYSTEM_PATH } from "./helpers";
import { execFile } from "node:child_process";

const DEBUG = process.env.OPENCLAW_LOG_LEVEL === "debug" || process.env.CLAWPI_DEBUG === "1";

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

  // ── Audio: play ────────────────────────────────────────────────────
  api.registerTool({
    name: "audio_play",
    description:
      "Play an audio file through the Pi's speakers. " +
      "Supports WAV, MP3, OGG, FLAC, and other common formats. " +
      "Non-WAV formats are automatically converted via ffmpeg before playback.\n\n" +
      "IMPORTANT — Speaking to the user:\n" +
      "When the user asks you to speak, talk, say something aloud, or " +
      "uses phrases like 'tell me...', 'talk to me...', 'say ...' — " +
      "you MUST use the tts tool to generate speech, then immediately call " +
      "audio_play with the resulting MP3 path to play it through the speakers.\n" +
      "If the user asks you to 'always speak your responses' or 'use voice for all replies', " +
      "then for EVERY response (including replies via Telegram or other channels) " +
      "also generate speech with tts and play it via audio_play on the display speakers. " +
      "Continue doing this until the user tells you to stop.\n\n" +
      "The tts tool outputs an MP3 file path (e.g. /tmp/openclaw/tts-.../voice-*.mp3) — " +
      "pass that path to this tool.\n\n" +
      "Volume note: Some USB speakers don't use the full 0.0–1.0 range — " +
      "e.g. the usable range may be 0.8–1.0 with everything below being silent. " +
      "If the user reports no sound, try increasing the volume with audio_set_volume " +
      "before assuming the speaker is broken.",
    parameters: Type.Object({
      path: Type.String({
        description:
          "Absolute path to the audio file to play (e.g. /tmp/openclaw/tts-.../voice-*.mp3)",
      }),
    }),
    async execute(_id: string, params: { path: string }) {
      const filePath = params.path;

      // Check if file exists
      try {
        await readFile(filePath, { flag: "r" }).then(() => {});
        // Just check access, don't read the whole file
      } catch {
        return text(`Error: file not found: ${filePath}`);
      }

      const isWav = filePath.endsWith(".wav");

      if (isWav) {
        // Play WAV directly
        await run("pw-play", [filePath]);
        return text(`Played: ${filePath}`);
      }

      // Convert to WAV via ffmpeg, then play
      const tmpWav = `/tmp/clawpi-play-${randomBytes(4).toString("hex")}.wav`;
      try {
        await run("ffmpeg", [
          "-i", filePath,
          "-ar", "44100",
          "-ac", "2",
          "-f", "wav",
          "-y",
          tmpWav,
        ]);
        await run("pw-play", [tmpWav]);
        return text(`Played: ${filePath}`);
      } finally {
        await unlink(tmpWav).catch(() => {});
      }
    },
  });

  // ── TTS: high-quality via ElevenLabs ─────────────────────────────
  const ELEVENLABS_KEY_FILE = process.env.CLAWPI_ELEVENLABS_API_KEY_FILE;
  const ELEVENLABS_DEFAULT_VOICE = process.env.CLAWPI_ELEVENLABS_VOICE ?? "eokb0hhuVX3JuAiUKucB";
  const ELEVENLABS_DEFAULT_MODEL = process.env.CLAWPI_ELEVENLABS_MODEL ?? "eleven_v3";

  api.registerTool({
    name: "tts_hq",
    description:
      "Generate high-quality speech from text using ElevenLabs cloud TTS. " +
      "Returns the path to the generated MP3 file. " +
      "Use this instead of the built-in tts tool when the user asks for " +
      "higher quality, more natural, or more expressive speech. " +
      "After generating, call audio_play with the returned path to play it.\n\n" +
      "Requires services.clawpi.elevenlabs.enable = true in the NixOS config " +
      "and an API key provisioned via ./scripts/provision-elevenlabs.sh.",
    parameters: Type.Object({
      text: Type.String({
        description: "The text to convert to speech",
      }),
      voice: Type.Optional(
        Type.String({
          description: "ElevenLabs voice ID (uses NixOS default if omitted)",
        }),
      ),
      model: Type.Optional(
        Type.String({
          description: "ElevenLabs model ID (uses NixOS default if omitted)",
        }),
      ),
    }),
    async execute(
      _id: string,
      params: { text: string; voice?: string; model?: string },
    ) {
      if (!ELEVENLABS_KEY_FILE) {
        return text(
          "Error: ElevenLabs is not enabled. " +
          "Set services.clawpi.elevenlabs.enable = true in the NixOS config and redeploy.",
        );
      }

      let apiKey: string | null = null;
      try {
        apiKey = (await readFile(ELEVENLABS_KEY_FILE, "utf-8")).trim() || null;
      } catch {
        // file missing or unreadable
      }
      if (!apiKey) {
        return text(
          "Error: ElevenLabs API key not found at " + ELEVENLABS_KEY_FILE + ". " +
          "Provision it with: ./scripts/provision-elevenlabs.sh",
        );
      }

      const voiceId = params.voice ?? ELEVENLABS_DEFAULT_VOICE;
      const modelId = params.model ?? ELEVENLABS_DEFAULT_MODEL;
      const outDir = "/tmp/clawpi-tts-hq";
      const outFile = join(outDir, `voice-${randomBytes(4).toString("hex")}.mp3`);

      await mkdir(outDir, { recursive: true });

      const apiUrl = `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`;
      if (DEBUG) {
        console.error(`[tts_hq] POST ${apiUrl} model=${modelId} text=${params.text.length} chars`);
      }

      const resp = await fetch(apiUrl, {
        method: "POST",
        headers: {
          "xi-api-key": apiKey,
          "Content-Type": "application/json",
          Accept: "audio/mpeg",
        },
        body: JSON.stringify({
          text: params.text,
          model_id: modelId,
        }),
      });

      if (DEBUG) {
        const hdrs: Record<string, string> = {};
        resp.headers.forEach((v, k) => { hdrs[k] = v; });
        console.error(`[tts_hq] response status=${resp.status} headers=${JSON.stringify(hdrs)}`);
      }

      if (!resp.ok) {
        const errBody = await resp.text().catch(() => "");
        if (DEBUG) {
          console.error(`[tts_hq] error body: ${errBody}`);
        }
        return text(`Error: ElevenLabs API returned ${resp.status}: ${errBody}`);
      }

      const buffer = Buffer.from(await resp.arrayBuffer());
      await writeFile(outFile, buffer);

      if (DEBUG) {
        console.error(`[tts_hq] wrote ${buffer.length} bytes to ${outFile}`);
      }

      return text(
        `Generated speech (${buffer.length} bytes, voice=${voiceId}, model=${modelId}).\n` +
        `File: ${outFile}\n\n` +
        `Play it with audio_play.`,
      );
    },
  });
}
