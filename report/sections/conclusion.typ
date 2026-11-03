// ---------- 5. Limitations and conclusion ----------
= Limitations and Conclusion

== Scalability

The chunk layer scales the way GFS's does: storage capacity and write bandwidth grow by adding chunkservers, and the nameserver never touches file bytes, so it never becomes a data-path bottleneck. Three aspects limit how far this implementation specifically scales, though:

- Metadata is not persisted: the nameserver keeps its entire file-ID-to-chunk lookup table (`self.files`) as a plain in-memory `dict`. If the nameserver process dies, every chunk byte on every chunkserver becomes unreachable, even though the data itself is untouched, since there is no operation log or checkpoint to replay, unlike GFS's master.
- No failure detection: there is no heartbeat between the nameserver and the chunkservers; a chunkserver that silently dies is only noticed on the next request that happens to target it, and nothing re-replicates the copies it was holding.
- The metadata path is serial (see Performance): querying $N$ chunkservers for free space costs $N$ sequential round trips today, so adding chunkservers to gain write throughput currently backfires.

None of these limitations is minor for a production system — persistence and failure
recovery are among the parts GFS spends the most effort on — but each one sits in a
known part of our code, so the extensions below are well scoped:
- persistence would extend `NameServer.files`'s read/write path with a simple append-only log or periodic snapshot to disk;
- heartbeats could reuse the existing `message` request/response shape on a timer, from each chunkserver to the nameserver;
- re-replication would extend `process_allocate_request` to notice a chunkserver drop out and pick a replacement;
- parallelizing `getall_storage` only requires replacing its sequential `for` loop with one request per chunkserver connection fired concurrently, then gathered.

== Conclusion

mini-dfs set out to reproduce, at a small scale, the core idea behind the Google File System: keep metadata and data on separate paths, let a single coordinator place data without ever carrying it, and replicate it the way GFS does rather than the way that's easiest to code. All three are implemented and demonstrated end to end: a client can write a file that gets chunked and replicated across several chunkservers chosen by a simple least-loaded heuristic, with the chunkservers themselves pipelining each chunk on to its other replicas instead of the client sending it `N_REPLICAS` times, and later read it back either whole or as an arbitrary byte range (including ranges that span a chunk boundary), with each chunk's length and MD5 checksum verified before it is returned, entirely over hand-rolled TCP sockets and JSON framing.

Building it surfaced three problems that make distributed storage hard even at this scale:
- Making sure a reply reaches the thread that is actually waiting for it, when several requests share one socket connection — solved here with `QueueConn`'s request-id based dispatch, detailed in the Architecture section.
- Keeping the coordinator off the data path without starving it of the information it needs to place data well — solved here, imperfectly: see Scalability, with a synchronous storage poll that does not yet scale past a handful of chunkservers.
- Moving replication bandwidth off the client without being able to show the improvement on a single-machine benchmark — solved in the code, and deliberately reported as not shown by the wall-clock numbers in the Performance section, a reminder that a benchmark can be honest about its own blind spots instead of overclaiming.

The simplifications still accepted (no metadata persistence, no heartbeats, a replication chain that forwards a whole chunk at a time rather than streaming it) are among the pieces GFS spends the most engineering effort on.

Security was outside this project's scope entirely, and is worth naming explicitly rather than leaving implicit: every actor talks in plaintext (JSON headers and raw chunk bytes travel unencrypted over TCP, readable and tamperable by anyone on the path), nothing authenticates who is really behind a given `clientname` (it is just a field a client fills in on its own requests, so one client can freely claim another's name), and every actor trusts its peers completely (a chunkserver executes whatever the nameserver tells it to, and the nameserver takes a chunkserver's reported free storage at face value). None of it is remediated here; a real deployment would need at least transport encryption and peer authentication before any of the above would be safe to expose beyond a trusted lab network.

== Contributions

#table(
  columns: (auto, 1fr),
  align: (left, left),
  stroke: 0.5pt + luma(150),
  inset: 6pt,
  table.header([*Member*], [*Contribution*]),
  [Mathieu SENART], [Wrote the `allocate` and `write` request handling, coordinated the codebase for the final report.],
  [Prusothman VIGNESWARAN], [Initiated the codebase architecture: wrote the first files and classes, and the socket usage.],
  [Marc JUSTO ARBONA], [Wrote the `read` request handling, coded the interactive CLI.],
  [David MUY], [Wrote the report.],
)

