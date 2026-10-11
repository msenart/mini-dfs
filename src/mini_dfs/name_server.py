import socket
import threading
from mini_dfs.globals import server_ready, HOST, CHUNK_SIZE
import json
import hashlib

class NameServer():
    def __init__(self, name = "name-server", host=HOST, port=0):
        self.name = name
        self.host = host
        self.port = port
        self.sock = None
        self.is_running = False
        self.lut = dict()
        self.chunk_servers = []


    def __str__(self):
        return f"[NameServer {self.name}, {self.host}, {self.port}]"

    def start(self):        
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((self.host, self.port))
        self.sock.listen()
        self.is_running = True

        threading.Thread(target=self._accept_clients, daemon=True).start()

    def _accept_clients(self):
        server_ready.set()
        while self.is_running:
            try:
                client_conn, client_addr = self.sock.accept()
                threading.Thread(target=self._handle_client, args=(client_conn,client_addr), daemon=True).start()
            except OSError:
                break

    def _handle_client(self, client_conn, client_addr):
        with client_conn:
            while self.is_running:
                try:
                    data = client_conn.recv(1024)
                    if not data:
                        break
                    req = json.loads(data)
                    match req["action"]:
                        case "message": 
                            print(f"{self} Received from {req["clientname"]}: {req["payload"]}")
                        case "write":
                            self.process_write_request(req,client_conn)
                        case "list":
                            self.process_list_request(req,client_conn)
                except ConnectionResetError:
                    break

    def process_list_request(self, req, client_conn):
        client_name = req["clientname"]
        filenames = []
        if client_name in self.lut:
            filenames = list(self.lut[client_name].keys())
        client_conn.sendall(json.dumps(filenames).encode('utf-8'))
    
    def process_write_request(self,req,client_conn):
        """
        """
        file_size, client_name, filename = req["size"], req["clientname"], req["filename"]
        missing_bytes = file_size
        data = bytearray()
        while self.is_running and missing_bytes > 0 :
            try:
                received_packet = client_conn.recv(min(missing_bytes, 1024))
                missing_bytes -= len(received_packet)
                if not received_packet:
                    break
                data.extend(received_packet)
            except ConnectionResetError:
                break
        print(f"{self} has received a file of size ", len(data))

        ## Separating the data into chunks
        data_chunks = []
        for i in range((len(data)//CHUNK_SIZE)+1):
            if i == len(data)//CHUNK_SIZE:
                data_chunks.append(data[i*CHUNK_SIZE:])
            data_chunks.append(data[i*CHUNK_SIZE:(i+1)*CHUNK_SIZE])

        ## Send each chunk and wait for the response of the chunk servers (which offset)
        for chunk in data_chunks:
            ## TODO Send data to chunk servers
            res = {
                "chunk_server"  : 1,
                "offset"        : 0
            }

            if client_name not in self.lut:
                self.lut[client_name] = {filename : []}
            self.lut[client_name][filename].append({
                "chunk_server" : [],
                "offset" : [],
                "md5" : hashlib.md5(chunk).hexdigest()
            })

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
