import socket
import threading
import json
import itertools, queue, threading
import mini_dfs.utils as utils
from mini_dfs.globals import *


class NameServer():
    def __init__(self, name = "name-server", host=BIND_HOST, client_port=CLIENT_PORT, server_port=CHUNK_SERVER_PORT):
        self.name = name
        self.host = host
        self.client_port = client_port
        self.server_port = server_port
        self.client_sock = None
        self.server_sock = None
        self.lut = dict()
        self.lut_lock:threading.Lock=threading.Lock()
        self.chunk_servers_conns = []
        self.chunk_servers_conns_lock:threading.Lock=threading.Lock()
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
        with self.chunk_servers_conns_lock:
            self.chunk_servers_conns.append(conn)
        try:
            with server_sock:
                conn.listen(lambda req: self._handle_server_msg(req, conn), lambda: self.is_running)
        finally:
            with self.chunk_servers_conns_lock:
                self.chunk_servers_conns.remove(conn)

    def _handle_server_msg(self, req, conn: utils.QueueConn):
        match req.get("action"):
            case "message":
                self.process_message_request(req, conn)
            case _:
                print(f"{self} unknown request: {req}")

    def _listen_client(self, client_sock, client_addr):
        conn = utils.QueueConn(client_sock)
        with client_sock:
            conn.listen(lambda req: self._handle_client_msg(req, conn), lambda: self.is_running)

    def _handle_client_msg(self, req, conn: utils.QueueConn):
        match req.get("action"):
            case "message":
                self.process_message_request(req, conn)
            case "allocate":
                self.process_allocate_request(req, conn)
            case "list":
                self.process_list_request(req, conn)
            case "read":
                self.process_read_request(req, conn)
            case _:
                print(f"{self} has received an unknown request: {req}")

    def getall_storage(self, conns: list[utils.QueueConn]):
        out = []
        for conn in conns:
            response = conn.request({"action":"storage"})
            out.append(int(response["memory"]))
        return out

    def process_message_request(self, req, client_conn: utils.QueueConn):
        print(f"{self} Received from {req["clientname"]}: {req["payload"]}")

    def process_list_request(self, req, client_conn: utils.QueueConn):
        client_name = req["clientname"]
        filenames = []
        if client_name in self.lut:
            filenames = list(self.lut[client_name].keys())
        client_conn.reply(req, {"action":"list", "filenames":filenames})

    def process_read_request(self, req, conn: utils.QueueConn):
        clientname, filename = req['clientname'], req['filename']
        if (filename not in self.lut[clientname]):      # We suppose clientname is always in the lut.
            conn.reply(req, {"status":"nok", "payload":"no such filename found in the database !"})
            return
        conn.reply(req, {"status":"ok", "payload":self.lut[clientname][filename]["chunk_handles"]})

    def process_allocate_request(self, req, client_conn: utils.QueueConn):
        client_name, chunk_number, filename = req["clientname"], req["chunk_number"], req["filename"]
        print(f"{self} received an allocation request of {chunk_number} chunks")

        # if the file already exists, return
        with self.lut_lock:
            if filename in self.lut.get(client_name, {}):
                client_conn.reply(req, {"status": "nok", "message": f"{filename} already exists in the database!"})
                return

        # find the best chunk configuration according to the servers storage
        with self.chunk_servers_conns_lock:
            conns = list(self.chunk_servers_conns)  # snapshot: indices must stay consistent below
        if not conns:
            client_conn.reply(req, {"status": "nok", "message": "no chunk server available!"})
            return
        try:
            memories = self.getall_storage(conns)
        except (ConnectionError, queue.Empty):
            client_conn.reply(req, {"status": "nok", "message": "a chunk server didn't answer!"})
            return
        servers_number = min(len(memories), N_REPLICAS)
        assigned_servers = []
        for _ in range(chunk_number):
            chosen = utils.argsort(memories)[:servers_number]
            assigned_servers.append(chosen)
            for j in chosen:
                memories[j] += 1

        if max(memories) > MAX_N_CHUNK_SERVER:
            client_conn.reply(req, {"status": "nok", "message": f"{filename} couldn't be written: not enough space!"})
            return

        # proceed chunk allocation and remember where the chunks are as for replicas.
        chunks = []
        try:
            for chosen in assigned_servers:
                replicas = []
                for j in chosen:
                    response = conns[j].request({"action": "allocate"})
                    if response.get("status") != "ok":
                        raise MemoryError(f"the server {j} couldn't allocate enough memory!")
                    host, port = response["client_host"], response["client_port"]
                    replicas.append({"host":host, "port":port, "file_index":response["file_index"]})
                chunks.append(replicas)
        except (MemoryError, ConnectionError, queue.Empty) as e:
            client_conn.reply(req, {"status": "nok", "message": f"{filename} couldn't be written: {e}"})
            return

        with self.lut_lock:
            self.lut.setdefault(client_name, {})[filename] = {"chunk_handles": chunks}

        client_conn.reply(req, {"status": "ok", "chunks": chunks})
