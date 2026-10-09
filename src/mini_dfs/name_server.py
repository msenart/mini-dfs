import socket
import threading
from mini_dfs.globals import server_ready, HOST
import json
class NameServer():
    def __init__(self, name = "name-server", host=HOST, port=0):
        self.name = name
        self.host = host
        self.port = port
        self.sock = None
        self.is_running = False
        self.lut = dict()

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
                    print(f"Received from {client_addr} an {req["action"]} request")
                    match req["action"]:
                        case "message": 
                            print(f"{self} Received from {client_addr}: {req["payload"]}")
                        case "write":
                            self.process_write_request(req["size"],client_conn)
                except ConnectionResetError:
                    break

    def process_write_request(self,file_size,client_conn):
        """
        """
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
