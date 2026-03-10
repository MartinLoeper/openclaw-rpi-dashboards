import { Type } from "@sinclair/typebox";
import { readdir, rename, mkdir, cp } from "node:fs/promises";
import { existsSync, readdirSync } from "node:fs";
import http from "node:http";
import { text } from "./helpers";

const CANVAS_DIR = process.env.CLAWPI_CANVAS_DIR || "/tmp/clawpi-canvas";
const ARCHIVE_DIR =
  process.env.CLAWPI_CANVAS_ARCHIVE_DIR ||
  "/var/lib/kiosk/.openclaw/canvas-archive";

const CDP_URL = "http://127.0.0.1:9222";
const CANVAS_BASE_URL = "http://localhost:3100/canvas/";
const LANDING_URL = "http://localhost:3100";

async function cdpNavigate(url: string): Promise<void> {
  const targets: any[] = await new Promise((resolve, reject) => {
    http
      .get(`${CDP_URL}/json`, (res) => {
        let body = "";
        res.on("data", (chunk: string) => (body += chunk));
        res.on("end", () => {
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            reject(e);
          }
        });
      })
      .on("error", reject);
  });

  const page = targets.find((t: any) => t.type === "page");
  if (!page) {
    throw new Error("No browser page found on CDP port 9222.");
  }

  const WebSocket = (await import("ws")).default;
  const ws = new WebSocket(page.webSocketDebuggerUrl);

  await new Promise<void>((resolve, reject) => {
    ws.on("open", () => {
      ws.send(
        JSON.stringify({
          id: 1,
          method: "Page.navigate",
          params: { url },
        }),
      );
    });
    ws.on("message", (data: any) => {
      const resp = JSON.parse(data.toString());
      if (resp.id === 1) {
        ws.close();
        if (resp.error) {
          reject(new Error(resp.error.message));
        } else {
          resolve();
        }
      }
    });
    ws.on("error", reject);
  });
}

/** Check if a directory has any entries (files or subdirs). */
async function dirHasContent(dir: string): Promise<boolean> {
  if (!existsSync(dir)) return false;
  const entries = await readdir(dir);
  return entries.length > 0;
}

/** Pick a unique archive name, appending -2, -3, … if needed. */
async function uniqueArchiveName(name: string): Promise<string> {
  let candidate = name;
  let suffix = 2;
  while (existsSync(`${ARCHIVE_DIR}/${candidate}`)) {
    candidate = `${name}-${suffix}`;
    suffix++;
  }
  return candidate;
}

/** Move all entries from src into dest (which must exist). */
async function moveAllEntries(src: string, dest: string): Promise<void> {
  const entries = await readdir(src);
  for (const entry of entries) {
    await rename(`${src}/${entry}`, `${dest}/${entry}`);
  }
}

export default function (api: any) {
  // ── canvas_folder ─────────────────────────────────────────────────────
  api.registerTool({
    name: "canvas_folder",
    description:
      "Get the canvas workspace directory path. Call this first to know " +
      "where to write HTML/CSS/JS files. Files placed here are served at " +
      "http://localhost:3100/canvas/. No build tools are available — use " +
      "CDN links for third-party libraries.",
    parameters: Type.Object({}),
    async execute() {
      await mkdir(CANVAS_DIR, { recursive: true });
      return text(
        `Canvas workspace: ${CANVAS_DIR}\n` +
          `Served at: ${CANVAS_BASE_URL}\n\n` +
          "Write your HTML/CSS/JS files here. Use canvas_open to display them.\n" +
          "No build tools (npm, yarn, webpack) — use CDN links for libraries:\n" +
          '  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>',
      );
    },
  });

  // ── canvas_open ───────────────────────────────────────────────────────
  api.registerTool({
    name: "canvas_open",
    description:
      "Navigate the kiosk Chromium browser to canvas content via CDP. " +
      "Call after writing files to the canvas directory.",
    parameters: Type.Object({
      path: Type.Optional(
        Type.String({
          description:
            'Relative path within the canvas directory (default: "index.html")',
        }),
      ),
    }),
    async execute(_id: string, params: { path?: string }) {
      const relPath = params.path ?? "index.html";
      const url = `${CANVAS_BASE_URL}${relPath}`;
      await cdpNavigate(url);
      return text(`Navigated to ${url}`);
    },
  });

  // ── canvas_close ──────────────────────────────────────────────────────
  api.registerTool({
    name: "canvas_close",
    description:
      "Navigate the kiosk Chromium browser back to the landing page.",
    parameters: Type.Object({}),
    async execute() {
      await cdpNavigate(LANDING_URL);
      return text("Navigated back to landing page.");
    },
  });

  // ── canvas_archive ────────────────────────────────────────────────────
  api.registerTool({
    name: "canvas_archive",
    description:
      "Archive the current canvas project. Moves ALL canvas files into a " +
      "new named subdirectory in the archive, then clears the workspace. " +
      "Always call this before starting a new project. If the canvas is " +
      "empty, this is a no-op. Never move files to the archive manually.",
    parameters: Type.Object({
      name: Type.String({
        description:
          "Short descriptive project name. Lowercase, dashes, no spaces " +
          '(e.g. "weather-dashboard", "photo-gallery").',
      }),
    }),
    async execute(_id: string, params: { name: string }) {
      if (!(await dirHasContent(CANVAS_DIR))) {
        return text("Canvas is empty — nothing to archive.");
      }

      await mkdir(ARCHIVE_DIR, { recursive: true });
      const finalName = await uniqueArchiveName(params.name);
      const dest = `${ARCHIVE_DIR}/${finalName}`;
      await mkdir(dest, { recursive: true });
      await moveAllEntries(CANVAS_DIR, dest);

      return text(`Archived to ${dest}\nCanvas is now empty.`);
    },
  });

  // ── canvas_list_archive ───────────────────────────────────────────────
  api.registerTool({
    name: "canvas_list_archive",
    description: "List all archived canvas projects.",
    parameters: Type.Object({}),
    async execute() {
      if (!existsSync(ARCHIVE_DIR)) {
        return text("No archive directory found. No projects archived yet.");
      }
      const entries = readdirSync(ARCHIVE_DIR, { withFileTypes: true })
        .filter((e) => e.isDirectory())
        .map((e) => e.name)
        .sort();

      if (entries.length === 0) {
        return text("Archive is empty.");
      }

      return text(`Archived projects:\n${entries.map((e) => `  - ${e}`).join("\n")}`);
    },
  });

  // ── canvas_restore ────────────────────────────────────────────────────
  api.registerTool({
    name: "canvas_restore",
    description:
      "Restore an archived project back into the active canvas workspace. " +
      "Files are COPIED from the archive (the archive is preserved, not deleted). " +
      "If the canvas currently has content, it is automatically archived " +
      "first (you must provide auto_archive_name for the current project). " +
      "After restoring, reload the page and navigate to the canvas if the " +
      "browser is not already showing it.",
    parameters: Type.Object({
      name: Type.String({
        description:
          "Name of the archived project to restore (as shown by canvas_list_archive).",
      }),
      auto_archive_name: Type.Optional(
        Type.String({
          description:
            "If the canvas is non-empty, archive it first under this name. " +
            "Required when the canvas has content.",
        }),
      ),
    }),
    async execute(
      _id: string,
      params: { name: string; auto_archive_name?: string },
    ) {
      const srcDir = `${ARCHIVE_DIR}/${params.name}`;
      if (!existsSync(srcDir)) {
        return text(
          `Error: No archived project named "${params.name}". ` +
            "Use canvas_list_archive to see available projects.",
        );
      }

      // Auto-archive current canvas if non-empty
      if (await dirHasContent(CANVAS_DIR)) {
        const archiveName = params.auto_archive_name;
        if (!archiveName) {
          return text(
            "Error: Canvas is non-empty. Provide auto_archive_name to " +
              "archive the current project first.",
          );
        }
        await mkdir(ARCHIVE_DIR, { recursive: true });
        const finalName = await uniqueArchiveName(archiveName);
        const dest = `${ARCHIVE_DIR}/${finalName}`;
        await mkdir(dest, { recursive: true });
        await moveAllEntries(CANVAS_DIR, dest);
      }

      // Copy archived project into canvas (archive is preserved)
      await mkdir(CANVAS_DIR, { recursive: true });
      const entries = await readdir(srcDir);
      for (const entry of entries) {
        await cp(`${srcDir}/${entry}`, `${CANVAS_DIR}/${entry}`, {
          recursive: true,
        });
      }

      return text(
        `Restored "${params.name}" to ${CANVAS_DIR}\n` +
          "Call canvas_open to display it.",
      );
    },
  });
}
