from pathlib import Path

from mini_dfs.globals import CHUNK_SIZE, N_REPLICAS

from conftest import make_cli, wait_for


def bin_files(cli):
    """chunk server name -> {file name: content}"""
    out = {}
    for cs in cli.chunkservers:
        out[cs.name] = {f.name: f.read_bytes() for f in Path(cs.name).glob("*.bin")}
    return out


def all_chunks(cli):
    return [content for files in bin_files(cli).values() for content in files.values()]


def write_file(tmp_path, content, name="data.txt"):
    path = tmp_path / name
    path.write_bytes(content)
    return path


# ---------------------------------------------------------------- creation

def test_create_client(cli, capsys):
    cli.onecmd("create_client alice")
    assert [c.name for c in cli.clients] == ["alice"]
    assert "created." in capsys.readouterr().out


def test_create_nameserver(cli, capsys):
    cli.onecmd("create_nameserver ns")
    assert cli.nameserver.name == "ns"
    assert "created." in capsys.readouterr().out


def test_create_chunkserver(cli, capsys):
    cli.onecmd("create_chunkserver cs0")
    assert [c.name for c in cli.chunkservers] == ["cs0"]
    assert "created." in capsys.readouterr().out


def test_create_nameserver_twice_overwrites(cli):
    cli.onecmd("create_nameserver first")
    cli.onecmd("create_nameserver second")
    assert cli.nameserver.name == "second"


def test_create_commands_need_exactly_one_argument(cli, capsys):
    for cmd in ("create_client", "create_nameserver", "create_chunkserver"):
        cli.onecmd(cmd)
        cli.onecmd(f"{cmd} a b")
    assert capsys.readouterr().out.count("Not enough arguments") == 6
    assert cli.clients == [] and cli.chunkservers == [] and cli.nameserver is None


def test_errors_are_caught_by_onecmd(cli, capsys):
    cli.onecmd("startall")      # no name server yet
    assert "Error on the command 'startall'" in capsys.readouterr().out


# ---------------------------------------------------------------- startall / ls / macro

def test_startall(cli):
    make_cli(cli, n_chunkservers=2, clients=("alice", "bob"))
    assert cli.nameserver.is_running
    assert all(c.is_running and c.port == cli.nameserver.client_port for c in cli.clients)
    assert all(c.is_running and c.nameserver_port == cli.nameserver.server_port for c in cli.chunkservers)


def test_ls_lists_every_entity(running_cli, capsys):
    capsys.readouterr()
    running_cli.onecmd("ls")
    out = capsys.readouterr().out
    for entity in [*running_cli.chunkservers, *running_cli.clients, running_cli.nameserver]:
        assert str(entity) in out


def test_macro(cli):
    cli.onecmd("macro")
    assert len(cli.chunkservers) == 1 and len(cli.clients) == 1 and cli.nameserver is not None
    assert wait_for(lambda: len(cli.nameserver.chunk_servers_conns) == 1)


# ---------------------------------------------------------------- message

def test_message(running_cli, capsys):
    running_cli.onecmd("message alice hello world")
    assert wait_for(lambda: "Received from alice: hello world" in capsys.readouterr().out)


def test_message_unknown_client_is_a_noop(running_cli, capsys):
    capsys.readouterr()
    running_cli.onecmd("message nobody hello")
    assert "Error" not in capsys.readouterr().out


def test_message_without_text(running_cli, capsys):
    capsys.readouterr()
    running_cli.onecmd("message alice")
    assert "Not enough arguments" in capsys.readouterr().out


# ---------------------------------------------------------------- lsf / write

def test_lsf_empty(running_cli, capsys):
    capsys.readouterr()
    running_cli.onecmd("lsf alice")
    assert "no file stored" in capsys.readouterr().out


def test_write_then_lsf(running_cli, tmp_path, capsys):
    path = write_file(tmp_path, bytes(range(256)))
    running_cli.onecmd(f"write alice {path}")
    running_cli.onecmd("lsf alice")
    out = capsys.readouterr().out
    assert "Error" not in out
    assert "data.txt" in out


def test_write_stores_every_chunk_on_n_replicas(running_cli, tmp_path):
    content = bytes(i % 251 for i in range(CHUNK_SIZE * 3 + 5))        # 4 chunks
    expected = [content[i:i + CHUNK_SIZE] for i in range(0, len(content), CHUNK_SIZE)]
    running_cli.onecmd(f"write alice {write_file(tmp_path, content)}")

    stored = all_chunks(running_cli)
    assert len(stored) == len(expected) * min(N_REPLICAS, 3)
    for chunk in expected:
        assert stored.count(chunk) == min(N_REPLICAS, 3)


def test_write_balances_chunks_across_servers(running_cli, tmp_path):
    running_cli.onecmd(f"write alice {write_file(tmp_path, b'x' * (CHUNK_SIZE * 5))}")
    counts = {len(files) for files in bin_files(running_cli).values()}
    assert len(counts) == 1


def test_write_with_a_single_chunkserver(cli, tmp_path):
    make_cli(cli, n_chunkservers=1)
    cli.onecmd(f"write alice {write_file(tmp_path, b'y' * (CHUNK_SIZE * 2))}")
    assert len(all_chunks(cli)) == 3         # 2 written chunks + 1 allocated but empty (the client asks for size/CHUNK_SIZE + 1)


def test_write_same_file_twice(running_cli, tmp_path, capsys):
    path = write_file(tmp_path, b"z" * (CHUNK_SIZE + 1))
    running_cli.onecmd(f"write alice {path}")
    before = bin_files(running_cli)
    capsys.readouterr()
    running_cli.onecmd(f"write alice {path}")
    assert "already exists" in capsys.readouterr().out
    assert bin_files(running_cli) == before


def test_lsf_is_per_client(cli, tmp_path, capsys):
    make_cli(cli, clients=("alice", "bob"))
    cli.onecmd(f"write alice {write_file(tmp_path, b'a' * 10, 'alice.txt')}")
    capsys.readouterr()
    cli.onecmd("lsf bob")
    out = capsys.readouterr().out
    assert "no file stored" in out and "alice.txt" not in out
    cli.onecmd("lsf alice")
    assert "alice.txt" in capsys.readouterr().out


def test_write_unknown_client_is_a_noop(running_cli, tmp_path):
    running_cli.onecmd(f"write nobody {write_file(tmp_path, b'a')}")
    assert all_chunks(running_cli) == []


def test_write_without_path(running_cli, capsys):
    capsys.readouterr()
    running_cli.onecmd("write alice")
    assert "Not enough arguments" in capsys.readouterr().out


def test_lsf_unknown_client_is_a_noop(running_cli, capsys):
    capsys.readouterr()
    running_cli.onecmd("lsf nobody")
    assert capsys.readouterr().out == ""
