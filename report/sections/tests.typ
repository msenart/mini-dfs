// ---------- 4. Tests and performance ----------
= Tests and Performance

All measurements and captures were produced on Windows 11, with Intel (R) Core(TM) Ultra 7 255HX, 32Go RAM, 1To SSD, with Python 3.13.15 managed by uv 0.12.17. 

== Tests

A small set of CLI-level tests (`tests/test_cli.py`) exercises `ls`, `write`, `lsf`, `read`, and the directory commands `mkdir`, `rmdir` and `lsdir` directly through the same interface a user would type, against a fixture that boots a full in-process cluster (one name server, several chunkservers, one or more clients) over real, if local, TCP sockets. Rather than aiming for exhaustive coverage, each command gets one straightforward case and one deliberately awkward one: an empty cluster for `ls`, a zero-byte file for `write`, and for `read`, a full round trip, a byte range that spans a chunk boundary, and two different kinds of "empty request" (an unknown client, and a client that exists but never wrote anything). The last of those surfaced a real bug while it was being written: reading a file for a client that had never written anything indexed straight into the name server's lookup table without checking the client had written anything first, raising an uncaught exception on the server and leaving the client hanging until its request timed out, instead of failing cleanly. The fix was a guard that treats "no match for this client" as a clean, reported failure instead of an exception, now implicit in the name server's ID-keyed lookup (`process_read_request`, `name_server.py`), which simply finds no matching entry rather than indexing into a missing key.

The directory feature has its own tests in the same file. They check that `mkdir` creates missing parents and can be repeated, that invalid paths (with `..`) and unknown directories are refused, that a file written into a nested directory is read back identically by its directory and filename, and that the same filename in two different directories gives two independent files. They also check that writing the same name twice in one directory still resolves to the latest copy (the older one is reachable by ID), that writing into a missing directory fails without storing any chunk, that `rmdir` refuses non-empty directories and the root, and that directories are kept per client name. While writing them, a file whose size was an exact multiple of `CHUNK_SIZE` revealed two small bugs: the client asked the nameserver for one chunk too many, leaving an empty chunk that could not be read back, and a read up to the end of the file (`-1`) dropped the last byte. Both were fixed, and a test now covers this case.

== Performance

To get a concrete sense of the overhead introduced by the JSON control-plane traffic and the thread-per-connection model, a small benchmark drives the CLI directly (the same mechanism the test suite uses) and times the `write`/`read` commands for synthetic random payloads of increasing size, over loopback TCP on a single machine, with `N_REPLICAS = 3`, after switching replication from client-driven to chunkserver-pipelined (see Architecture):

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (center, left, center, center, center),
    stroke: 0.5pt + luma(150),
    inset: 6pt,
    table.header([*Chunkservers*], [*Payload*], [*Write (s)*], [*Read (s)*], [*Client write throughput (MB/s)*]),
    [1], [2 MiB (1 chunk)],   [0.023], [0.032], [86.3],
    [1], [10 MiB (5 chunks)], [0.108], [0.202], [92.7],
    [1], [40 MiB (20 chunks)], [0.538], [0.719], [74.3],
    [4], [2 MiB (1 chunk)],   [0.051], [0.066], [39.4],
    [4], [10 MiB (5 chunks)], [0.319], [0.193], [31.3],
    [4], [40 MiB (20 chunks)], [1.352], [0.658], [29.6],
  ),
  caption: [Write/read wall-clock time and write throughput, single machine, loopback TCP, after moving to pipelined replication. Single-run measurements meant to show architectural trends, not calibrated absolute numbers. Measures were taken after the fixes described in Section 4.1],
)

=== Writing
Compared with a single chunkserver, which can only hold one copy of each chunk, writing to 4 chunkservers with three replicas is 2.2 to 3 times slower. The reason is simple once the mechanism is spelled out: not only the chunk has to be copied three times, but also the replication pipeline makes chunkservers wait for its peer's acknowledgment, and the peer acknowledgment would depend on its own peer, etc... The acknowledgments are recursive. When `N_REPLICAS = 3`, this means that 3 acknowledgments were sent, 2 for the chunkservers, one for the client. So we don't gain much write time, and the naive solution, which consists of making the client send the replicas three times to each chunkserver, would have performed similarly.

What does change, deterministically, is how many bytes the client itself has to send, which is the actual point of pipelining in GFS, since a client's own bandwidth is usually the most lacking resource, not the datacenter-internal links between chunkservers. In our configuration, we only send the chunks once, whereas the naive method would make the client send the chunks three times.

=== Reading

Unlike writes, reads go through no forwarding chain: each chunk is fetched from the first replica in the nameserver's list that returns a valid copy. With 10 MiB and 40 MiB, reads take about as long with 4 chunkservers as with 1 (0.202 s → 0.193 s and 0.719 s → 0.658 s), while writing 40 MiB is 2.5 times slower; only the 2 MiB read is slower (0.032 s → 0.066 s), which a single run cannot distinguish from noise. With one chunkserver, reads are slower than writes (0.719 s against 0.538 s for 40 MiB). A likely cause is the extra work in process_read_request (chunk_server.py): it lists the storage directory and reads checksum.txt before checking the chunk's length and MD5, whereas a write computes the MD5 once and records it. We have not profiled this.

