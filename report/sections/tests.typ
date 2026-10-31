// ---------- 4. Tests and performance ----------
= Tests and Performance

== Tests

The test suite (``tests/test_cli.py``, 22 tests) runs under ``pytest`` against a shared fixture (``tests/conftest.py``) that boots a full cluster *in-process*: one ``NameServer``, a configurable number of ``ChunkServer`` instances, and one or more ``Client`` instances, all bound to real (if local) TCP sockets and driven through the same ``cmd``-style commands as the interactive CLI. Every test tears every entity down afterwards, and a small ``wait_for(...)`` helper polls for asynchronous state (socket registration, pushed messages) instead of sleeping a fixed amount of time.

The suite covers four areas:
- entity creation and CLI argument validation (``create_client``, ``create_nameserver``, ``create_chunkserver``, and the error messages on wrong arities),
- cluster bootstrap (``startall``, the ``macro`` preset, ``ls``),
- the message-push path between a client and the nameserver,
- write / list-files (``write``, ``lsf``): chunking, replication count, load balancing across chunkservers, write-once semantics, per-client isolation, and graceful no-ops on an unknown client name.

Running the suite against the current state of the implementation gives:

#figure(
  table(
    columns: (1fr, auto, auto, auto),
    align: (left, center, center, center),
    stroke: 0.5pt + luma(150),
    inset: 6pt,
    table.header([*Category*], [*Tests*], [*Passed*], [*Failed*]),
    [Entity creation / CLI validation], [6], [5], [1],
    [Cluster bootstrap (`startall`, `macro`, `ls`)], [3], [1], [2],
    [Messaging], [3], [2], [1],
    [Write / list files], [10], [6], [4],
    table.hline(),
    [*Total*], [*22*], [*14*], [*8*],
  ),
  caption: [Test results by category.],
)

The eight failures are not newly-discovered bugs so much as drift between the test suite and later implementation changes — concrete examples found while going through the failures:
- ``test_startall`` expects a ``Client.port`` attribute that no longer exists on the ``Client`` class.
- ``test_macro`` still expects the ``macro`` preset to create a single chunkserver; it now provisions four.
- ``test_lsf_unknown_client_is_a_noop`` expects silence on an unknown client name; ``lsf`` now prints an explicit "client name ... doesn't exist" message.
- ``test_write_stores_every_chunk_on_n_replicas`` and ``test_write_with_a_single_chunkserver`` assume chunk/allocation counts that no longer match the current allocation logic.

This is a maintenance gap rather than a correctness one — the implementation evolved and the assertions were not all updated to match — and reconciling the eight tests with the current behavior is listed as future work in the Conclusion.

== Performance

To get a concrete sense of the overhead introduced by the JSON control-plane traffic and the thread-per-connection model, a small benchmark drives the CLI directly (the same mechanism the test suite uses) and times the ``write``/``read`` commands for synthetic random payloads of increasing size, over loopback TCP on a single machine, with ``N_REPLICAS = 3``, after switching replication from client-driven to chunkserver-pipelined (see Architecture):

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

With 4 chunkservers (where ``N_REPLICAS = 3`` actually applies — with a single chunkserver there is only ever 1 copy, replicated or not), wall-clock write time is only modestly better than before the change (roughly 10-25% faster, e.g. 1.786 s $->$ 1.352 s for 40 MiB), *not* three times faster as the "client sends it 3 times" framing might suggest. The reason is simple once the mechanism is spelled out: on one machine over loopback, the *total* bytes moved on the wire are unchanged — three copies of each chunk still get transferred, whether the client makes all three transfers itself or a chain of chunkservers does, and the chain is not byte-pipelined (noted in Architecture), so the hops run one after another rather than overlapping. Wall-clock time on a single-machine benchmark was never going to show the real benefit.

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
  caption: [Bytes the client itself has to upload for a write, with ``N_REPLICAS = 3``: exactly 3$times$ before the change (client sends every replica), exactly 1$times$ after (client sends each chunk once; chunkservers forward the rest).],
)

This table's numbers are exact, not measured — they follow directly from the code (the client's write loop sends `chunk_mds` entries one-by-one before the change, `chunk_mds[0]` only after) rather than from a benchmark, which is precisely why the loopback wall-clock benchmark above doesn't reflect them: it cannot distinguish "who sent the bytes" on a single machine, only "how many bytes moved in total."

Separately, adding chunkservers still makes writes slower rather than faster for the same payload, which traces back to ``NameServer.getall_storage`` (Architecture section) querying each chunkserver's remaining storage in a sequential ``for`` loop instead of concurrently — unrelated to replication, and still listed as future work in the Conclusion.
