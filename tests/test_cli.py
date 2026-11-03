from pathlib import Path

from mini_dfs.globals import CHUNK_SIZE

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


def test_errors_are_caught_by_onecmd(cli, capsys):
    cli.onecmd("startall")      # no name server yet
    assert "Error on the command 'startall'" in capsys.readouterr().out


# ---------------------------------------------------------------- startall / ls / macro

def test_ls_lists_every_entity(running_cli, capsys):
    capsys.readouterr()
    running_cli.onecmd("ls")
    out = capsys.readouterr().out
    for entity in [*running_cli.chunkservers, *running_cli.clients, running_cli.nameserver]:
        assert str(entity) in out


# ---------------------------------------------------------------- message

def test_message(running_cli, capsys):
    running_cli.onecmd("message alice hello world")
    assert wait_for(lambda: "Received from alice: hello world" in capsys.readouterr().out)


def test_message_unknown_client_is_a_noop(running_cli, capsys):
    capsys.readouterr()
    running_cli.onecmd("message nobody hello")
    assert "Error" not in capsys.readouterr().out


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


def test_write_balances_chunks_across_servers(running_cli, tmp_path):
    running_cli.onecmd(f"write alice {write_file(tmp_path, b'x' * (CHUNK_SIZE * 5))}")
    counts = {len(files) for files in bin_files(running_cli).values()}
    assert len(counts) == 1


def test_write_same_filename_twice_is_allowed(running_cli, tmp_path, capsys):
    path = write_file(tmp_path, b"z" * (CHUNK_SIZE + 1))
    running_cli.onecmd(f"write alice {path}")
    before = all_chunks(running_cli)
    capsys.readouterr()
    running_cli.onecmd(f"write alice {path}")
    out = capsys.readouterr().out
    assert "already exists" not in out
    assert "written successfully" in out
    assert len(all_chunks(running_cli)) == 2 * len(before)   # each write gets its own file ID, both copies kept


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


# ---------------------------------------------------------------- ls / write / read: normal + edge cases

def test_ls_with_nothing_created(cli, capsys):
    capsys.readouterr()
    cli.onecmd("ls")
    assert "Error" not in capsys.readouterr().out


def test_write_empty_file(running_cli, tmp_path, capsys):
    capsys.readouterr()
    running_cli.onecmd(f"write alice {write_file(tmp_path, b'')}")
    assert "Error" not in capsys.readouterr().out
    running_cli.onecmd("lsf alice")
    assert "data.txt" in capsys.readouterr().out


def test_read_full_file_round_trip(running_cli, tmp_path):
    content = bytes(i % 251 for i in range(CHUNK_SIZE * 2 + 37))   # spans 3 chunks
    running_cli.onecmd(f"write alice {write_file(tmp_path, content)}")
    running_cli.onecmd("read alice data.txt 0 -1")
    assert (Path("storage") / "alice" / "data.txt").read_bytes() == content


def test_read_partial_range_across_chunks(running_cli, tmp_path):
    content = bytes(i % 251 for i in range(CHUNK_SIZE + 500))      # one full chunk, one partial
    running_cli.onecmd(f"write alice {write_file(tmp_path, content)}")

    begin, end = CHUNK_SIZE - 10, CHUNK_SIZE + 10                  # spans the chunk boundary
    running_cli.onecmd(f"read alice data.txt {begin} {end}")
    assert (Path("storage") / "alice" / "data.txt").read_bytes() == content[begin:end]


def test_read_unknown_client_is_a_noop(running_cli, capsys):
    capsys.readouterr()
    running_cli.onecmd("read nobody data.txt 0 -1")
    assert "doesn't exist" in capsys.readouterr().out
    assert not (Path("storage") / "nobody").exists()


def test_read_file_for_client_with_no_writes_is_a_noop(running_cli, capsys):
    capsys.readouterr()
    running_cli.onecmd("read alice never_written.txt 0 -1")
    assert "no such filename" in capsys.readouterr().out
