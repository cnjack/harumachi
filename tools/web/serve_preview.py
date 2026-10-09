#!/usr/bin/env python3
"""Local browser preview with isolation headers and precompressed Web assets."""
from pathlib import Path
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import argparse
import mimetypes
import re

parser = argparse.ArgumentParser()
parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2] / "site")
parser.add_argument("--port", type=int, default=8770)
args = parser.parse_args()
ROOT = args.root.resolve()
mimetypes.add_type("application/wasm", ".wasm")


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def end_headers(self):
        if self.path.startswith("/play/"):
            self.send_header("Cross-Origin-Opener-Policy", "same-origin")
            self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def send_head(self):
        path = Path(self.translate_path(self.path))
        match = re.fullmatch(r"bytes=(\d+)-(\d+)", self.headers.get("Range", ""))
        if not match or not path.is_file():
            return super().send_head()
        start, end = map(int, match.groups())
        size = path.stat().st_size
        if start >= size or end < start:
            self.send_error(416)
            return None
        end = min(end, size - 1)
        source = path.open("rb")
        source.seek(start)
        self._remaining = end - start + 1
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(str(path)))
        self.send_header("Content-Length", str(self._remaining))
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        return source

    def copyfile(self, source, destination):
        if not hasattr(self, "_remaining"):
            return super().copyfile(source, destination)
        while self._remaining:
            piece = source.read(min(65536, self._remaining))
            if not piece:
                break
            destination.write(piece)
            self._remaining -= len(piece)


print(f"Harumachi preview: http://127.0.0.1:{args.port}/", flush=True)
ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
