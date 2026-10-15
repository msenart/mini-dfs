import socket
import threading
import os

from mini_dfs.globals import HOST, CHUNK_SIZE
import mini_dfs.utils as utils

import json
class Client():
    def __init__(self, name = "client", host = HOST, port = None):
        self.name = name
        self.host = host
        self.port = None
        self.conn = None
        self.is_running = False

    def __str__(self):
        return f"[Client {self.name}, {self.host}, {self.port}]"

    def start(self):        
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        if self.port == None:
            print(f"{self} hasn't any bound port yet !")
        sock.connect((self.host, self.port))
        self.conn = utils.QueueConn(sock)
        self.is_running = True
        threading.Thread(target=self.conn.listen, args=(self._listen, lambda: self.is_running), daemon=True).start()

    def stop(self):
        print(f"{self} is disconnecting...")
        self.is_running = False
        if self.conn:
            self.conn.close()

    def _listen(self, req : dict):
        """
        Handles the messages pushed by the name server (responses to request() are routed by the QueueConn).
        """
        if (req.get("action") == "message"):
            self.process_message_request(req)
        else:
            print(f"received unknown request: {json.dumps(req)}")

    def process_message_request(self, req):
        print(f"{self} has received: {req["payload"]}")

    def process_list_request(self, req):
        filenames = req["filenames"]
        if len(filenames) == 0:
            print(f"{self} has no file stored in the database.")
            return
        else:
            for file in filenames:
                print(f"{self}: {file}")
            return

    def send_message(self, msg):
        """
        Sends a message to the name server. request format : msg = <payload> 
        """
        try:
            message = {
                "action": "message",
                "payload": msg,
                "clientname": self.name
                }
            self.conn.send(message)
            print(f"{self} has sent the message !")
        except OSError as e:
            print(f"{self} couldn't send message ! : {e}")

    def send_write(self, path):
        """
        Sends a write request to the name server. request format : msg = <path>
        """
        ## Request allocation to name server
        header = {
            "action": "allocate",
            "clientname": self.name,
            "chunk_number" : (os.path.getsize(path)//CHUNK_SIZE) + 1,
            "filename": os.path.basename(path)
        }
        response = self.conn.request(header)
        if response.get("status") != "ok":
            print(f"{self}: {response.get('message')}")
            return
        tot_chunks_mds = response["chunks"]

        chunks = []
        with open(path, "rb") as file:
            while buf := file.read(CHUNK_SIZE):
                chunks.append(buf)
        for chunk, chunk_mds in zip(chunks, tot_chunks_mds):     # loop over all chunks
            for chunk_md in chunk_mds:                      # loop over each replica coordinate
                host, port, file_index = chunk_md["host"], chunk_md["port"], chunk_md["file_index"] # file_index refers to the allocated chunk in the chunkserver.
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as chunkserver_sock:
                    chunkserver_sock.connect((host, port))
                    req = {
                        "action":"write",
                        "file_index":file_index,
                    }
                    utils.send_data(chunkserver_sock, req)
                    utils.send_data(chunkserver_sock, chunk)
                    response = json.loads(utils.recv_data(chunkserver_sock, bytes=False))
                    if response["status"] != "ok":
                        raise BrokenPipeError(f"the server {host}:{port} couldn't write the chunk !")
        ## TODO: there is a performance problem : the socket creation is in the loop ! multiple socket creations...


    def send_list(self):
        message = {
            "action": "list",
            "clientname": self.name
        }
        self.process_list_request(self.conn.request(message))
