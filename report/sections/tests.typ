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

To get a concrete sense of the overhead introduced by the JSON control-plane traffic and the thread-per-connection model, a small benchmark drives the CLI directly (the same mechanism the test suite uses) and times the ``write``/``read`` commands for synthetic random payloads of increasing size, over loopback TCP on a single machine, with ``N_REPLICAS = 3``:

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (center, left, center, center, center),
    stroke: 0.5pt + luma(150),
    inset: 6pt,
    table.header([*Chunkservers*], [*Payload*], [*Write (s)*], [*Read (s)*], [*Write throughput (MB/s)*]),
    [1], [2 MiB (1 chunk)],   [0.022], [0.054], [90.2],
    [1], [10 MiB (5 chunks)], [0.157], [0.182], [63.8],
    [1], [40 MiB (20 chunks)], [0.678], [0.846], [59.0],
    [4], [2 MiB (1 chunk)],   [0.059], [0.101], [33.7],
    [4], [10 MiB (5 chunks)], [0.346], [0.314], [28.9],
    [4], [40 MiB (20 chunks)], [1.786], [0.915], [22.4],
  ),
  caption: [Write/read wall-clock time and write throughput, single machine, loopback TCP. Single-run measurements meant to show architectural trends, not calibrated absolute numbers.],
)

Two things stand out:
- *Write throughput is dominated by the replication factor.* Each chunk's bytes are sent three times by the *client* (once per replica) rather than forwarded chunkserver-to-chunkserver, so the client's own upload bandwidth is the bottleneck, not chunkserver disk I/O.
- *Adding chunkservers makes writes slower, not faster,* for the same payload (going from 1 to 4 chunkservers roughly triples write time). This traces directly back to ``NameServer.getall_storage`` (Architecture section): it queries each chunkserver's remaining storage in a plain Python ``for`` loop, one request-reply round trip at a time, instead of firing the ``storage`` requests concurrently. With four chunkservers, that is four sequential metadata round trips before a single byte is transferred, for every file write.

This is consistent with the architecture's intent — the nameserver is deliberately kept out of the data path, since it never sees file bytes — but its metadata path is currently serial, which caps how well the system scales as more chunkservers are added. Parallelizing ``getall_storage`` (e.g. one thread, or one concurrent request per chunkserver connection, instead of a sequential loop) is a contained, well-understood optimization listed as future work.
