import argparse
import cmd
import os
import signal
import threading

from mini_dfs.client import Client
from mini_dfs.name_server import NameServer
from mini_dfs.chunk_server import ChunkServer
from mini_dfs.globals import *


class ClientShell(cmd.Cmd):
    intro = 'Welcome to mini-dfs. Type help or ? to list commands.\n'
    prompt = '(mini-dfs) '

    def __init__(self, client: Client):
        super().__init__()
        self.client = client

    def onecmd(self, line):
        try:
            return super().onecmd(line)
        except Exception as e:
            print(e)
            print(f"Error on the command '{line}'")
            return False

    def do_message(self, args):
        """Sends a message to the nameserver. Usage: message <text>"""
        self.client.send_message(args)

    def do_write(self, args):
        """Writes a file into the database. Usage: write <path-to-file>"""
        self.client.send_write(args.strip())

    def do_read(self, args):
        """Reads a file from the database. Usage: read <filename> <offset-begin> <offset-end>"""
        if len(args.split()) != 3:
            print("Usage: read <filename> <offset-begin> <offset-end>")
            return
        path, begin, end = args.split()
        self.client.send_read(os.path.basename(path), int(begin), int(end))

    def do_lsf(self, args):
        """Lists the files stored by this client. Usage: lsf"""
        self.client.send_list()

    def do_exit(self, args):
        """Quits the shell."""
        return True

    do_EOF = do_exit


def wait_for_sigterm():
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    stop.wait()


def main():
    parser = argparse.ArgumentParser(prog="mini-dfs", description="Runs one mini-dfs component.")
    sub = parser.add_subparsers(dest="role", required=True)
    sub.add_parser("nameserver")
    p = sub.add_parser("chunkserver")
    p.add_argument("--name", required=True)
    p = sub.add_parser("client")
    p.add_argument("--name", required=True)
    args = parser.parse_args()

    if args.role == "nameserver":
        entity = NameServer("name-server", client_port=CLIENT_PORT, server_port=CHUNK_SERVER_PORT)
        entity.start()
        print(f"{entity} is listening (chunk servers on {entity.server_port})", flush=True)
        wait_for_sigterm()
    elif args.role == "chunkserver":
        entity = ChunkServer(args.name, port=CHUNK_SERVER_PORT)
        entity.start()
        print(f"{entity} is running, advertising {entity.advertise_host}:{entity.client_sock.getsockname()[1]}", flush=True)
        wait_for_sigterm()
    else:
        entity = Client(args.name, port=CLIENT_PORT)
        entity.start()
        try:
            ClientShell(entity).cmdloop()
        finally:
            entity.stop()
        return
    entity.stop()


if __name__ == "__main__":
    main()
