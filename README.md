# mini-dfs

# Overview

This school project's purpose is to simulate a mini distributed file system (mini-dfs). It is constituted of three main classes:
- ``ChunkServer``, which purpose is to store clients files under the form of byte chunks.
- a master (named ``NameServer`` in the code), which deals with all the metadata and organizes the traffic.
- ``Client``, which are the database users.

The project is **dependence-free**, except for testing which is done with ``pytest``. It handles its connections with TCP protocols only and the famous ``socket`` module. To handle listening and sending request packets on the same socket simultaneously (possible on two different threads), a specific class named ``QueueConn`` which wraps the ``socket`` module was added, taking advantage of the ``thread.Lock()`` system.

# Launch the project

Hyperparameters in ``globals.py`` can be changed before launching the project.

There is two ways to launch the project:
- The first is with ``cli.py``.
- The second is with Docker. Make sure you have it installed on your OS.

## ``cli.py``

The cli was build using the built-in ``cmd`` module from python.

``` cmd
python src/mini_dfs/cli.py
help
macro
ls
write shrek pyproject.toml
lsf shrek
read shrek pyproject.toml 0 -1
read shrek pyproject.toml 1 11
```

## Docker

Every component (name server, 4 chunk servers, client) runs in its own container.

```
mkdir -p files            # put files to upload here
docker compose up -d --build
docker compose run --rm client
(mini-dfs) write /files/hello.txt
(mini-dfs) lsf
(mini-dfs) read hello.txt 0 10
```

Configuration is passed through environment variables (see `globals.py`): `NAMESERVER_HOST`, `BIND_HOST`, `ADVERTISE_HOST`, `CHUNK_CLIENT_PORT`, `CLIENT_PORT`, `CHUNK_SERVER_PORT`.
The original single-process thread simulation is still available with `python src/mini_dfs/cli.py`.
