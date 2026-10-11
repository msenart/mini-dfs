import argparse
import cmd
import atexit

from mini_dfs.client import Client
from mini_dfs.name_server import NameServer

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
        Creates a client instance. Usage create-client <client-name>. 
        """
        if (len(args.split()) != 1):
            print("Not enough arguments to unpack.")
            return
        name = args.split()[0]
        client = Client(name)
        self.clients.append(client)
        print(f"{client} created.")

    def do_create_nameserver(self, args):
        """
        Creates a nameserver instance. Call the command twice overwrites the previous nameserver. Usage create-nameserver <nameserver-name> <nameserver-host> <nameserver-port>.
        """
        if (len(args.split()) != 1):
            print("Not enough arguments to unpack.")
            return
        name = args.split()[0]
        self.nameserver = NameServer(name, port=8081)
        print(f"{self.nameserver} created.")
        
    def do_startall(self, args):
        """
        Start all entities.
        """
        # bind all ports from clients to name server port.
        for client in self.clients:
            client.port = self.nameserver.port
        print("All clients have been bound to the nameserver !")
        self.nameserver.start()
        for client in self.clients:
            client.start()
        print("All entities have started !")

    def _shutdownall(self):
        """
        Stops all socket connections for every entity.
        """
        for client in self.clients:
            client.stop()
        self.nameserver.stop()

    def do_message(self, args):
        """
        Send message from the client <name> to the nameserver. Usage: send <client-name> <request>
        """
        if (len(args.split()) < 2):
            print("do_client_send: Not enough arguments to unpack.")

        actor_name, msg = args.split(" ",1)
        for actor in self.clients:
            if actor.name == actor_name:
                actor.send_message(msg)
                break

    def do_write(self, args):
        """
        Send a write request from the client <name> to the nameserver. Usage: write <client-name> <path-to-file>
        """
        if (len(args.split()) < 2):
            print("do_client_send: Not enough arguments to unpack.")

        actor_name, path = args.split(" ",1)
        for actor in self.clients:
            if actor.name == actor_name:
                actor.send_write(path)
                break

    def do_lsf(self, args):
        """
        Lists all files that a user has in the database. Usage: lsf <client-name>
        """
        client_name = args
        for client in self.clients:
            if client.name == client_name:
                client.send_list()
                break

    def do_ls(self, args=None):
        """
        Lists all the entities that are in the simulation. Usage: ls
        """
        for client in self.clients:
            print(client)
        print(self.nameserver)

    def do_macro(self, args=None):
        self.do_create_client("shrek")
        self.do_create_nameserver("caca")
        self.do_startall(None)

if __name__ == "__main__":
    cli = CLI()
    atexit.register(cli._shutdownall)
    cli.cmdloop()