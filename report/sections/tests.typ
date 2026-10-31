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

With 4 chunkservers (where `N_REPLICAS = 3` actually applies — with a single chunkserver there is only ever 1 copy, replicated or not), wall-clock write time is only modestly better than before the change (roughly 10-25% faster, e.g. 1.786 s $->$ 1.352 s for 40 MiB), *not* three times faster as the "client sends it 3 times" framing might suggest. The reason is simple once the mechanism is spelled out: on one machine over loopback, the *total* bytes moved on the wire are unchanged — three copies of each chunk still get transferred, whether the client makes all three transfers itself or a chain of chunkservers does, and the chain is not byte-pipelined (noted in Architecture), so the hops run one after another rather than overlapping. Wall-clock time on a single-machine benchmark was never going to show the real benefit.

What *does* change, deterministically, is how many bytes the _client itself_ has to send — which is the actual point of pipelining in GFS, since a client's own uplink (e.g. a laptop on a home connection writing to a datacenter) is usually the scarce resource, not the datacenter-internal links between chunkservers:

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
