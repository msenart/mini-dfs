import threading
from enum import StrEnum

CHUNK_SIZE = 2*1024*1024 # chunk size in bytes
HOST = "localhost"
server_ready = threading.Event()
ALL_COMMANDS = ["message", "read", "write"]