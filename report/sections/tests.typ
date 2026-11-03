// ---------- 4. Tests and performance ----------
= Tests and Performance

All measurements and captures were produced on Windows 11, with Intel (R) Core(TM) Ultra 7 255HX, 32Go RAM, 1To SSD, with Python 3.13.15 managed by uv 0.12.17. 

== Tests

A small set of CLI-level tests (`tests/test_cli.py`) exercises `ls`, `write`, `lsf`, and `read` directly through the same interface a user would type, against a fixture that boots a full in-process cluster (one name server, several chunkservers, one or more clients) over real, if local, TCP sockets. Rather than aiming for exhaustive coverage, each command gets one straightforward case and one deliberately awkward one: an empty cluster for `ls`, a zero-byte file for `write`, and for `read`, a full round trip, a byte range that spans a chunk boundary, and two different kinds of "empty request" (an unknown client, and a client that exists but never wrote anything). The last of those surfaced a real bug while it was being written: reading a file for a client that had never written anything indexed straight into the name server's lookup table without checking the client had written anything first, raising an uncaught exception on the server and leaving the client hanging until its request timed out, instead of failing cleanly. The fix was a guard that treats "no match for this client" as a clean, reported failure instead of an exception, now implicit in the name server's ID-keyed lookup (`process_read_request`, `name_server.py`), which simply finds no matching entry rather than indexing into a missing key.

== Performance

To get a concrete sense of the overhead introduced by the JSON control-plane traffic and the thread-per-connection model, a small benchmark drives the CLI directly (the same mechanism the test suite uses) and times the `write`/`read` commands for synthetic random payloads of increasing size, over loopback TCP on a single machine, with `N_REPLICAS = 3`, after switching replication from client-driven to chunkserver-pipelined (see Architecture):

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (center, left, center, center, center),
    stroke: 0.5pt + luma(150),
    inset: 6pt,
    table.header([*Chunkservers*], [*Payload*], [*Write (s)*], [*Read (s)*], [*Write throughput (MB/s)*]),
    [1], [2 MiB (1 chunk)],   [0.023], [0.032], [86.3],
    [1], [10 MiB (5 chunks)], [0.108], [0.202], [92.7],
    [1], [40 MiB (20 chunks)], [0.538], [0.719], [74.3],
    [4], [2 MiB (1 chunk)],   [0.051], [0.066], [39.4],
    [4], [10 MiB (5 chunks)], [0.319], [0.193], [31.3],
    [4], [40 MiB (20 chunks)], [1.352], [0.658], [29.6],
  ),
  caption: [Write/read wall-clock time and write throughput, single machine, loopback TCP, after moving to pipelined replication. Single-run measurements meant to show architectural trends, not calibrated absolute numbers.],
)

=== Writing
With 4 chunkservers (where `N_REPLICAS = 3`), the write throughput is at least 2 times lower when `N_REPLICAS  = 3`, and performance decreases even more when there are more than 1 chunk to send. The reason is simple once the mechanism is spelled out: the write request is ensured by the chunkservers to be well performed on each chunkserver. During the chunkserver writing phase, the chunkserver sends the `forward_to` dictionary, and waits the next chunkserver for acknowledgment that the its writing operation is well performed. The client also waits for an acknowledgment from the chunkservers. When `N_REPLICAS = 3`, this means that 3 acknowledgments were sent, 2 for the chunkservers, one for the client. So we don't gain much write time, and the naive solution, which consists of making the client send the replicas three times to each chunkserver, would have performed similarly.

What does change, deterministically, is how many bytes the client itself has to send, which is the actual point of pipelining in GFS, since a client's own bandwidth is usually the most lacking resource, not the datacenter-internal links between chunkservers. In our configuration, we only send the chunks once, whereas the naive method would make the client send the chunks three times.

Separately, adding chunkservers (`N_REPLICAS` being constant) still makes writes slower rather than faster for the same payload, which traces back to `NameServer.getall_storage` (Architecture section) querying each chunkserver's remaining storage in a sequential `for` loop instead of concurrently. This is unrelated to replication, and still listed as future work in the Conclusion.

=== Reading

Read time scales with the chunk count, same as write: one round trip per chunk. Unlike write, read is not seriously slowed down by adding chunkservers, since a read is always a single direct hop to whichever replica answers first, with no forwarding chain — reading the 40 MiB file is actually marginally faster with 4 chunkservers than with 1 ($0.719"s" -> 0.658"s"$), while writing it is $2.5$ times slower (Writing, above). The remaining gap at the 1-chunkserver baseline (`0.719s` read vs `0.538s` write) comes from `process_read_request` (`chunk_server.py`) doing more work per chunk than a write does: it lists the whole storage directory to confirm the chunk exists, then re-derives and checks its length and MD5 against `checksum.txt` before replying, where a write just opens the target file and writes to it.
