// ---------- 2. Product presentation ----------
= Product Presentation and Demonstration

This school project's purpose is to simulate a mini distributed file system (mini-dfs). It is constituted of three main classes:
- `ChunkServer`, whose purpose is to store clients' files under the form of byte chunks.
- a master (named `NameServer` in the code), which deals with all the metadata and organizes the traffic.
- `Client`, which are the database users.

The project is managed through the module manager `uv`. The project is *dependency-free* (outside of `pytest` for testing). It handles its connections with TCP protocols only and the built-in `socket` module.

Hyperparameters in `globals.py` can be changed before launching the project — most notably `CHUNK_SIZE` (2 MiB by default) and `N_REPLICAS` (3 by default). Apart from the hyperparameters, there is NO data leak between the different instances.

The CLI was built using the built-in `cmd` module from Python.

Essential commands to use the CLI:
```sh
python -m mini_dfs                  # Start module.
help                                # available commands.
macro                               # preset architecture (4 chunkservers, 1 nameserver, 1 client).
ls                                  # list all instances.
write alice project_ict_3.pdf       # alice writes a mock file in the database.
lsf alice                           # list all stored files from alice.
read alice project_ict_3.pdf 0 -1   # read alice's entire file from the database.
read alice project_ict_3.pdf 1 11   # read alice's file from the second byte to the 12th byte (not included).
```

Running these exact commands against a real 2.04 MB PDF (`project_ict_3.pdf`, split into 2 chunks since it's just over `CHUNK_SIZE`) gives:

```text
(mini-dfs) macro
[ChunkServer ds1, localhost, None] created.
[ChunkServer ds2, localhost, None] created.
[ChunkServer ds3, localhost, None] created.
[ChunkServer ds4, localhost, None] created.
[Client alice, localhost, None] created.
[NameServer ns1, localhost, 8080] created.
All clients and chunkservers have been bound to the nameserver !
All entities have started !
(mini-dfs) ls
[ChunkServer ds1, localhost, 8081]
[ChunkServer ds2, localhost, 8081]
[ChunkServer ds3, localhost, 8081]
[ChunkServer ds4, localhost, 8081]
[Client alice, localhost, 8080]
[NameServer ns1, localhost, 8080]
(mini-dfs) write alice project_ict_3.pdf
[NameServer ns1, localhost, 8080] received an allocation request of 2 chunks
[Client alice, localhost, 8080]: project_ict_3.pdf written successfully as file_id=1 (2 chunk(s)).
(mini-dfs) lsf alice
[Client alice, localhost, 8080]: id=1 project_ict_3.pdf
(mini-dfs) read alice project_ict_3.pdf 0 -1
File written to storage\alice\project_ict_3.pdf
(mini-dfs) read alice project_ict_3.pdf 1 11
File written to storage\alice\project_ict_3.pdf
```

The last command overwrites that same output path with just the requested slice: the resulting file is exactly 10 bytes, `PDF-1.7\n\n4` — bytes 1 through 10 of the source PDF's header, confirmed byte-identical to that exact slice of the original file.
