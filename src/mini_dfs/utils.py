import os
import json
import base64
import socket
import struct
import itertools, queue, threading, time

from mini_dfs.globals import CHUNK_SIZE

def argsort(l : list, reverse=False):
    indices = sorted(range(len(l)), key=l.__getitem__, reverse=reverse)
    return indices

def connect_with_retry(sock : socket.socket, address, attempts=30, delay=1.0) -> None:
    """Connects the socket, retrying while the peer isn't up yet (containers start in any order)."""
    for attempt in range(attempts):
        try:
            sock.connect(address)
            return
        except (ConnectionRefusedError, socket.gaierror):
            if attempt == attempts - 1:
                raise
            time.sleep(delay)

# send/receive data packets the right way

def send_data(sock : socket.socket, data) -> None:
    if isinstance(data, dict):
        data = json.dumps(data).encode('utf-8')
    elif isinstance(data, str):
        data = data.encode('utf-8')
    elif isinstance(data, (bytearray, bytes)):
        data = bytes(data)
    else:
        raise TypeError(f"str or bytes were expected, received {type(data).__name__}")
    sock.sendall(struct.pack(">I", len(data)) + data)

def recv_exact(sock : socket.socket, n : int) -> bytearray:
    buf = bytearray()
    while len(buf) < n:
        data = sock.recv(n-len(buf))
        if not data:
            raise ConnectionError("Lost connection !")
        buf += data
    return buf

def recv_data(sock : socket.socket, bytes):
    data_size = struct.unpack(">I", recv_exact(sock, 4))[0]
    if bytes == True:
        return recv_exact(sock, data_size)
    else :
        return recv_exact(sock, data_size).decode('utf-8')

class QueueConn:
    """Wraps one socket shared by a listener thread and requesting threads."""
    def __init__(self, sock):
        self.sock = sock
        self.send_lock = threading.Lock()
        self.pending = {}                       # request_id -> queue.Queue
        self.pending_lock = threading.Lock()
        self.ids = itertools.count()

    def send(self, payload):
        with self.send_lock:
            send_data(self.sock, payload)

    def close(self):
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()

    def reply(self, req, payload):
        """Answers req, echoing its request_id so the peer's request() gets it."""
        self.send({**payload, "request_id": req.get("request_id")})

    def listen(self, handler, is_running=lambda: True):
        """
        Single reader of the socket: routes responses to the waiting request()
        and passes every other message to handler(msg). Returns when the connection is lost.
        """
        try:
            while is_running():
                msg = json.loads(recv_data(self.sock, bytes=False))
                if self.dispatch_response(msg):
                    continue
                handler(msg)
        except (OSError, struct.error):     # ConnectionError is an OSError
            pass
        finally:
            self.close_all_pending()

    def request(self, payload, timeout=5):
        rid = next(self.ids)
        q = queue.Queue(maxsize=1)
        with self.pending_lock:
            self.pending[rid] = q
        try:
            with self.send_lock:
                send_data(self.sock, {**payload, "request_id": rid})
            resp = q.get(timeout=timeout)
            if resp is None:
                raise ConnectionError("connection closed")
            return resp
        finally:
            with self.pending_lock:
                self.pending.pop(rid, None)     # cleanup on timeout/error too

    def dispatch_response(self, msg):
        """Called by the reader. Returns True if msg was a response."""
        rid = msg.get("request_id")
        if rid is None:
            return False
        with self.pending_lock:
            q = self.pending.get(rid)
        if q is None:
            return False        # late reply for a timed-out request: drop it
        q.put(msg)
        return True

    def close_all_pending(self):
        with self.pending_lock:
            for q in self.pending.values():
                q.put(None)     # wake up waiters