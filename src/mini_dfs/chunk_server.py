import socket
import threading
import json
import os
from shutil import rmtree
import hashlib

from mini_dfs.globals import *
import mini_dfs.utils as utils

class ChunkServer():
    def __init__(self, name = "chunk-server", host = NAMESERVER_HOST, nameserver_port = None, advertise_host = None, client_port = CHUNK_CLIENT_PORT):
        self.name = name
        self.host = host    # name server address
        self.advertise_host = advertise_host or ADVERTISE_HOST or host    # address given to clients
        self.client_port = client_port
        self.nameserver_conn = None
        self.nameserver_port = nameserver_port
        self.client_sock = None
        self.is_running = False
        self.dir_lock:threading.Lock=threading.Lock()

    def __str__(self):
        return f"[ChunkServer {self.name}, {self.host}, {self.nameserver_port}]"

    def start(self):
        os.makedirs(self.name, exist_ok=True)
        with open(os.path.join(self.name, "checksum.txt"), "w") as file:
            for i in range(MAX_N_CHUNK_SERVER):
                file.write("\n")
        nameserver_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        if self.nameserver_port == None:
            print(f"{self} hasn't any bound port yet !")
        utils.connect_with_retry(nameserver_sock, (self.host, self.nameserver_port))
        self.nameserver_conn = utils.QueueConn(nameserver_sock)
        self.is_running = True
        threading.Thread(target=self._listen_nameserver, daemon=True).start()
        
        self.client_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.client_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.client_sock.bind(("0.0.0.0", self.client_port))
        self.client_sock.listen()
        threading.Thread(target=self._accept_clients, daemon=True).start()

    def stop(self):
        print(f"{self} is disconnecting...")
        self.is_running = False
        if os.path.exists(self.name): ## Clears the whole storage before starting another session.
            rmtree(self.name)
        if self.nameserver_conn:
            self.nameserver_conn.close()
        if self.client_sock:
            self.client_sock.close()

    def _listen_nameserver(self):
        self.nameserver_conn.listen(self._handle_nameserver_msg, lambda: self.is_running)

    def _handle_nameserver_msg(self, req):
        match req.get("action"):
            case "storage":
                self.process_storage_request(req)
            case "allocate":
                self.process_allocate_request(req)
            case _:
                print(f"{self} unknown request: {req}")

    def _accept_clients(self):
        while self.is_running:
            try:
                client_conn, client_addr = self.client_sock.accept()
                threading.Thread(target=self._listen_client, args=(client_conn,client_addr), daemon=True).start()
            except OSError:
                break

    def _listen_client(self, client_conn, client_addr):
        # no socket timeout: it could fire mid-frame and desynchronize the stream
        with client_conn:
            while self.is_running:
                try:
                    req = json.loads(utils.recv_data(client_conn, bytes=False))
                    action = req["action"]
                    if action == "write":
                        self.process_write_request(client_conn, req)
                    elif action == "read":
                        self.process_read_request(client_conn, req)
                    else:
                        self.send_message(client_conn, f"unknown action : {action}")
                except OSError:     # includes ConnectionError
                    break

    def send_message(self, conn, msg):
        req = {
            "action" : "message",
            "payload" : msg
        }
        utils.send_data(conn, req)

    def process_allocate_request(self, req):
        with self.dir_lock:
            os.makedirs(self.name, exist_ok=True)
            if len(os.listdir(self.name)) > MAX_N_CHUNK_SERVER: ## If no more place in servers
                self.nameserver_conn.reply(req, {"status": "nok"})
                return
            used = {
                int(f[:-4])
                for f in os.listdir(self.name)
                if f.endswith(".bin") and f[:-4].isdigit()
            }
            index = min(set(range(len(used) + 1)) - used)
            open(os.path.join(self.name, f"{index}.bin"), "wb").close()
        client_host, client_port = self.advertise_host, self.client_sock.getsockname()[1]  # getsockname() host is 0.0.0.0 (bind address)
        self.nameserver_conn.reply(req, {"status": "ok", "client_host": client_host, "client_port": client_port, "file_index": index})

    def process_storage_request(self, req):
        response = {
            "action":"storage",
            "memory":sum(1 for filename in os.listdir(self.name) if filename[-4:] == ".bin")
        }
        self.nameserver_conn.reply(req, response)

    def process_write_request(self, conn:utils.QueueConn, req):
        file_index = req["file_index"]
        data = utils.recv_data(conn, bytes=True)
        # write chunk
        with open(os.path.join(self.name,f"{file_index}.bin"), "r+b") as file:
            file.write(data)

        # write its checksum in the checksum.txt
        with open(os.path.join(self.name,f"checksum.txt"), "r") as checksum_file:
            checksums = checksum_file.readlines()
        checksums[file_index] = hashlib.md5(data).hexdigest()
        with open(os.path.join(self.name,f"checksum.txt"), "w") as checksum_file:
            checksum_file.writelines(checksums)
        utils.send_data(conn, {"status":"ok"})

    def process_read_request(self, conn:socket.socket, req):
        file_index = req["file_index"]
        filenames = [int(filename[:-4]) for filename in os.listdir(self.name) if filename != 'checksum.txt']
        if file_index not in filenames:
            utils.send_data(conn, {'status':'nok', 'payload':'did not find a chunk from the stored file...'})
            return
        with open(os.path.join(self.name, str(file_index)+'.bin'), 'rb') as file:
            chunk = file.read()
        utils.send_data(conn, {'status':'ok'})
        utils.send_data(conn, chunk)