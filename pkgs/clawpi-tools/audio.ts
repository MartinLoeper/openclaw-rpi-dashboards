import { Type } from "@sinclair/typebox";
import { readFile, writeFile, unlink, mkdir } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { homedir } from "node:os";
import { join } from "node:path";
import { run, text, SYSTEM_PATH } from "./helpers";
import { execFile } from "node:child_process";

const DEBUG = process.env.OPENCLAW_LOG_LEVEL === "debug" || process.env.CLAWPI_DEBUG === "1";

// Read whisper/transcription config from the gateway's openclaw.json at import time.
// Returns the wrapper command path, or null if audio transcription is not configured.
// The wrapper handles Groq-first-with-local-fallback and format conversion internally.
function getTranscribeCommand(): string | null {
  try {
    const configPath = join(homedir(), ".openclaw", "openclaw.json");
    const fs = require("node:fs");
    const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
    const media = config?.tools?.media?.audio;
    if (!media?.enabled || !media?.models?.[0]) return null;
    return media.models[0].command;
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
      "Record audio from the microphone and transcribe it using the configured " +
      "transcription backend (Groq cloud with local whisper.cpp fallback). " +
      "Returns the transcription text. Useful for listening to what the user says, " +
      "capturing ambient speech, or taking voice notes. " +
      "Before recording, ask the user how many seconds to record " +
      "unless they already specified a duration. Defaults to 5 seconds. " +
      "Requires services.clawpi.audio.enable = true.",
    parameters: Type.Object({
      seconds: Type.Optional(
        Type.Number({
          description: "Recording duration in seconds (default: 5)",
          minimum: 1,
          maximum: 60,
        }),
      ),
    }),
    async execute(
      _id: string,
      params: { seconds?: number },
    ) {
      const transcribeCmd = getTranscribeCommand();
      if (!transcribeCmd) {
        return text(
          "Error: audio transcription is not configured. Enable it with services.clawpi.audio.enable = true.",
        );
      }

      const duration = params.seconds ?? 5;
      const tmpFile = `/tmp/clawpi-transcribe-${randomBytes(4).toString("hex")}.wav`;

      try {
        // Show recording indicator
        await fetch("http://localhost:3100/api/recording/start", { method: "POST" }).catch(() => {});

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

        // Hide recording indicator before transcription
        await fetch("http://localhost:3100/api/recording/stop", { method: "POST" }).catch(() => {});

        // Step 2: Transcribe using the wrapper (handles Groq → local fallback + format conversion)
        const { stdout } = await run(transcribeCmd, [tmpFile]);
        const transcript = stdout.trim();

        return text(
          transcript
            ? `Transcription (${duration}s):\n\n${transcript}`
            : `No speech detected in ${duration}s recording.`,
        );
      } finally {
        await fetch("http://localhost:3100/api/recording/stop", { method: "POST" }).catch(() => {});
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

      // Notify daemon to show stop button
      await fetch("http://localhost:3100/api/tts/playing", { method: "POST" }).catch(() => {});

      const isWav = filePath.endsWith(".wav");

      try {
        if (isWav) {
          await run("pw-play", [filePath]);
        } else {
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
          } finally {
            await unlink(tmpWav).catch(() => {});
          }
        }
        return text(`Played: ${filePath}`);
      } finally {
        // Hide stop button when playback ends (naturally or via error)
        await fetch("http://localhost:3100/api/tts/stopped", { method: "POST" }).catch(() => {});
      }
    },
  });

  // ── Audio: stop playback ──────────────────────────────────────────
  api.registerTool({
    name: "tts_stop",
    description:
      "Stop any currently playing audio (kills pw-play). " +
      "Use this when the user asks to stop speaking, be quiet, or shut up.",
    parameters: Type.Object({}),
    async execute() {
      const resp = await fetch("http://localhost:3100/api/tts/stop", { method: "POST" });
      if (!resp.ok) {
        return text(`Error: stop endpoint returned ${resp.status}`);
      }
      return text("Playback stopped.");
    },
  });

  // ── TTS: Cartesia ──────────────────────────────────────────────
  const CARTESIA_KEY_FILE = process.env.CLAWPI_CARTESIA_API_KEY_FILE;
  const CARTESIA_DEFAULT_VOICE = process.env.CLAWPI_CARTESIA_VOICE ?? "a0e99841-438c-4a64-b679-ae501e7d6091";
  const CARTESIA_DEFAULT_MODEL = process.env.CLAWPI_CARTESIA_MODEL ?? "sonic-2";
  const CARTESIA_API_VERSION = "2025-04-16";

  api.registerTool({
    name: "tts_cartesia",
    description:
      "Generate speech from text using Cartesia's Sonic TTS API. " +
      "Returns the path to the generated WAV file. " +
      "Cartesia offers ultra-low-latency, natural-sounding speech with emotion control. " +
      "After generating, call audio_play with the returned path to play it.\n\n" +
      "Requires services.clawpi.cartesia.enable = true in the NixOS config " +
      "and an API key provisioned via ./scripts/provision-cartesia.sh.",
    parameters: Type.Object({
      text: Type.String({
        description: "The text to convert to speech",
      }),
      voice: Type.Optional(
        Type.String({
          description: "Cartesia voice ID (uses NixOS default if omitted)",
        }),
      ),
      model: Type.Optional(
        Type.String({
          description: 'Cartesia model ID, e.g. "sonic-2", "sonic-turbo" (uses NixOS default if omitted)',
        }),
      ),
      language: Type.Optional(
        Type.String({
          description: 'Language code, e.g. "en", "de", "fr" (auto-detected if omitted)',
        }),
      ),
      speed: Type.Optional(
        Type.Number({
          description: "Speech speed from 0.6 to 1.5 (default: normal)",
          minimum: 0.6,
          maximum: 1.5,
        }),
      ),
    }),
    async execute(
      _id: string,
      params: { text: string; voice?: string; model?: string; language?: string; speed?: number },
    ) {
      if (!CARTESIA_KEY_FILE) {
        return text(
          "Error: Cartesia is not enabled. " +
          "Set services.clawpi.cartesia.enable = true in the NixOS config and redeploy.",
        );
      }

      let apiKey: string | null = null;
      try {
        apiKey = (await readFile(CARTESIA_KEY_FILE, "utf-8")).trim() || null;
      } catch {
        // file missing or unreadable
      }
      if (!apiKey) {
        return text(
          "Error: Cartesia API key not found at " + CARTESIA_KEY_FILE + ". " +
          "Provision it with: ./scripts/provision-cartesia.sh",
        );
      }

      const voiceId = params.voice ?? CARTESIA_DEFAULT_VOICE;
      const modelId = params.model ?? CARTESIA_DEFAULT_MODEL;
      const outDir = "/tmp/clawpi-tts-cartesia";
      const outFile = join(outDir, `voice-${randomBytes(4).toString("hex")}.wav`);

      await mkdir(outDir, { recursive: true });

      const apiUrl = "https://api.cartesia.ai/tts/bytes";
      const body: Record<string, unknown> = {
        model_id: modelId,
        transcript: params.text,
        voice: { mode: "id", id: voiceId },
        output_format: { container: "wav", encoding: "pcm_s16le", sample_rate: 44100 },
      };
      if (params.language) body.language = params.language;
      if (params.speed) {
        body.generation_config = { speed: params.speed === 1.0 ? "normal" : String(params.speed) };
      }

      if (DEBUG) {
        console.error(`[tts_cartesia] POST ${apiUrl} model=${modelId} voice=${voiceId} text=${params.text.length} chars`);
      }

      const resp = await fetch(apiUrl, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Cartesia-Version": CARTESIA_API_VERSION,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });

      if (DEBUG) {
        const hdrs: Record<string, string> = {};
        resp.headers.forEach((v, k) => { hdrs[k] = v; });
        console.error(`[tts_cartesia] response status=${resp.status} headers=${JSON.stringify(hdrs)}`);
      }

      if (!resp.ok) {
        const errBody = await resp.text().catch(() => "");
        if (DEBUG) {
          console.error(`[tts_cartesia] error body: ${errBody}`);
        }
        return text(`Error: Cartesia API returned ${resp.status}: ${errBody}`);
      }

      const buffer = Buffer.from(await resp.arrayBuffer());
      await writeFile(outFile, buffer);

      if (DEBUG) {
        console.error(`[tts_cartesia] wrote ${buffer.length} bytes to ${outFile}`);
      }

      return text(
        `Generated speech (${buffer.length} bytes, voice=${voiceId}, model=${modelId}).\n` +
        `File: ${outFile}\n\n` +
        `Play it with audio_play.`,
      );
    },
  });

  // ── Cartesia: list/search voices ──────────────────────────────
  api.registerTool({
    name: "tts_cartesia_voices",
    description:
      "Search and list available Cartesia voices. " +
      "Returns voice IDs, names, descriptions, and languages. Use this to find the right " +
      "voice ID for the tts_cartesia tool.",
    parameters: Type.Object({
      search: Type.Optional(
        Type.String({
          description: "Search term to filter by name, description, or voice ID",
        }),
      ),
      gender: Type.Optional(
        Type.String({
          description: 'Filter by gender: "masculine", "feminine", "gender_neutral"',
        }),
      ),
      limit: Type.Optional(
        Type.Number({
          description: "Max results to return (1–100, default 20)",
          minimum: 1,
          maximum: 100,
        }),
      ),
    }),
    async execute(
      _id: string,
      params: { search?: string; gender?: string; limit?: number },
    ) {
      if (!CARTESIA_KEY_FILE) {
        return text(
          "Error: Cartesia is not enabled. " +
          "Set services.clawpi.cartesia.enable = true in the NixOS config and redeploy.",
        );
      }

      let apiKey: string | null = null;
      try {
        apiKey = (await readFile(CARTESIA_KEY_FILE, "utf-8")).trim() || null;
      } catch {
        // file missing or unreadable
      }
      if (!apiKey) {
        return text(
          "Error: Cartesia API key not found at " + CARTESIA_KEY_FILE + ". " +
          "Provision it with: ./scripts/provision-cartesia.sh",
        );
      }

      const queryParams = new URLSearchParams();
      if (params.search) queryParams.set("q", params.search);
      if (params.gender) queryParams.set("gender", params.gender);
      queryParams.set("limit", String(params.limit ?? 20));

      const url = `https://api.cartesia.ai/voices?${queryParams}`;
      if (DEBUG) {
        console.error(`[tts_cartesia_voices] GET ${url}`);
      }

      const resp = await fetch(url, {
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Cartesia-Version": CARTESIA_API_VERSION,
        },
      });

      if (!resp.ok) {
        const errBody = await resp.text().catch(() => "");
        return text(`Error: Cartesia API returned ${resp.status}: ${errBody}`);
      }

      const data = await resp.json() as {
        data?: Array<{
          id: string;
          name: string;
          description?: string;
          language?: string;
          gender?: string;
        }>;
        has_more?: boolean;
      };

      const voices = data.data ?? [];
      if (voices.length === 0) {
        return text("No voices found matching the query.");
      }

      const lines = voices.map((v) => {
        const meta = [v.language, v.gender].filter(Boolean).join(", ");
        return `- **${v.name}** (${v.id})${meta ? ` [${meta}]` : ""}${v.description ? ` — ${v.description}` : ""}`;
      });

      const header = data.has_more
        ? `Showing ${voices.length} voices (more available):\n\n`
        : "";

      return text(header + lines.join("\n"));
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
      `Voice note: The default voice (${ELEVENLABS_DEFAULT_VOICE}) speaks Schwäbisch ` +
      "(Swabian German dialect). When using this voice or omitting the voice parameter, " +
      "write the text in Schwäbisch for the most natural result. " +
      "Use tts_hq_voices to find a different voice if standard German or another language is needed.\n\n" +
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

  // ── ElevenLabs: list/search voices ──────────────────────────────
  api.registerTool({
    name: "tts_hq_voices",
    description:
      "Search and list available ElevenLabs voices. " +
      "Returns voice IDs, names, and labels. Use this to find the right " +
      "voice ID for the tts_hq tool.",
    parameters: Type.Object({
      search: Type.Optional(
        Type.String({
          description: "Search term to filter by name, description, or labels",
        }),
      ),
      voice_type: Type.Optional(
        Type.String({
          description:
            'Filter by type: "personal", "community", "default", "workspace", "saved"',
        }),
      ),
      page_size: Type.Optional(
        Type.Number({
          description: "Max results to return (1–100, default 20)",
          minimum: 1,
          maximum: 100,
        }),
      ),
    }),
    async execute(
      _id: string,
      params: { search?: string; voice_type?: string; page_size?: number },
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

      const queryParams = new URLSearchParams();
      if (params.search) queryParams.set("search", params.search);
      if (params.voice_type) queryParams.set("voice_type", params.voice_type);
      queryParams.set("page_size", String(params.page_size ?? 20));

      const url = `https://api.elevenlabs.io/v1/voices?${queryParams}`;
      if (DEBUG) {
        console.error(`[tts_hq_voices] GET ${url}`);
      }

      const resp = await fetch(url, {
        headers: { "xi-api-key": apiKey },
      });

      if (!resp.ok) {
        const errBody = await resp.text().catch(() => "");
        return text(`Error: ElevenLabs API returned ${resp.status}: ${errBody}`);
      }

      const data = await resp.json() as {
        voices?: Array<{
          voice_id: string;
          name: string;
          category?: string;
          labels?: Record<string, string>;
          description?: string;
        }>;
        total_count?: number;
      };

      const voices = data.voices ?? [];
      if (voices.length === 0) {
        return text("No voices found matching the query.");
      }

      const lines = voices.map((v) => {
        const labels = v.labels ? Object.values(v.labels).join(", ") : "";
        return `- **${v.name}** (${v.voice_id}) [${v.category ?? "unknown"}]${labels ? ` — ${labels}` : ""}`;
      });

      const header = data.total_count != null
        ? `Found ${data.total_count} voices (showing ${voices.length}):\n\n`
        : "";

      return text(header + lines.join("\n"));
    },
  });
}
