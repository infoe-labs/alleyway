#!/usr/bin/env python3
"""Local dev server for the web export: python3 tools/serve.py [dist]

Serves the exported build with the MIME types browsers require for wasm.
"""
from __future__ import annotations

import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript",
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".json": "application/json",
    }


def main() -> None:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("dist")
    if not (root / "index.html").exists():
        sys.exit(f"{root}/index.html not found — export the Web build first (see README).")
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8080
    httpd = ThreadingHTTPServer(("0.0.0.0", port), partial(Handler, directory=str(root)))
    print(f"serving {root.resolve()} at http://localhost:{port}/index.html  (Ctrl+C to stop)")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
