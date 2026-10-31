// ---------- 5. Limitations and conclusion ----------
= Limitations and Conclusion

== Scalability

The chunk layer scales the way GFS's does: storage capacity and write bandwidth grow by adding chunkservers, and the nameserver never touches file bytes, so it never becomes a data-path bottleneck. Three aspects limit how far *this* implementation specifically scales, though:

- *Metadata is not persisted.* The nameserver keeps its entire file-to-chunk lookup table (``self.lut``) as a plain in-memory ``dict``. If the nameserver process dies, every chunk byte on every chunkserver becomes unreachable, even though the data itself is untouched — there is no operation log or checkpoint to replay, unlike GFS's master.
- *No failure detection.* As noted in the Architecture section, there is no heartbeat between the nameserver and the chunkservers; a chunkserver that silently dies is only noticed on the next request that happens to target it, and nothing re-replicates the copies it was holding.
- *The metadata path is serial* (see Performance): querying $N$ chunkservers for free space costs $N$ sequential round trips today, so adding chunkservers to gain write throughput currently backfires.

None of these are fundamental — they are the corners that were deliberately cut to keep the project within the scope of a course assignment. Each maps cleanly to one function, which keeps them tractable as concrete next steps rather than open-ended ideas:
- persistence would extend ``NameServer.lut``'s read/write path with a simple append-only log or periodic snapshot to disk;
- heartbeats could reuse the existing ``message`` request/response shape on a timer, from each chunkserver to the nameserver;
- re-replication would extend ``process_allocate_request`` to notice a chunkserver drop out and pick a replacement;
- parallelizing ``getall_storage`` only requires replacing its sequential ``for`` loop with one request per chunkserver connection fired concurrently, then gathered.
- reconciling the eight test failures identified in the Tests section with the current behavior, so the suite can be trusted as a regression check for the fixes above.

== Conclusion

mini-dfs set out to reproduce, at a small scale, the core idea behind the Google File System: keep metadata and data on separate paths, let a single coordinator place data without ever carrying it, and replicate it the way GFS does rather than the way that's easiest to code. All three are implemented and demonstrated end to end — a client can write a file that gets chunked and replicated across several chunkservers chosen by a simple least-loaded heuristic, with the chunkservers themselves pipelining each chunk on to its other replicas instead of the client sending it `N_REPLICAS` times, and later read it back byte-exact and checksum-verified from any offset, entirely over hand-rolled TCP sockets and JSON framing.

Building it surfaced three problems that make distributed storage hard even at this scale: making sure a reply reaches the thread that is actually waiting for it when several requests share one socket connection (solved here with ``QueueConn``'s request-id–based dispatch, detailed in the Architecture section); keeping the coordinator off the data path without starving it of the information it needs to place data well (solved here, imperfectly — see Scalability — with a synchronous storage poll that does not yet scale past a handful of chunkservers); and moving replication bandwidth off the client without being able to show the improvement on a single-machine benchmark (solved in the code, and deliberately reported as *not* shown by the wall-clock numbers in the Performance section — a reminder that a benchmark can be honest about its own blind spots instead of overclaiming).

The simplifications still accepted — no metadata persistence, no heartbeats, a replication chain that forwards a whole chunk at a time rather than streaming it — are among the pieces GFS spends the most engineering effort on. In hindsight, that was a reasonable way to spend a limited project budget: get the core data path right and measurable first, fix the parts that were clearly wrong once understood (client-driven replication among them), and leave the remaining fault-tolerance machinery as clearly scoped, well-understood future work rather than as unknown unknowns.
