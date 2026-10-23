# Spotify's page over the Chromium DevTools protocol. Spotify has to start with
# --remote-debugging-port (see spotify-launcher.conf). Plain sockets, no extra packages

import base64
import json
import os
import socket
import struct
import urllib.request

PORT = int(os.environ.get("SPOTIFY_CDP_PORT", "9227"))


class Page:
    def __init__(self, timeout=5):
        with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json", timeout=timeout) as r:
            pages = json.load(r)
        url = next(p["webSocketDebuggerUrl"] for p in pages if p["type"] == "page" and "xpui" in p["url"])
        path = url.split(str(PORT), 1)[1]
        self.sock = socket.create_connection(("127.0.0.1", PORT), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{PORT}\r\nUpgrade: websocket\r\n"
                           f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(1024)
            if not chunk:
                raise ConnectionError("handshake")
            head += chunk
        if b" 101 " not in head.split(b"\r\n", 1)[0]:
            raise ConnectionError(head.split(b"\r\n", 1)[0].decode())
        self.buf = head.split(b"\r\n\r\n", 1)[1]
        self.next_id = 0

    def recv_exact(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send(self, text):
        data = text.encode()
        mask = os.urandom(4)
        n = len(data)
        head = bytes([0x81]) + (bytes([0x80 | n]) if n < 126 else
                                bytes([0x80 | 126]) + struct.pack(">H", n) if n < 65536 else
                                bytes([0x80 | 127]) + struct.pack(">Q", n))
        self.sock.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

    def read(self):
        msg = b""
        while True:
            b0, b1 = self.recv_exact(2)
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self.recv_exact(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self.recv_exact(8))[0]
            msg += self.recv_exact(n)
            if b0 & 0x80:
                return msg.decode()

    # Evaluates a JS expression in the page, awaiting promises, and returns its JSON value
    def eval(self, expr):
        self.next_id += 1
        self.send(json.dumps({"id": self.next_id, "method": "Runtime.evaluate",
                              "params": {"expression": expr, "awaitPromise": True, "returnByValue": True}}))
        while True:
            reply = json.loads(self.read())
            if reply.get("id") == self.next_id:
                result = reply.get("result", {})
                if "exceptionDetails" in result:
                    raise RuntimeError(result["exceptionDetails"].get("exception", {}).get("description", "error"))
                return result.get("result", {}).get("value")
