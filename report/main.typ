// ============================================================
//  Report template — Typst
//  Compile with: typst compile rapport.typ
// ============================================================

#import "@preview/fletcher:0.5.8": diagram, node, edge

// ---------- Metadata (edit these) ----------
#let titre = "Project Title"
#let sous-titre = "Project Report"
#let auteurs = ("First LAST", "First LAST")
#let encadrant = "First LAST"
#let organisme = "School / Company name"
#let date = datetime.today().display("[month repr:long] [day], [year]")
// ---------- Global settings ----------
#set document(title: titre, author: auteurs)
#set page(
  paper: "a4",
  margin: (x: 2.5cm, y: 2.5cm),
)
#set text(font: "New Computer Modern", size: 11pt, lang: "en")
#set par(justify: true, leading: 0.7em, first-line-indent: 1em, spacing: 0.9em)
#set heading(numbering: "1.1")
#set figure(gap: 1em)
#set list(indent: 1em)
#set enum(indent: 1em)

// Headings
#show heading.where(level: 1): it => {
  pagebreak(weak: true)
  v(1cm)
  text(size: 20pt, weight: "bold", it)
  v(0.6cm)
}
#show heading.where(level: 2): it => {
  v(0.5em)
  text(size: 14pt, it)
  v(0.3em)
}
#show heading.where(level: 3): it => text(size: 12pt, style: "italic", it)

// Links and code
#show link: set text(fill: rgb("#1a4f9c"))
#show raw.where(block: true): it => block(
  fill: luma(245),
  stroke: 0.5pt + luma(200),
  inset: 8pt,
  radius: 3pt,
  width: 100%,
  it,
)

// ============================================================
//  Title page
// ============================================================
#page(numbering: none)[
  #align(center)[
    #v(2cm)
    #text(size: 12pt)[#organisme]
    #v(3cm)
    #line(length: 60%, stroke: 1pt)
    #v(0.5cm)
    #text(size: 26pt, weight: "bold")[#titre]
    #v(0.3cm)
    #text(size: 16pt)[#sous-titre]
    #v(0.5cm)
    #line(length: 60%, stroke: 1pt)
    #v(3cm)
    #for a in auteurs [
      #text(size: 13pt)[#a] \
    ]
    #v(1cm)
    #text(size: 11pt)[Supervisor: #encadrant]
    #v(1fr)
    #text(size: 11pt)[#date]
  ]
]

// ============================================================
//  Abstract (optional)
// ============================================================
#page(numbering: none)[
  #align(center)[#text(size: 14pt, weight: "bold")[Abstract]]
  #v(0.5cm)
  #lorem(80)
]

// ============================================================
//  Tables of contents
// ============================================================
#set page(numbering: "i")
#counter(page).update(1)
#outline(title: "Table of Contents", indent: auto, depth: 3)

#pagebreak()
#outline(title: "List of Figures", target: figure.where(kind: image))

#pagebreak()
#outline(title: "List of Tables", target: figure.where(kind: table))

// ============================================================
//  Report body
// ============================================================
#set page(
  numbering: "1",
  header: context {
    if counter(page).get().first() > 0 {
      set text(size: 9pt, fill: luma(100))
      titre
      h(1fr)
      sous-titre
      v(-0.3em)
      line(length: 100%, stroke: 0.4pt + luma(180))
    }
  },
)
#counter(page).update(1)

// ---------- 1. Introduction ----------
= Introduction
== Context
Handling huge amounts of data every day has become the norm. The systems in charge of it must offer high throughput, the ability to absorb many concurrent requests, durability, and easy maintenance, so that a failure can be repaired without interrupting the service or losing data.

The historical starting point is the single-node relational database: strong consistency through ACID transactions, but scaling is only vertical (a bigger server), which quickly becomes costly and leaves a single point of failure. Replication addresses availability and read throughput by copying data to other nodes, but writes remain limited by a single primary. Sharding splits the data across machines so that capacity and write throughput grow with the number of nodes, at the price of costly cross-shard queries and delicate rebalancing. These shared-nothing designs scale well, but they traditionally relied on expensive and reliable servers, assuming that failures were rare.

At the beginning of the 2000s, Google’s workloads (web-scale crawling and indexing, very large files mostly appended to and read sequentially) made this model economically unviable. On thousands of commodity machines, failures are no longer exceptional but constant, so the system must tolerate them automatically through replication and fast recovery. This is the context in which the Google File System (GFS) was designed: a distributed file system optimized for large files and high aggregate throughput, which separates metadata management from data transfer.

The project reproduces a similar data structure : separating the different types of data into their own pipelines, and dedicate a server to organize the data traffic.
// ---------- 2. Product presentation ----------
= Product Presentation and Demonstration

This school project's purpose is to simulate a mini distributed file system (mini-dfs). It is constituted of three main classes:
- ``ChunkServer``, which purpose is to store clients files under the form of byte chunks.
- a master (named ``NameServer`` in the code), which deals with all the metadata and organizes the traffic.
- ``Client``, which are the database users.

The project is managed through the module manager **uv**. The project is **dependence-free**. It handles its connections with TCP protocols only and the famous ``socket`` module.

Hyperparameters in ``globals.py`` can be changed before launching the project.

The CLI was build using the built-in ``cmd`` module from python.

Essential commands to use the CLI:
``` cmd
python -m mini_dfs                  # Start module
help                                # available commands
macro                               # preset architecture (4 chunkservers, 1 nameserver, 1 client)
ls                                  # list all instances
write alice project_ict_3.pdf       # alice writes a mock file in the database
lsf alice                           # list all stored files from alice.
read alice project_ict_3.pdf 0 -1   # read alice's entire file from the database
read alice project_ict_3.pdf 1 11   # read alice's file from the second byte to the 12th byte (not included)
```

// ---------- 3. Architecture ----------
= Architecture

== Overview

#let ns-fill = rgb("#fde7c8")
#let cs-fill = rgb("#d6e6f7")
#let cl-fill = rgb("#d9f0d3")

#figure(
  layout(size => {
    let d = diagram(
      spacing: (46mm, 22mm),
      node-stroke: 0.8pt,
      node-inset: 8pt,
      edge-stroke: 0.9pt,

      // Nodes
      node((0, 1.5), [*Client* \ Alice], fill: cl-fill, shape: rect, corner-radius: 3pt, name: <alice>),
      node((4, 1.5), [*NameServer* \ (metadata)], fill: ns-fill, shape: rect, corner-radius: 3pt, name: <ns>),
      node((2, 0), [Chunkserver 1], fill: cs-fill, shape: rect, corner-radius: 3pt, name: <cs1>),
      node((2, 1), [Chunkserver 2], fill: cs-fill, shape: rect, corner-radius: 3pt, name: <cs2>),
      node((2, 2), [Chunkserver 3], fill: cs-fill, shape: rect, corner-radius: 3pt, name: <cs3>),
      node((2, 3), [Chunkserver 4], fill: cs-fill, shape: rect, corner-radius: 3pt, name: <cs4>),

      // NameServer <-> chunkservers (space allocation, remaining storage)
      edge(<ns>, <cs1>, "<->", label: [A. allocate space / \ remaining storage?], label-pos: 0.45, label-side: left, label-fill: true),
      edge(<ns>, <cs2>, "<->"),
      edge(<ns>, <cs3>, "<->"),
      edge(<ns>, <cs4>, "<->"),

      // Alice <-> NameServer (metadata), routed around the chunkservers
      edge(<alice>, <ns>, "->", bend: 70deg, label: [1. file name], label-side: left, label-fill: true),
      edge(<ns>, <alice>, "->", bend: 70deg, label: [2. chunk handles + locations], label-side: left, label-fill: true),

      // Alice -> each chunkserver (data)
      edge(<alice>, <cs1>, "->", label: [3. chunk 1], label-pos: 0.5, label-side: left, label-fill: true),
      edge(<alice>, <cs2>, "->", label: [3. chunk 2], label-pos: 0.5, label-side: left, label-fill: true),
      edge(<alice>, <cs3>, "->", label: [3. chunk 3], label-pos: 0.5, label-side: right, label-fill: true),
      edge(<alice>, <cs4>, "->", label: [3. chunk 4], label-pos: 0.5, label-side: right, label-fill: true),
    )
    let w = measure(d).width
    let factor = if w > size.width { size.width / w * 100% } else { 100% }
    scale(factor, reflow: true, d)
  }),
  caption: [The NameServer allocates space on the chunkservers in advance. Alice asks it where to store the chunks, then sends each chunk directly to a chunkserver.],
)

The database architecture is shown in the schematic right above, illustrating when the client requesting to store a file in the database. First, the client asks the nameserver for storing a file. The nameserver asks then the chunkservers for their remaining storage. Considering this, it evaluates the best file arrangement for the chunkservers : the client's file is going to be split into chunks of regular size and then sent into the concerned servers. The nameserver sends back the information to the client of which the client should send the information to. Finally, the client splits the data itself and sends the data to the concerned chunkservers.

The reproduced model is simplified : no heartbeat (chunkservers send regularly a message to tell the nameserver that the servers are alive) and no replication within the chunkserver network, that would allow the client to send the file only once.

== Software architecture

The chosen language to assure the project is Python, and the object-oriented architecture represents quite the different actors:

```text
project/
├── __init__.py
├── __main__.py       # entry point
├── chunk_server.py
├── client.py      
├── globals.py        # shared constants and settings
├── name_server.py
└── utils.py          # helper functions
```

The project takes the form of a Python module which uses built-in python modules only to assure connection:
- `cmd` so that the teacher can interact with the database.
- `socket` to establish TCP connections between the actors.
- `threading` to make the different actors be able to act in parallel.

== Metadata Traffic Management
The network traffic is organized with TCP connections only. In order to establish connection between two actors, one socket should listen and the other socket should call him for connection.
When the connection is accepted for both parts, the connection is handled in a dedicated socket and thread for the listener. It is shown below.
Caller:
```
self.call_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
call_sock.connect((host, port))
```

Listener:
```
self.listen_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.bind((host, port))
sock.listen()
while self.is_running:
  client_conn, client_addr = self.client_sock.accept()
  threading.Thread(target=self._listen_client, args=(client_conn,client_addr), daemon=True).start()
...
```

All the send packets are JSON packets and raw bytes packets. JSON packets contains light data, such as requests from a machine to another, or responses from the requests. For example, when the nameserver calls the chunkservers to get their remaining storage, the request they send is this:
```
{'action':'storage'}
```
When the chunkserver receives the information, it sends back to the nameserver:
```
{'action':'storage', 'memory':<memory>}
```

In order to send a byte chunk, the sender (clients or chunkservers) first sends a JSON header, then the raw bytes:
```
{'action':'write', 'chunk_index':chunk_index} # header

'E8In&56"&"rbiZIUZ_...'                       # raw bytes
```

The sockets are organized this way:
- Client $<->$ Nameserver: The client has the nameserver socket as an attribute, whereas the nameserver handles the client socket as a thread that always listen to the socket.
- Nameserver $<->$ Chunkserver: as the nameserver has to make the best fetching schedule for an importing file, it should know all the chunkservers in a single thread, so the nameserver groups all chunkserver sockets into a list attribute. The chunkserver has the nameserver socket as an attribute.
- Client $<->$ Chunkserver: A connection is opened and closed on-the-fly to write and read the chunks directly from the source. The client is the caller and the chunkserver is always the listener in both case (read and write).

#figure(
  layout(size => {
    let d = diagram(
      spacing: (46mm, 22mm),
      node-stroke: 0.8pt,
      node-inset: 8pt,
      edge-stroke: 0.9pt,

      // Nodes
      node((0, 1.5), [*Client* \ Alice], fill: cl-fill, shape: rect, corner-radius: 3pt, name: <alice>),
      node((4, 1.5), [*NameServer* \ (metadata)], fill: ns-fill, shape: rect, corner-radius: 3pt, name: <ns>),
      node((2, 0), [Chunkserver 1], fill: cs-fill, shape: rect, corner-radius: 3pt, name: <cs1>),
      node((2, 1), [Chunkserver 2], fill: cs-fill, shape: rect, corner-radius: 3pt, name: <cs2>),
      node((2, 2), [Chunkserver 3], fill: cs-fill, shape: rect, corner-radius: 3pt, name: <cs3>),
      node((2, 3), [Chunkserver 4], fill: cs-fill, shape: rect, corner-radius: 3pt, name: <cs4>),

      // Alice <-> NameServer (Sockets)
      // On courbe la flèche pour contourner la colonne de Chunkservers au centre
      edge(<alice>, <ns>, "<->", bend: -50deg, 
        label: [Client: Attr socket \ NS: Thread listener], 
        label-pos: 0.5, label-side: left, label-fill: true),

      // NameServer <-> Chunkservers (Sockets)
      edge(<ns>, <cs1>, "<->", 
        label: [NS: List attr \ CS: Attr socket], 
        label-pos: 0.5, label-side: left, label-fill: true),
      edge(<ns>, <cs2>, "<->"),
      edge(<ns>, <cs3>, "<->"),
      edge(<ns>, <cs4>, "<->"),

      // Alice <-> Chunkservers (Sockets)
      edge(<alice>, <cs1>, "<->"),
      edge(<alice>, <cs2>, "<->", 
        label: [On-the-fly (R/W) \ Caller $<->$ Listener], 
        label-pos: 0.5, label-side: left, label-fill: true),
      edge(<alice>, <cs3>, "<->"),
      edge(<alice>, <cs4>, "<->"),
    )
    
    // Auto-scaling pour ne pas déborder horizontalement
    let w = measure(d).width
    let factor = if w > size.width { size.width / w * 100% } else { 100% }
    scale(factor, reflow: true, d)
  }),
  caption: [Architecture des connexions Sockets : attributs, threads et connexions à la volée],
)

However, there is one problem that a socket couldn't solve. When two threads listen on the same socket, there is no guarantee that the message could be read by the right thread. That is why a thread-safe wrapper class QueueConn was created. Wrapping socket, It sorts the the requests it sends by an ordinal order of message. It automatically adds one more pair (key, value) to the JSON packet so that, when receiving the packet from QueueConn, the instance can bind the request to the response and bring the right response to the right thread.

== Storage Organization and Integrity

When the nameserver receives the request from the client to store a file (the file size is given inside the client's request), it first asks chunkservers how much space they have spent. Then, the nameserver simulates the best chunk distribution among the chunkservers:
```
chunk_bindings = []
for chunk in chunks:
  chunkservers_indices = np.argsort(chunkservers_storage_bytes)
  for i in range(n_replicas):
    chunk_bindings.append(chunkservers_indices[i])
    chunkservers_storage_bytes[i]+=CHUNK_SIZE
```
Right after that, the nameserver asks chunkservers to allocate the chunks (creating chunk files without actually writing anything inside), and when it succeeds, it stores in a LUT the name of the client, the filename, and the precise chunks locations: 
```
{
  'alice':{
  'filename':[
      {'host':CHUNKSERVER_HOST, 'port':CHUNKSERVER_PORT, file_index: 0},
      {'host':CHUNKSERVER_HOST, 'port':CHUNKSERVER_PORT, file_index: 1},...   
    ]
  }
}
```
Then, it sends back to the client a JSON where the chunks should be sent. The client finally sends  
the chunks to the concerned servers. In the project, it is the client that takes care of sending replicas to the chunkservers.

When receiving the data and storing it into its chunk, the chunkserver also calculates and stores the md5 checksum in a dedicated file named `checksums.txt`.

The chunkservers storage architecture is the following:

```
chunkserver_storage
├── 1.bin
├── 2.bin
├── 3.bin
├── ...
└── checksums.txt
```

When the client asks to read a specific file or specific bytes in the file, the nameserver sends the whole file metadata to it, and the client calculates which chunk is useful to get. The chunkserver reads the right chunks, verify that the checksum is correct, and sends the chunks back to the client. Finally, the client can get specific bytes from the concerned chunks.

== Advantages and Limitations of the implementation

This model is a simplified model of the GFS.
The main advantages of our architecture are:
- The nameserver only organizes the traffic and doesn't deal with large amount of data.
There are many drawbacks to our implementation:
- There is no replication within the database. Therefore client has to send the file n-replica times to the chunkservers.
- There is no client verification protocol in many places, especially between chunkservers and clients when writing and reading bytes.
// - There might be concurrency bugs.

// ---------- 4. Tests and performance ----------
= Tests and Performance

== Tests
#lorem(40)

#figure(
  table(
    columns: (auto, 1fr, auto),
    align: (left, left, center),
    stroke: 0.5pt + luma(150),
    inset: 6pt,
    table.header([*Test*], [*Description*], [*Result*]),
    [T1], [Description of test 1], [Passed],
    [T2], [Description of test 2], [Passed],
    [T3], [Description of test 3], [Failed],
  ),
  caption: [Test summary.],
) <tab-tests>

== Performance
#lorem(40)

#figure(
  rect(width: 80%, height: 5cm, fill: luma(240))[#align(center + horizon)[Performance chart]],
  caption: [Performance measurements.],
) <fig-perf>

// ---------- 5. Limitations and conclusion ----------
= Limitations and Conclusion

== Scalability
#lorem(50)

== Conclusion
#lorem(60)

// ============================================================
//  Bibliography (optional — create refs.bib)
// ============================================================
// #pagebreak()
// #bibliography("refs.bib", style: "ieee", title: "References")

// ============================================================
//  Appendices (optional)
// ============================================================
// #pagebreak()
// #set heading(numbering: "A.1")
// #counter(heading).update(0)
// = Appendices
