import socket
import threading
import json
import os
from shutil import rmtree

from mini_dfs.globals import *
import mini_dfs.utils as utils

HOST = 'localhost'

class ChunkServer():
    def __init__(self, name = "chunk-server", host = HOST, port = None):
        self.name = name
        self.host = host
        self.nameserver_sock = None
        self.nameserver_port = port
        self.client_sock = None
        self.is_running = False
        self.dir_lock:threading.Lock=threading.Lock()

    def __str__(self):
        return f"[ChunkServer {self.name}, {self.host}, {self.nameserver_port}]"

    def start(self):
        if os.path.exists(self.name): ## Clears the whole storage before starting another session.
            rmtree(self.name)
        os.makedirs(self.name, exist_ok=True)
        self.nameserver_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        if self.nameserver_port == None:
            print(f"{self} hasn't any bound port yet !")
        self.nameserver_sock.connect((self.host, self.nameserver_port))
        self.is_running = True
        threading.Thread(target=self._listen_nameserver, daemon=True).start()
        
        self.client_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.client_sock.bind(("0.0.0.0", 0))
        self.client_sock.listen()
        threading.Thread(target=self._accept_clients, daemon=True).start()

    def stop(self):
        print(f"{self} is disconnecting...")
        self.is_running = False
        if self.nameserver_sock:
            try:
                self.nameserver_sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.nameserver_sock.close()

    def _listen_nameserver(self):
        while self.is_running:
            req = utils.recv_data(self.nameserver_sock, bytes=False)
            req = json.loads(req)
            match req["action"]:
                case "storage":
                    self.process_storage_request(req)
                case "allocate":
                    self.process_allocate_request(req)

    def _accept_clients(self):
        while self.is_running:
            try:
                client_conn, client_addr = self.client_sock.accept()
                threading.Thread(target=self._listen_client, args=(client_conn,client_addr), daemon=True).start()
            except OSError:
                break

    def _listen_client(self, client_conn, client_addr):
        client_conn.settimeout(1.0)
        with client_conn:
            while self.is_running:
                try:
                    data = utils.recv_data(client_conn, bytes=False)
                except socket.timeout:
                    continue
                except (ConnectionResetError, BrokenPipeError):
                    break
                if not data:
                    break
                req = json.loads(data)
                action = req["action"]
                if action == "write":
                    self.process_write_request(client_conn, req)
                else:
                    self.send_message(client_conn, f"unknown action : {action}")

    def send_message(self, conn, msg):
        req = {
            "action" : "message",
            "payload" : msg
        }
        utils.send_data(conn, req)

    def process_allocate_request(self, conn, req):
        with self.dir_lock:
            os.makedirs(self.name, exist_ok=True)
            if len(os.listdir(self.name)) > MAX_N_CHUNK_SERVER: ## If no more place in servers
                utils.send_data(conn, {"status": "nok"})
                return
            used = {
                int(f[:-4])
                for f in os.listdir(self.name)
                if f.endswith(".bin") and f[:-4].isdigit()
            }
            index = min(set(range(len(used) + 1)) - used)
            open(os.path.join(self.name, f"{index}.bin"), "wb").close()
        client_host, client_port = self.client_sock.getsockname()
        utils.send_data(conn, {"status": "ok", "client_host": client_host, "client_port": client_port,"index": index})

    def process_storage_request(self, req):
        response = {
            "action":"storage",
            "memory":sum(1 for filename in os.listdir(self.name) if filename[-4:] == ".bin")
        }
        utils.send_data(self.nameserver_sock,response)

    def process_write_request(self, conn, req):
        file_index = req["file_index"]
        data = utils.recv_data(self.nameserver_sock, bytes=True)
        with open(os.path.join(self.name,f"{file_index}.bin"), "r+b") as file:
            file.write(data)
        utils.send_data(conn, {"status":"ok"})
