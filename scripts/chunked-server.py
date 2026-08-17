#!/usr/bin/env python3
import http.server
import pathlib
import sys


class ChunkedHandler(http.server.BaseHTTPRequestHandler):
    root = pathlib.Path()

    def do_GET(self):
        relative = pathlib.PurePosixPath(self.path.split("?", 1)[0].lstrip("/"))
        if any(part in ("", ".", "..") for part in relative.parts):
            self.send_error(400)
            return
        path = self.root.joinpath(*relative.parts)
        if not path.is_file():
            self.send_error(404)
            return
        body = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        for offset in range(0, len(body), 4096):
            chunk = body[offset : offset + 4096]
            self.wfile.write(f"{len(chunk):x}\r\n".encode("ascii"))
            self.wfile.write(chunk)
            self.wfile.write(b"\r\n")
        self.wfile.write(b"0\r\n\r\n")

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    ChunkedHandler.root = pathlib.Path(sys.argv[1]).resolve()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2])), ChunkedHandler)
    server.serve_forever()
