import socket
import threading
import os

from mini_dfs.globals import *
import mini_dfs.utils as utils

import json
class Client():
    def __init__(self, name = "client", host = NAMESERVER_HOST, nameserver_port = None):
        self.name = name
        self.host = host
        self.nameserver_port = nameserver_port
        self.conn = None
        self.is_running = False

    def __str__(self):
        return f"[Client {self.name}, {self.host}, {self.nameserver_port}]"

    def start(self):        
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        if self.nameserver_port == None:
            print(f"{self} hasn't any bound port yet !")
        utils.connect_with_retry(sock, (self.host, self.nameserver_port))
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

    def send_read(self, filename, offset_begin=0, offset_end=0):
        req = {
            'action': 'read',
            'filename': filename,
            'clientname': self.name
        }
        response = self.conn.request(req)
        if response["status"] != "ok":
            print(response["payload"])
            return
        chunks_mds = response["payload"]

        if offset_end == -1:
            index_begin = offset_begin//CHUNK_SIZE
            chunks_mds = chunks_mds[index_begin:]
        elif offset_end >= 0 and (offset_begin < offset_end):
            index_begin = offset_begin//CHUNK_SIZE
            index_end   = (offset_end//CHUNK_SIZE)+1
            chunks_mds = chunks_mds[index_begin:index_end]

        chunks_data = []
        for chunk_mds in chunks_mds:
            for chunk_md in chunk_mds:
                host, port, file_index = chunk_md['host'], chunk_md['port'], chunk_md['file_index']
                try:
                    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as chunkserver_sock:
                        chunkserver_sock.settimeout(3)
                        chunkserver_sock.connect((host, port))
                        req = {
                            "action":"read",
                            "file_index":file_index
                        }
                        utils.send_data(chunkserver_sock, req)
                        response2 = json.loads(utils.recv_data(chunkserver_sock, bytes=False))
                        if response2["status"] != "ok":
                            print(response2["payload"])
                            continue
                        chunks_data.append(utils.recv_data(chunkserver_sock, bytes=True))
                        break ## exit the loop when succeeded to get the data from one chunk
                except ConnectionError as ex:
                    print(f"{self}: lost connection! : {ex}")
                    continue
        
        result = b''.join(chunks_data)
        chunk_difference = offset_end//CHUNK_SIZE - offset_begin//CHUNK_SIZE
        result = result[offset_begin%CHUNK_SIZE:chunk_difference*CHUNK_SIZE+offset_end%CHUNK_SIZE]
        print(result)


    def send_list(self):
        message = {
            "action": "list",
            "clientname": self.name
        }
        self.process_list_request(self.conn.request(message))
