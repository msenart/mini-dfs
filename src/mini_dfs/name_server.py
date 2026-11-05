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
        self.files = dict()                                 # file_id -> {clientname, directory, filename, chunk_handles}
        self.dirs = dict()                                  # clientname -> set of existing directories (always contains "/")
        self.files_lock:threading.Lock=threading.Lock()     # protects both self.files and self.dirs
        self._next_file_id = itertools.count(1)
        self.chunk_servers_conns = []
        self.chunk_servers_conns_lock:threading.Lock=threading.Lock()
        self.is_running = False

    def __str__(self):
        return f"[NameServer {self.name}]"

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
            case "mkdir":
                self.process_mkdir_request(req, conn)
            case "rmdir":
                self.process_rmdir_request(req, conn)
            case "lsdir":
                self.process_lsdir_request(req, conn)
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

    def _client_dirs(self, client_name):
        """Directory set of a client (created on first use). Must be called with files_lock held."""
        return self.dirs.setdefault(client_name, {"/"})

    def process_list_request(self, req, client_conn: utils.QueueConn):
        client_name = req["clientname"]
        with self.files_lock:
            entries = [{"file_id": fid, "directory": rec["directory"], "filename": rec["filename"]}
                       for fid, rec in self.files.items() if rec["clientname"] == client_name]
        client_conn.reply(req, {"action":"list", "files":entries})

    def process_mkdir_request(self, req, conn: utils.QueueConn):
        """Creates a directory and all its missing parents (like mkdir -p). Succeeds if it already exists."""
        try:
            path = utils.normalize_path(req["path"])
        except ValueError as e:
            conn.reply(req, {"status":"nok", "message":f"invalid path: {e}"})
            return
        with self.files_lock:
            dirs = self._client_dirs(req["clientname"])
            parts = path.split("/")[1:] if path != "/" else []
            for i in range(1, len(parts) + 1):
                dirs.add("/" + "/".join(parts[:i]))
        conn.reply(req, {"status":"ok", "message":f"directory {path} is ready."})

    def process_rmdir_request(self, req, conn: utils.QueueConn):
        """Removes an empty directory (no file, no sub-directory). The root can't be removed."""
        client_name = req["clientname"]
        try:
            path = utils.normalize_path(req["path"])
        except ValueError as e:
            conn.reply(req, {"status":"nok", "message":f"invalid path: {e}"})
            return
        with self.files_lock:
            dirs = self._client_dirs(client_name)
            if path == "/":
                msg = "the root directory can't be removed."
            elif path not in dirs:
                msg = f"directory {path} doesn't exist."
            elif any(d.startswith(path + "/") for d in dirs) or \
                 any(r["clientname"] == client_name and r["directory"] == path for r in self.files.values()):
                msg = f"directory {path} is not empty."
            else:
                dirs.discard(path)
                conn.reply(req, {"status":"ok", "message":f"directory {path} removed."})
                return
        conn.reply(req, {"status":"nok", "message":msg})

    def process_lsdir_request(self, req, conn: utils.QueueConn):
        """Lists the content of ONE directory: its direct sub-directories and its files."""
        client_name = req["clientname"]
        try:
            path = utils.normalize_path(req.get("path", "/"))
        except ValueError as e:
            conn.reply(req, {"status":"nok", "message":f"invalid path: {e}"})
            return
        with self.files_lock:
            dirs = self._client_dirs(client_name)
            if path not in dirs:
                conn.reply(req, {"status":"nok", "message":f"directory {path} doesn't exist."})
                return
            prefix = "/" if path == "/" else path + "/"
            subdirs = sorted(d[len(prefix):] for d in dirs
                             if d != path and d.startswith(prefix) and "/" not in d[len(prefix):])
            files = [{"file_id": fid, "filename": r["filename"]}
                     for fid, r in self.files.items() if r["clientname"] == client_name and r["directory"] == path]
        conn.reply(req, {"status":"ok", "path":path, "dirs":subdirs, "files":files})

    def process_read_request(self, req, conn: utils.QueueConn):
        clientname, file_id = req['clientname'], req.get('file_id')
        if file_id is not None:
            with self.files_lock:
                match = self.files.get(file_id)
            if match is None or match["clientname"] != clientname:
                conn.reply(req, {"status":"nok", "payload":f"no file with id {file_id} found for this client !"})
                return
        else:
            filename = req['filename']
            try:
                directory = utils.normalize_path(req.get('directory', "/"))
            except ValueError as e:
                conn.reply(req, {"status":"nok", "payload":f"invalid path: {e}"})
                return
            match = None
            with self.files_lock:
                for rec in self.files.values():     # dicts preserve insertion order: last match is the most recent write
                    if rec["clientname"] == clientname and rec["directory"] == directory and rec["filename"] == filename:
                        match = rec
            if match is None:
                conn.reply(req, {"status":"nok", "payload":"no such filename found in the database !"})
                return
        conn.reply(req, {"status":"ok", "payload":{"filename":match["filename"], "chunk_handles":match["chunk_handles"]}})

    def process_allocate_request(self, req, client_conn: utils.QueueConn):
        client_name, chunk_number, filename = req["clientname"], req["chunk_number"], req["filename"]
        print(f"{self} received an allocation request of {chunk_number} chunks")

        # the target directory must exist (checked first, so nothing is allocated on error)
        try:
            directory = utils.normalize_path(req.get("directory", "/"))
        except ValueError as e:
            client_conn.reply(req, {"status": "nok", "message": f"invalid directory: {e}"})
            return
        with self.files_lock:
            directory_exists = directory in self._client_dirs(client_name)
        if not directory_exists:
            client_conn.reply(req, {"status": "nok", "message": f"directory {directory} doesn't exist: create it with mkdir first!"})
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

        with self.files_lock:
            if directory not in self._client_dirs(client_name):     # removed by a concurrent rmdir
                client_conn.reply(req, {"status": "nok", "message": f"directory {directory} doesn't exist anymore!"})
                return
            file_id = next(self._next_file_id)
            self.files[file_id] = {"clientname": client_name, "directory": directory, "filename": filename, "chunk_handles": chunks}

        client_conn.reply(req, {"status": "ok", "file_id": file_id, "chunks": chunks})
