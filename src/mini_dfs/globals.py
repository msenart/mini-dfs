import threading
from enum import StrEnum

# CHUNK_SIZE = 2*1024*1024 # chunk size in bytes
CHUNK_SIZE = 32
HOST = "localhost"
CLIENT_PORT = 8080
CHUNK_SERVER_PORT = 8081
MAX_N_CHUNK_SERVER = 100
N_REPLICAS = 3