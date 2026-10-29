import argparse
import cmd
import atexit
import os

from mini_dfs.client import Client
from mini_dfs.name_server import NameServer
from mini_dfs.chunk_server import ChunkServer
from mini_dfs.globals import *

class CLI(cmd.Cmd):
    intro = 'Welcome to the Cmd.   Type help or ? to list commands.\n'
    prompt = '(mini-dfs)'

    def __init__(self):
        super().__init__()
        self.nameserver = None
        self.clients = []
        self.chunkservers = []

    def onecmd(self, line):
            try:
                return super().onecmd(line)
            except Exception as e:
                print(e)
                print(f"Error on the command '{line}'")
                return False

    def do_create_client(self, args):
        """
        Creates a client instance.
        Usage: create-client <client-name> 
        """
        if (len(args.split()) != 1):
            print("Usage: create-client <client-name>")
            return
        name = args.split()[0]
        client = Client(name)
        self.clients.append(client)
        print(f"{client} created.")

    def do_create_nameserver(self, args):
        """
        Creates a nameserver instance.
        Call the command twice overwrites the previous nameserver. 
        Usage: create-nameserver <nameserver-name>
        """
        if (len(args.split()) != 1):
            print("Usage: create-nameserver <nameserver-name>")
            return
        name = args.split()[0]
        self.nameserver = NameServer(name, client_port=CLIENT_PORT, server_port=CHUNK_SERVER_PORT)
        print(f"{self.nameserver} created.")

    def do_create_chunkserver(self, args):
        """
        Creates a chunkserver instance.
        Usage: create-chunkserver <chunkserver-name>
        """
        if (len(args.split()) != 1):
            print("Usage: create-chunkserver <chunkserver-name>")
            return
        name = args.split()[0]
        self.chunkservers.append(ChunkServer(name))
        print(f"{self.chunkservers[-1]} created.")

    def do_startall(self, args):
        """
        Start all entities.
        """
        # bind all ports from clients and chunkservers to name server port.
        for client in self.clients:
            client.nameserver_port = self.nameserver.client_port
        for chunkserver in self.chunkservers:
            chunkserver.nameserver_port = self.nameserver.server_port
        print("All clients and chunkservers have been bound to the nameserver !")
        self.nameserver.start()
        for client in self.clients:
            client.start()
        for chunkserver in self.chunkservers:
            chunkserver.start()
        print("All entities have started !")

    def do_exit(self, args):
        """
        Stops all socket connections for every entity.
        """
        self._exit()
        exit()

    def _exit(self):
        """
        Stops all socket connections for every entity.
        """
        for client in self.clients:
            client.stop()
        for chunkserver in self.chunkservers:
            chunkserver.stop()
        if self.nameserver:
            self.nameserver.stop()

    def do_message(self, args):
        """
        Send message from the client <name> to the nameserver.
        Usage: send <client-name> <request>
        """
        if (len(args.split()) < 2):
            print("Usage: send <client-name> <request>")
            return

        actor_name, msg = args.split(" ",1)
        if not any(c.name == actor_name for c in self.clients):
            print(f"client {actor_name} doesn't exist")
            return
        for actor in self.clients:
            if actor.name == actor_name:
                actor.send_message(msg)
                return

    def do_write(self, args):
        """
        Writes the <path-to-file> file into the database.
        Usage: write <client-name> <path-to-file>
        """
        if (len(args.split()) < 2):
            print("Usage: write <client-name> <path-to-file>")
            return

        actor_name, path = args.split(" ",1)
        for actor in self.clients:
            if actor.name == actor_name:
                actor.send_write(path)
                break

    def do_read(self, args):
        """
        Prints an existing file named <filename> from the database into the terminal.
        Usage: read <client-name> <filename> <offset-begin> <offset-end>
        <offset-begin> is in [0, +inf)
        <offset-end> is in [0, +inf). If =-1, prints from <offset-begin> to end of file.
        """
        if len(args.split()) != 4:
            print("Usage: read <client-name> <filename> <offset-begin> <offset-end>")
            return
            
        actor_name, path, offset_begin, offset_end = args.split()
        filename = os.path.basename(path)
        if not any(c.name == actor_name for c in self.clients):
            print(f"client name {actor_name} doesn't exist !")
            return
        for actor in self.clients:
            if actor.name == actor_name:
                actor.send_read(filename, int(offset_begin), int(offset_end))
                return
    
    def do_lsf(self, args):
        """
        Lists all files that a user has in the database.
        Usage: lsf <client-name>
        """
        client_name = args
        if len(args.split()) != 1:
            print("Usage: lsf <client-name>")
            return
        if not any(c.name == client_name for c in self.clients):
            print(f"client name {client_name} doesn't exist !")
            return
        for client in self.clients:
            if client.name == client_name:
                client.send_list()
                return

    def do_ls(self, args=None):
        """
        Lists all the entities that are in the simulation. Usage: ls
        """
        for chunkserver in self.chunkservers:
            print(chunkserver)
        for client in self.clients:
            print(client)
        print(self.nameserver)

    def do_macro(self, args=None):
        """
        Builds automatically a configuration for those who are lazy. Check the configuration is live using command ls.
        """
        self.do_create_chunkserver("ds1")
        self.do_create_chunkserver("ds2")
        self.do_create_chunkserver("ds3")
        self.do_create_chunkserver("ds4")
        self.do_create_client("alice")
        self.do_create_nameserver("ns1")
        self.do_startall(None)

if __name__ == "__main__":
    cli = CLI()
    atexit.register(cli._exit)
    cli.cmdloop()