// ---------- 2. Product presentation ----------
= Product Presentation and Demonstration

This school project's purpose is to simulate a mini distributed file system (mini-dfs). It is constituted of three main classes:
- ``ChunkServer``, whose purpose is to store clients' files under the form of byte chunks.
- a master (named ``NameServer`` in the code), which deals with all the metadata and organizes the traffic.
- ``Client``, which are the database users.

The project is managed through the module manager *uv*. The project is *dependency-free* (outside of ``pytest`` for testing). It handles its connections with TCP protocols only and the built-in ``socket`` module.

Hyperparameters in ``globals.py`` can be changed before launching the project — most notably ``CHUNK_SIZE`` (2 MiB by default) and ``N_REPLICAS`` (3 by default). Apart from that, there is NO data leak between the different instances.

The CLI was built using the built-in ``cmd`` module from Python.

Essential commands to use the CLI:
```sh
python -m mini_dfs                  # Start module
help                                # available commands
macro                               # preset architecture (4 chunkservers, 1 nameserver, 1 client)
ls                                  # list all instances
write alice project_ict_3.pdf       # alice writes a mock file in the database
lsf alice                           # list all stored files from alice.
read alice project_ict_3.pdf 0 -1   # read alice's entire file from the database
read alice project_ict_3.pdf 1 11   # read alice's file from the second byte to the 12th byte (not included)
```
