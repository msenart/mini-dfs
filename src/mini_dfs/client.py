import socket
import threading
import os
from mini_dfs.globals import server_ready, HOST, CHUNK_SIZE

import json
class Client():
    def __init__(self, name = "client", host = HOST, port = None):
        self.name = name
        self.host = host
        self.port = None
        self.sock = None
        self.is_running = False

    def __str__(self):
        return f"[Client {self.name}, {self.host}, {self.port}]"

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
        try:
            while self.is_running:
                data = self.sock.recv(1024)
                if not data:
                    break
                print(f"{self} received {data}")
        except OSError:
            pass
        print(f"{self} has disconnected.")

    def send_message(self, msg):
        """
        Sends a message to the name server. request format : msg = <payload> 
        """
        try:
            message = {
                "action": "message",
                "payload": msg
                }
            packet = (json.dumps(message) + "\n").encode('utf-8')
            self.sock.sendall(packet)
            print(f"{self} has sent the message !")
        except OSError as e:
            print(f"{self} couldn't send message !")

    def send_write(self, path):
        """
        Sends a write request to the name server. request format : msg = <path>
        """

        header = {
            "action": "write",
            "size": os.path.getsize(path)
        }
        header_packet = json.dumps(header).encode('utf-8')
        self.sock.sendall(header_packet)

        with open(path, "rb") as file:
            while True:
                chunk = file.read(CHUNK_SIZE)
                if not chunk:
                    break
                self.sock.sendall(chunk)
        

    def stop(self):
        print(f"{self} is disconnecting...")
        self.is_running = False
        if self.sock:
            try:
                self.sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.sock.close()
