#!/usr/bin/env python3
"""Take a screenshot of the kiosk Chromium via CDP.

Requires an SSH tunnel to the Pi's CDP port:
  ssh -i id_ed25519_rpi5 -L 9222:127.0.0.1:9222 -N nixos@openclaw-rpi5.local

Usage:
  ./scripts/screenshot.py [output.png]
  nix develop --command python3 scripts/screenshot.py [output.png]
"""

import json
import base64
import asyncio
import sys

import websockets


CDP_URL = "http://localhost:9222"
DEFAULT_OUTPUT = "/tmp/clawpi-screenshot.png"


async def get_page_ws_url():
    """Fetch the first page's WebSocket debugger URL from CDP."""
    import urllib.request
    with urllib.request.urlopen(f"{CDP_URL}/json") as resp:
        targets = json.loads(resp.read())
    for target in targets:
        if target.get("type") == "page":
            return target["webSocketDebuggerUrl"]
    raise RuntimeError("No page target found on CDP")


async def capture(output_path: str):
    ws_url = await get_page_ws_url()
    async with websockets.connect(ws_url) as ws:
        await ws.send(json.dumps({
            "id": 1,
            "method": "Page.captureScreenshot",
            "params": {"format": "png"},
        }))
        resp = json.loads(await ws.recv())
        if "error" in resp:
            raise RuntimeError(f"CDP error: {resp['error']}")
        data = base64.b64decode(resp["result"]["data"])
        with open(output_path, "wb") as f:
            f.write(data)
        print(f"Screenshot saved to {output_path} ({len(data)} bytes)")


def main():
    output = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUTPUT
    asyncio.run(capture(output))


if __name__ == "__main__":
    main()
