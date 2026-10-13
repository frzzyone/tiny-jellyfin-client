#!/usr/bin/env python3
"""Tiny HTTP server with Range support for PlayerCore tests.

Serves files from a directory and prints the chosen port on stdout. Supports:
  ?drop=N    the first request for this path is cut off after N bytes
  ?norange=1 ignore Range headers (always 200 with the full body)
  ?status=N  reply with that status code
  ?slow=S    sleep S seconds after every 64 KB sent
Requests must carry `Authorization: test` unless the path starts with /public/.
"""
import http.server
import os
import socketserver
import sys
import time
import urllib.parse

ROOT = sys.argv[1]
dropped = set()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def empty(self, status, headers=()):
        self.send_response(status)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        if "status" in query:
            return self.empty(int(query["status"][0]))
        public = url.path.startswith("/public/")
        if not public and self.headers.get("Authorization") != "test":
            return self.empty(401)
        rel = url.path[len("/public/"):] if public else url.path.lstrip("/")
        path = os.path.join(ROOT, urllib.parse.unquote(rel))
        if not os.path.isfile(path):
            return self.empty(404)
        size = os.path.getsize(path)
        start, end, partial = 0, size - 1, False
        rng = self.headers.get("Range")
        if rng and "norange" not in query and rng.startswith("bytes="):
            a, _, b = rng[6:].partition("-")
            start = int(a)
            end = int(b) if b else size - 1
            if start >= size:
                return self.empty(416, [("Content-Range", f"bytes */{size}")])
            partial = True
        length = end - start + 1
        self.send_response(206 if partial else 200)
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        limit = None
        if "drop" in query and url.path not in dropped:
            dropped.add(url.path)
            limit = int(query["drop"][0])
        with open(path, "rb") as f:
            f.seek(start)
            sent = 0
            while sent < length:
                chunk = f.read(min(65536, length - sent))
                if not chunk:
                    break
                if limit is not None and sent + len(chunk) > limit:
                    self.wfile.write(chunk[: max(0, limit - sent)])
                    self.wfile.flush()
                    self.close_connection = True
                    self.connection.shutdown(2)
                    return
                self.wfile.write(chunk)
                sent += len(chunk)
                if "slow" in query:
                    time.sleep(float(query["slow"][0]))


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def handle_error(self, request, client_address):
        # Clients cancel requests all the time (seeks, parking); don't print tracebacks.
        pass

    def server_bind(self):
        # HTTPServer.server_bind calls socket.getfqdn(), a reverse DNS lookup that can stall
        # for ~30 s on CI machines.
        socketserver.TCPServer.server_bind(self)
        self.server_name = "localhost"
        self.server_port = self.server_address[1]


server = Server(("127.0.0.1", 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
