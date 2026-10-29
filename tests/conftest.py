import time

import pytest

from mini_dfs.__main__ import CLI


def wait_for(predicate, timeout=3.0):
    """Polls predicate until it is true (registrations and pushed messages are asynchronous)."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.02)
    return predicate()


@pytest.fixture
def cli(tmp_path, monkeypatch):
    # chunk servers create a directory named after themselves in the CWD
    monkeypatch.chdir(tmp_path)
    cli = CLI()
    yield cli
    for entity in [*cli.clients, *cli.chunkservers, cli.nameserver]:
        if entity is not None:
            entity.stop()


def make_cli(cli, n_chunkservers=3, clients=("alice",)):
    cli.onecmd("create_nameserver ns")
    for i in range(n_chunkservers):
        cli.onecmd(f"create_chunkserver cs{i}")
    for name in clients:
        cli.onecmd(f"create_client {name}")
    cli.onecmd("startall")
    assert wait_for(lambda: len(cli.nameserver.chunk_servers_conns) == n_chunkservers)
    return cli


@pytest.fixture
def running_cli(cli):
    return make_cli(cli)
