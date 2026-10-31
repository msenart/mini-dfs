import threading
from enum import StrEnum
import os

HOST = "localhost"
# Overridable through the environment so that each component can run in its own container.
NAMESERVER_HOST = os.environ.get("NAMESERVER_HOST", HOST)   # where clients / chunk servers reach the name server
BIND_HOST = os.environ.get("BIND_HOST", HOST)               # interface the name server listens on
ADVERTISE_HOST = os.environ.get("ADVERTISE_HOST", None)     # address a chunk server gives to clients
CHUNK_CLIENT_PORT = int(os.environ.get("CHUNK_CLIENT_PORT", 0))  # 0 = random port
CLIENT_PORT = int(os.environ.get("CLIENT_PORT", 8080))
CHUNK_SERVER_PORT = int(os.environ.get("CHUNK_SERVER_PORT", 8081))

# Hyperparameters
CHUNK_SIZE = 2*1024*1024    # Chunk size in bytes.
MAX_N_CHUNK_SERVER = 10    # The maximum memory allocated for each server, in term of memory chunks. (Memory = CHUNK_SIZE * MAX_N_CHUNK_SERVER)
N_REPLICAS = 3              # How many times there should be a chunk replica. (each replica is stored in a different database)