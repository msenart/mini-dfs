# mini-dfs

# Overview

This school project's purpose is to simulate a mini distributed file system (mini-dfs). It is constituted of three main classes:
- ``ChunkServer``, which purpose is to store clients files under the form of byte chunks.
- a master (named ``NameServer`` in the code), which deals with all the metadata and organizes the traffic.
- ``Client``, which are the database users.

The project is managed through the module manager **uv**. The project is **dependence-free**, except for testing which is done with ``pytest``. It handles its connections with TCP protocols only and the famous ``socket`` module. To handle listening and sending request packets on the same socket simultaneously (possible on two different threads), a specific class named ``QueueConn`` which wraps the ``socket`` module was added, taking advantage of the ``thread.Lock()`` system.

# Launch the project

Hyperparameters in ``globals.py`` can be changed before launching the project.

## ``cli.py``

The cli was build using the built-in ``cmd`` module from python.

Essential commands to use the CLI:
``` cmd
python -m mini_dfs
help
macro
ls
write alice project_ict_3.pdf
lsf alice
read alice project_ict_3.pdf 0 -1
read alice project_ict_3.pdf 1 11
```
