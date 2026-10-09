import socket
import threading
from mini_dfs.utils import handout_port
from mini_dfs.globals import server_ready

HOST = 'localhost'

class ChunkServer():
    def __init__(self, name = "chunk-server", host = HOST):
        self.name = name
        self.host = host
        self.sock = None
        self.is_running = False
        self.bytes = []

    def __str__(self):
        return f"[ChunkServer {self.name}, {self.host}, {self.port}]"

    def start(self):        
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        if self.port == None:
            print(f"{self} hasn't any bound port yet !")
        if not server_ready.wait(timeout=5):
            print(f"{self} Error : Server hasn't started on time.")
            return
        self.sock.connect((self.host, self.port))
        self.is_running = True
        threading.Thread(target=self._listen, daemon=True).start()

    def _listen(self):
        while self.is_running:
            try:
                client_conn, client_addr = self.sock.accept()
                threading.Thread(target=self._handle_client, args=(client_conn,), daemon=True).start()
            except OSError:
                break

    def _handle_client(self, conn):
        try:
            while self.is_running:
                data = conn.recv(1024)
                if not data:
                    break
                print(f"{self} Received from client: {data.decode('utf-8')}")
        finally:
            conn.close()

    def stop(self):
        print(f"{self} is disconnecting...")
        self.is_running = False
        if self.sock:
            try:
                self.sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.sock.close()

    def _on_disconnect_callback(self):
        print(f"{self} has terminated.")
