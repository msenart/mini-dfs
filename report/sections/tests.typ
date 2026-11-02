// ---------- 4. Tests and performance ----------
= Tests and Performance

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

With 4 chunkservers (where `N_REPLICAS = 3` actually applies — with a single chunkserver there is only ever 1 copy), the write/read throughput is roughly three times lower when `N_REPLICAS  = 3`, and performance gets a little lower the more there are chunks to send. The reason is simple once the mechanism is spelled out: the write request is ensured by the chunkservers to be well performed on each chunkserver. During the chunkserver writing phase, the chunkserver sends the `forward_to` dictionary, and waits the next chunkserver for acknowledgment that the its writing operation is well performed. The client also waits for an acknowledgment from the chunkservers. When `N_REPLICAS = 3`, this means that 3 acknowledgments were sent, 2 for the chunkservers, one for the client.

So we don't gain much write time, and the naive solution, which consists of making the client send the replicas three times to each chunkserver, would have performed similarly, and maybe better. What does change, deterministically, is how many bytes the _client itself_ has to send — which is the actual point of pipelining in GFS, since a client's own bandwidth is usually the most lacking resource, not the datacenter-internal links between chunkservers:

#figure(
  table(
    columns: (auto, auto, auto),
    align: (left, center, center),
    stroke: 0.5pt + luma(150),
    inset: 6pt,
    table.header([*Payload*], [*Client egress — before*], [*Client egress — after*]),
    [2 MiB (1 chunk)],   [6 MiB  (2 MiB $times$ 3)],  [2 MiB],
    [10 MiB (5 chunks)], [30 MiB (10 MiB $times$ 3)], [10 MiB],  
    [40 MiB (20 chunks)], [120 MiB (40 MiB $times$ 3)], [40 MiB],
  ),
  caption: [Bytes the client itself has to upload for a write, with `N_REPLICAS = 3`: exactly 3$times$ before the change (client sends every replica), exactly 1$times$ after (client sends each chunk once; chunkservers forward the rest).],
)

This table's numbers are exact, not measured — they follow directly from the code (the client's write loop sends `chunk_mds` entries one-by-one before the change, `chunk_mds[0]` only after) rather than from a benchmark, which is precisely why the loopback wall-clock benchmark above doesn't reflect them: it cannot distinguish "who sent the bytes" on a single machine, only "how many bytes moved in total."

Separately, adding chunkservers still makes writes slower rather than faster for the same payload, which traces back to `NameServer.getall_storage` (Architecture section) querying each chunkserver's remaining storage in a sequential `for` loop instead of concurrently — unrelated to replication, and still listed as future work in the Conclusion.
