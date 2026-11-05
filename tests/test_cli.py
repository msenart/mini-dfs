import re
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


def test_read_by_id_disambiguates_same_filename(running_cli, tmp_path, capsys):
    first, second = b"a" * 10, b"b" * 10
    capsys.readouterr()
    running_cli.onecmd(f"write alice {write_file(tmp_path, first)}")
    first_id = int(re.search(r"file_id=(\d+)", capsys.readouterr().out).group(1))
    running_cli.onecmd(f"write alice {write_file(tmp_path, second)}")
    second_id = int(re.search(r"file_id=(\d+)", capsys.readouterr().out).group(1))

    running_cli.onecmd("read alice data.txt 0 -1")                 # plain filename -> most recent write
    assert (Path("storage") / "alice" / "data.txt").read_bytes() == second

    running_cli.onecmd(f"read alice {first_id} 0 -1")              # by id -> the older copy, otherwise unreachable
    assert (Path("storage") / "alice" / "data.txt").read_bytes() == first

    running_cli.onecmd(f"read alice {second_id} 0 -1")             # by id -> the newer copy still works too
    assert (Path("storage") / "alice" / "data.txt").read_bytes() == second


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


# ---------------------------------------------------------------- directories

def out_of(cli, capsys, command):
    capsys.readouterr()
    cli.onecmd(command)
    return capsys.readouterr().out


def test_mkdir_creates_parents_and_is_idempotent(running_cli, capsys):
    running_cli.onecmd("mkdir alice /a/b/c")
    running_cli.onecmd("mkdir alice /a/b/c")
    assert "[dir]  b/" in out_of(running_cli, capsys, "lsdir alice /a")
    assert "[dir]  c/" in out_of(running_cli, capsys, "lsdir alice /a/b")
    assert "[dir]  a/" in out_of(running_cli, capsys, "lsdir alice")


def test_invalid_paths_are_rejected(running_cli, capsys):
    assert "invalid path" in out_of(running_cli, capsys, "mkdir alice /a/../..")
    assert "doesn't exist" in out_of(running_cli, capsys, "lsdir alice /nope")


def test_write_into_nested_directory_and_read_by_path(running_cli, tmp_path, capsys):
    content = bytes(range(200))
    running_cli.onecmd("mkdir alice /docs/2026")
    out = out_of(running_cli, capsys, f"write alice {write_file(tmp_path, content)} /docs/2026")
    assert "written successfully" in out and "/docs/2026" in out
    assert "id=" in out_of(running_cli, capsys, "lsdir alice /docs/2026")
    assert "/docs/2026/data.txt" in out_of(running_cli, capsys, "lsf alice")

    running_cli.onecmd("read alice /docs/2026/data.txt 0 -1")
    assert (Path("storage") / "alice" / "data.txt").read_bytes() == content


def test_same_filename_in_two_directories_does_not_collide(running_cli, tmp_path):
    running_cli.onecmd("mkdir alice /x")
    running_cli.onecmd("mkdir alice /y")
    running_cli.onecmd(f"write alice {write_file(tmp_path, b'in x')} /x")
    running_cli.onecmd(f"write alice {write_file(tmp_path, b'in y')} /y")
    running_cli.onecmd(f"write alice {write_file(tmp_path, b'in root')}")

    for path, expected in (("/x/data.txt", b"in x"), ("/y/data.txt", b"in y"), ("data.txt", b"in root")):
        running_cli.onecmd(f"read alice {path} 0 -1")
        assert (Path("storage") / "alice" / "data.txt").read_bytes() == expected


def test_same_name_twice_in_one_directory_latest_wins_older_by_id(running_cli, tmp_path, capsys):
    running_cli.onecmd("mkdir alice /d")
    out_of(running_cli, capsys, f"write alice {write_file(tmp_path, b'old')} /d")
    out = out_of(running_cli, capsys, f"write alice {write_file(tmp_path, b'new')} /d")
    running_cli.onecmd("read alice /d/data.txt 0 -1")
    assert (Path("storage") / "alice" / "data.txt").read_bytes() == b"new"
    running_cli.onecmd("read alice 1 0 -1")
    assert (Path("storage") / "alice" / "data.txt").read_bytes() == b"old"


def test_write_into_missing_directory_fails_and_stores_nothing(running_cli, tmp_path, capsys):
    out = out_of(running_cli, capsys, f"write alice {write_file(tmp_path, b'x')} /missing")
    assert "doesn't exist" in out
    assert "no file stored" in out_of(running_cli, capsys, "lsf alice")
    assert all(not files for files in bin_files(running_cli).values())


def test_read_with_wrong_directory_fails(running_cli, tmp_path, capsys):
    running_cli.onecmd("mkdir alice /x")
    running_cli.onecmd(f"write alice {write_file(tmp_path, b'x')} /x")
    assert "no such filename" in out_of(running_cli, capsys, "read alice /data.txt 0 -1")


def test_rmdir_rules(running_cli, tmp_path, capsys):
    running_cli.onecmd("mkdir alice /a/b")
    assert "not empty" in out_of(running_cli, capsys, "rmdir alice /a")           # has a sub-directory
    running_cli.onecmd(f"write alice {write_file(tmp_path, b'x')} /a/b")
    assert "not empty" in out_of(running_cli, capsys, "rmdir alice /a/b")         # has a file
    assert "root" in out_of(running_cli, capsys, "rmdir alice /")
    assert "doesn't exist" in out_of(running_cli, capsys, "rmdir alice /zzz")
    running_cli.onecmd("mkdir alice /empty")
    assert "removed" in out_of(running_cli, capsys, "rmdir alice /empty")
    assert "doesn't exist" in out_of(running_cli, capsys, "lsdir alice /empty")


def test_directories_are_private_to_each_client(cli, capsys):
    make_cli(cli, clients=("alice", "bob"))
    cli.onecmd("mkdir alice /secret")
    assert "doesn't exist" in out_of(cli, capsys, "lsdir bob /secret")


def test_read_to_end_keeps_last_byte_on_chunk_multiple(running_cli, tmp_path):
    content = bytes(i % 251 for i in range(CHUNK_SIZE))
    running_cli.onecmd(f"write alice {write_file(tmp_path, content)}")
    running_cli.onecmd("read alice data.txt 0 -1")
    assert (Path("storage") / "alice" / "data.txt").read_bytes() == content
