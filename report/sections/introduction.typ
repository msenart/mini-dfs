= Introduction
== Context
Handling huge amounts of data every day has become the norm. The systems in charge of it must offer high throughput, the ability to absorb many concurrent requests, durability, and easy maintenance, so that a failure can be repaired without interrupting the service or losing data.

The historical starting point is the single-node relational database: strong consistency through ACID transactions, but scaling is only vertical (a bigger server), which quickly becomes costly and leaves a single point of failure. Replication addresses availability and read throughput by copying data to other nodes, but writes remain limited by a single primary. Sharding splits the data across machines so that capacity and write throughput grow with the number of nodes, at the price of costly cross-shard queries and delicate rebalancing. These shared-nothing designs scale well, but they traditionally relied on expensive and reliable servers, assuming that failures were rare.

At the beginning of the 2000s, Google's workloads (web-scale crawling and indexing, very large files mostly appended to and read sequentially) made this model economically unviable. On thousands of commodity machines, failures are no longer exceptional but constant, so the system must tolerate them automatically through replication and fast recovery. This is the context in which the Google File System (GFS) was designed: a distributed file system optimized for large files and high aggregate throughput, which separates metadata management from data transfer.

The project reproduces a similar data structure: separating the different types of data into their own pipelines, and dedicating a server to organize the data traffic.
