// ---------- 2. Product presentation ----------
= Product Presentation and Demonstration

This school project's purpose is to simulate a mini distributed file system (mini-dfs). It is constituted of three main classes:
- `ChunkServer`, whose purpose is to store clients' files under the form of byte chunks.
- a master (named `NameServer` in the code), which deals with all the metadata and organizes the traffic.
- `Client`, which are the database users.

The project is dependency-free (outside of `pytest` for testing). It handles its connections with TCP protocols only and the built-in `socket` module. The CLI was built using the built-in `cmd` module from Python.

Hyperparameters in `globals.py` can be changed before launching the project, most notably `CHUNK_SIZE` (2 MiB by default) and `N_REPLICAS` (3 by default). Apart from the global hyperparameters, there is no data leak between the different instances of the simulation, making the simulation reproducible with real devices.

From the project root, preferably within a dedicated python virtual environment, here are the essential commands to use the CLI:
```sh
pip install -e .                            # Installs the project as a module in the current environment using pyproject.toml.
python -m mini_dfs                          # Start module.
help                                        # available commands.
macro                                       # preset architecture (4 chunkservers, 1 nameserver, 1 client).
ls                                          # list all instances.
write alice big_demo.bin                    # alice writes an 8MB+ file in the database.
lsf alice                                   # list all stored files from alice (shows id + filename).
read alice big_demo.bin 0 -1                # read alice's entire file from the database.
read alice big_demo.bin 2000000 2000064     # read 64 bytes near the 2 MB mark, inside chunk 0.
read alice big_demo.bin 2097136 2097168     # read 32 bytes straddling the chunk 0 / chunk 1 boundary.
```

Running these exact commands against a real 8.58 MB file, `big_demo.bin`, gives:

#figure(
  image("../media/terminal1.png", width: 80%)
)

A new folder named `storage/` (automatically destroyed when exiting the program) should appear, containing the memory of the whole simulation. After these commands, you should get this:

#figure(
  image("../media/terminal2.png", width: 30%)
)

And last, in the `checksum.txt` for `ds1` and `ds4`, you should have this:

#figure(
  stack(
    dir: ttb,
    spacing: 8pt,
    grid(
      columns: (1fr, 1fr),
      gutter: 8pt,
      image("../media/terminal3.png"),
      image("../media/checksums2.png"),
    ),
    align(center, image("../media/checksums3.png", width: 50%)),
  ),
  caption: "checksum.txt of ds1 (left), ds2 (right) and ds3 (bottom): should contain 3 exact same checksum.txt files (each line is: <md5 checksum> <number of bytes>). And 2097152 = 1024 * 1024 * 2 = 2 MB."
)

#figure(
  image("../media/terminal4.png", width: 50%),
  caption: "checksum.txt of ds4: should contain 3 checksums, and the first checksum is the second checksum of ds1."
)

=== Chunk distribution and replica placement

Inspecting `storage/dsN/` directly right after the write shows how the 5 chunks $times$ `N_REPLICAS` = 3 = 15 chunk copies actually landed: 4 on `ds1`, `ds2`, `ds3` each, and 3 on `ds4`:

#figure(
  table(
    columns: (auto, auto, auto),
    align: (left, center, right),
    stroke: 0.5pt + luma(150),
    inset: 6pt,
    table.header([*Chunkserver*], [*Chunk files*], [*Total bytes stored*]),
    [`ds1`], [4], [6,477,724],
    [`ds2`], [4], [6,477,724],
    [`ds3`], [4], [6,477,724],
    [`ds4`], [3], [6,291,456],
  ),
  caption: [Real per-chunkserver chunk counts and byte totals after writing `big_demo.bin`, read directly off disk.],
)

The nameserver's `self.files[1]["chunk_handles"]` entry records exactly which chunkserver (and which local file index on that chunkserver, since each chunkserver numbers its own `.bin` files independently) holds each of the 5 logical chunks:

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (center, left, left, left, left),
    stroke: 0.5pt + luma(150),
    inset: 6pt,
    table.header([*Chunk*], [*Size (bytes)*], [*Replica 1*], [*Replica 2*], [*Replica 3*]),
    [0], [2,097,152], [`ds1` (0.bin)], [`ds2` (0.bin)], [`ds3` (0.bin)],
    [1], [2,097,152], [`ds4` (0.bin)], [`ds1` (1.bin)], [`ds2` (1.bin)],
    [2], [2,097,152], [`ds3` (1.bin)], [`ds4` (1.bin)], [`ds1` (2.bin)],
    [3], [2,097,152], [`ds2` (2.bin)], [`ds3` (2.bin)], [`ds4` (2.bin)],
    [4], [186,268],   [`ds1` (3.bin)], [`ds2` (3.bin)], [`ds3` (3.bin)],
  ),
  caption: [Chunk-to-replica mapping for `big_demo.bin`, read directly from the nameserver's in-memory table. The least-loaded placement rotates which three servers get picked as each chunk is allocated.],
)

As a cross-check independent of the read path's own integrity verification (Storage Organization and Integrity), reading `checksum.txt` on two different replicas of chunk 0 (`ds1`'s `0.bin` and `ds2`'s `0.bin`) by hand gives the exact same checksum and length:

```text
storage/ds1/checksum.txt line 0 (ds1's 0.bin): d03a2f029848d41b860f63b0934f3be0 2097152
storage/ds2/checksum.txt line 0 (ds2's 0.bin): d03a2f029848d41b860f63b0934f3be0 2097152
```

confirming the two replicas genuinely hold identical bytes, not just that each one locally agrees with its own recorded checksum.

=== Reads: full file, near a round offset, and across a chunk boundary

```text
(mini-dfs) read alice big_demo.bin 0 -1
File written to storage\alice\big_demo.bin
(mini-dfs) read alice big_demo.bin 2000000 2000064
File written to storage\alice\big_demo.bin
(mini-dfs) read alice big_demo.bin 2097136 2097168
File written to storage\alice\big_demo.bin
```

Each of these three reads was independently verified against the real `big_demo.bin` bytes on disk (the client always writes to the same output path, so each result was captured and compared before the next read overwrote it):

- Full read (`0 -1`): 8,574,876 bytes come back, byte-identical to the entire source file. This is the complete round trip across all 5 chunks and 4 chunkservers.
- Near the 2 MB mark, inside chunk 0 (`2000000 2000064`): 64 bytes, entirely within chunk 0 (which spans bytes 0 to 2,097,151), so this exercises a plain single-chunk fetch at an offset close to, but short of, the chunk boundary. Byte-identical to `big_demo.bin[2000000:2000064]`, hex:
  ```
  2b52f341b2bc455995885f7ad4a2803929be1e6853485d924c9ff6a961f87d
  a1420858df9f535d651401f3af886da2b3d72eeda204246f85acded5b5e2e4
  71e2
  ```
- Across the chunk 0 / chunk 1 frontier (`2097136 2097168`, i.e. `CHUNK_SIZE` $-$ 16 to `CHUNK_SIZE` $+$ 16): 32 bytes, the last 16 of chunk 0 fused with the first 16 of chunk 1, two separate chunkserver round trips stitched into one contiguous result. Byte-identical to `big_demo.bin[2097136:2097168]`, hex:
  ```
  57915bb1cf92927c83e991c56bd8585be9d6c2ded936a64b1cf2589ea49ee69
  5
  ```

All three match the corresponding slice of the real source file exactly, confirming the offset-to-chunk-index arithmetic, the chunk-boundary stitching, and the replica selection all hold up on a file more than four times the single-chunk size, not just on the smaller single-PDF case shown earlier in development.
