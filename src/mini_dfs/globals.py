import threading
from enum import StrEnum

# CHUNK_SIZE = 2*1024*1024 # chunk size in bytes
CHUNK_SIZE = 16
import os

HOST = "localhost"
# Overridable through the environment so that each component can run in its own container.
NAMESERVER_HOST = os.environ.get("NAMESERVER_HOST", HOST)   # where clients / chunk servers reach the name server
BIND_HOST = os.environ.get("BIND_HOST", HOST)               # interface the name server listens on
ADVERTISE_HOST = os.environ.get("ADVERTISE_HOST", None)     # address a chunk server gives to clients
CHUNK_CLIENT_PORT = int(os.environ.get("CHUNK_CLIENT_PORT", 0))  # 0 = random port
CLIENT_PORT = int(os.environ.get("CLIENT_PORT", 8080))
CHUNK_SERVER_PORT = int(os.environ.get("CHUNK_SERVER_PORT", 8081))
MAX_N_CHUNK_SERVER = 100
N_REPLICAS = 3