import socket
import threading
import json
import hashlib
import itertools, queue, threading
import mini_dfs.utils as utils
from mini_dfs.globals import *


class NameServer():
    def __init__(self, name = "name-server", host=HOST, client_port=CLIENT_PORT, server_port=CHUNK_SERVER_PORT):
        self.name = name
        self.host = host
        self.client_port = client_port
        self.server_port = server_port
        self.client_sock = None
        self.server_sock = None
        self.lut = dict()
        self.lut_lock:threading.Lock=threading.Lock()
        self.chunk_servers_socks = []
        self.chunk_servers_socks_lock:threading.Lock=threading.Lock()
        self.is_running = False

    def __str__(self):
        return f"[NameServer {self.name}, {self.host}, {self.client_port}]"

    def start(self):        
        self.client_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.client_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.client_sock.bind((self.host, self.client_port))
        self.client_sock.listen()
        self.is_running = True
        threading.Thread(target=self._accept_clients, daemon=True).start()
        
        self.server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_sock.bind((self.host, self.server_port))
        self.server_sock.listen()
        threading.Thread(target=self._accept_servers, daemon=True).start()

    def stop(self):
        print(f"{self} is disconnecting...")
        self.is_running = False
        for sock in [self.client_sock, self.server_sock]:
            if sock:
                try:
                    sock.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                sock.close()
    
    def _accept_servers(self): 
        while self.is_running:
            try:
                server_conn, server_addr = self.server_sock.accept()
                threading.Thread(target=self._listen_server, args=(server_conn,server_addr), daemon=True).start()
            except OSError:
                break

    def _accept_clients(self):
        while self.is_running:
            try:
                client_conn, client_addr = self.client_sock.accept()
                threading.Thread(target=self._listen_client, args=(client_conn,client_addr), daemon=True).start()
            except OSError:
                break

    def _listen_server(self, server_sock, server_addr):
        conn = utils.QueueConn(server_sock)
        with self.chunk_servers_socks_lock:
            self.chunk_servers_socks.append(server_sock)
        try:
            with server_sock:
                while self.is_running:
                    try:
                        req = json.loads(utils.recv_data(server_sock, bytes=False))
                    except ConnectionResetError:
                        break
                    if conn.dispatch_response(req):
                        continue                     # it was a reply to a request()
                    match req["action"]:
                        case "message":
                            self.process_message_request(req, conn)
                        case _:
                            print(f"{self} unknown request: {req}")
        finally:
            with self.chunk_servers_socks_lock:
                self.chunk_servers_socks.remove(conn)
            conn.close_all_pending()
    
    def _listen_client(self, client_conn, client_addr):
        with client_conn:
            while self.is_running:
                try:
                    req = json.loads(utils.recv_data(client_conn,bytes=False))
                    match req["action"]:
                        case "message":
                            self.process_message_request(req, client_conn)
                        case "allocate":
                            self.process_allocate_request(req,client_conn)
                        case "list":
                            self.process_list_request(req,client_conn)
                        case _:
                            print(f"{self} has received an unknown request: {req}")
                except ConnectionResetError:
                    break

    def getall_storage(self):
        out = []
        for i, conn in enumerate(self.chunk_servers_socks):
            utils.send_data(conn, {"action":"storage"})
            response = json.loads(utils.recv_data(conn, bytes=False))
            if response["action"] == "storage":
                out.append(int(response["memory"]))
            else:
                print(f"{self} has received an unknown response: {response}")
        return out

    def send_message(self, conn, msg):
        packet = {
            "action":"message",
            "payload":msg
        }
        utils.send_data(conn, json.dumps(packet))

    def process_message_request(self, req, client_conn):
        print(f"{self} Received from {req["clientname"]}: {req["payload"]}")

    def process_list_request(self, req, client_conn):
        client_name = req["clientname"]
        filenames = []
        if client_name in self.lut:
            filenames = list(self.lut[client_name].keys())
        utils.send_data(client_conn, {
            "action":"list",
            "filenames":filenames
            })
    
    def process_allocate_request(self, req, client_conn):
        client_name, chunk_number, filename = req["clientname"], req["chunk_number"], req["filename"]
        print(f"{self} received an allocation request of {chunk_number} chunks")
        
        # if the file already exists, return
        with self.lut_lock:    
            if filename in self.lut.get(client_name, {}):
                self.send_message(client_conn, f"{filename} already exists in the database!")
                return

        # find the best chunk configuration according to the servers storage
        memories = self.getall_storage()
        servers_number = min(len(memories), N_REPLICAS)
        assigned_servers = []
        for _ in range(chunk_number):
            chosen = utils.argsort(memories)[:servers_number]
            assigned_servers.append(chosen)
            for j in chosen:
                memories[j] += 1

        if max(memories) > MAX_N_CHUNK_SERVER:
            self.send_message(client_conn, f"{filename} couldn't be written: not enough space!")
            return

        # proceed chunk allocation and remember where the chunks are as for replicas.
        chunks = []
        for chosen in assigned_servers:
            replicas = []
            for j in chosen:
                sock = self.chunk_servers_socks[j]
                utils.send_data(sock, json.dumps({"action": "allocate"}).encode())
                response = json.loads(utils.recv_data(sock, bytes=False))
                if response.get("status") != "ok":
                    raise MemoryError(f"the server {j} couldn't allocate enough memory!")
                host, port = response["client_host"], response["client_port"]
                replicas.append({"host":host, "port":port, "file_index":response["file_index"]})
            chunks.append(replicas)

        with self.lut_lock:
            self.lut.setdefault(client_name, {})[filename] = {"chunk_handles": chunks}

        self.send_message(client_conn, {"status": "ok", "chunks": chunks})
