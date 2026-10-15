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
        self.sock = None
        self.is_running = False

    def __str__(self):
        return f"[Client {self.name}, {self.host}, {self.port}]"

    def start(self):        
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        if self.port == None:
            print(f"{self} hasn't any bound port yet !")
        self.sock.connect((self.host, self.port))
        self.is_running = True

    def stop(self):
        print(f"{self} is disconnecting...")
        self.is_running = False
        if self.sock:
            try:
                self.sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.sock.close()

    def _listen(self, req : dict):
        """
        This is not really a listen function since there is no thread related to it.
        """
        if (req["action"] == "message"):
            self.process_message_request(req)
        elif (req["action"] == "list"):
            self.process_list_request(req)
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
            utils.send_data(self.sock, message)
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
        utils.send_data(self.sock, header)
        response = utils.recv_data(self.sock, bytes=False)
        tot_chunks_mds = json.loads(response)

        chunks = []
        with open(path, "rb") as file:
            while buf := file.read(CHUNK_SIZE):
                chunks.append(buf)
        for chunk, chunk_mds in chunks, tot_chunks_mds:     # loop over all chunks
            for chunk_md in chunk_mds:                      # loop over each replica coordinate
                host, port, file_index = chunk_md["host"], chunk_md["port"], chunk_md["file_index"] # file_index refers to the allocated chunk in the chunkserver.
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as chunkserver_sock:
                    chunkserver_sock.connect((host, port))
                    req = {
                        "action":"write",
                        "file_index":file_index,
                    }
                    utils.send_data(chunkserver_sock, req)
                    utils.send_data(chunk)
                    response = json.loads(utils.recv_data(chunkserver_sock, bytes=False))
                    if response["status"] != "ok":
                        raise BrokenPipeError(f"the server {host}:{port} couldn't write the chunk !")
        ## TODO: there is a performance problem : the socket creation is in the loop ! multiple socket creations...


    def send_list(self):
        message = {
            "action": "list",
            "clientname": self.name
        }
        # Send once
        utils.send_data(self.sock,message)
        data = utils.recv_data(self.sock, bytes=False)
        self._listen(json.loads(data))
