#import "@preview/fletcher:0.5.8": diagram, node, edge
#import "../common.typ": *

// ---------- 3. Architecture ----------
= Architecture

== Overview

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

The database architecture is shown in the schematic right above, illustrating a client requesting to store a file in the database. First, the client asks the nameserver to store a file. The nameserver then asks the chunkservers for their remaining storage. Considering this, it evaluates the best file arrangement for the chunkservers: the client's file is going to be split into chunks of regular size and then sent to the concerned servers. The nameserver sends back to the client the information about which chunkserver each chunk should go to. Finally, the client splits the data itself and sends it to the concerned chunkservers.

The reproduced model is simplified: no heartbeat (chunkservers regularly telling the nameserver that they are alive) and no chunkserver-to-chunkserver replication — the client itself is the one sending every replica (see @sec-limitations below).

== Software architecture

The chosen language to build the project is Python, and the object-oriented architecture represents the different actors:

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

The project takes the form of a Python module which uses built-in Python modules only to establish connections:
- `cmd` so that the user can interact with the database interactively.
- `socket` to establish TCP connections between the actors.
- `threading` to make the different actors act in parallel.

== Metadata Traffic Management
The network traffic is organized with TCP connections only. To establish a connection between two actors, one socket listens and the other calls it to connect.
Once the connection is accepted on both sides, it is handled in a dedicated socket, with the listening side also starting a dedicated thread to keep listening on other incoming connections. It is shown below.
Caller:
```python
self.call_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
call_sock.connect((host, port))
```

Listener:
```python
self.listen_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.bind((host, port))
sock.listen()
while self.is_running:
  client_conn, client_addr = self.client_sock.accept()
  threading.Thread(target=self._listen_client, args=(client_conn,client_addr), daemon=True).start()
...
```

All sent packets are either JSON packets or raw byte packets. JSON packets contain light data, such as requests from one machine to another, or responses to those requests. For example, when the nameserver asks a chunkserver for its remaining storage, the request it sends is this:
```python
{'action':'storage'}
```
When the chunkserver receives the request, it sends back to the nameserver:
```python
{'action':'storage', 'memory':<memory>}
```

To send a byte chunk, the sender (client or chunkserver) first sends a JSON header, then the raw bytes:
```python
{'action':'write', 'chunk_index':chunk_index} # header

'E8In&56"&"rbiZIUZ_...'                       # raw bytes
```

The sockets are organized this way:
- Client $<->$ Nameserver: the client has the nameserver socket as an attribute, whereas the nameserver handles the client socket in a dedicated thread that always listens on it.
- Nameserver $<->$ Chunkserver: since the nameserver has to compute the best placement for an incoming file, it needs to know about all the chunkservers from a single thread, so the nameserver groups every chunkserver socket into a list attribute. Each chunkserver, conversely, only has the nameserver socket as a single attribute.
- Client $<->$ Chunkserver: a connection is opened and closed on the fly to write and read chunks directly from the source. The client is always the caller and the chunkserver is always the listener, for both reads and writes.

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

      // Alice <-> NameServer (Sockets) — bent to route around the chunkserver column
      edge(<alice>, <ns>, "<->", bend: -50deg,
        label: [Client: attr. socket \ NameServer: thread listener],
        label-pos: 0.5, label-side: left, label-fill: true),

      // NameServer <-> Chunkservers (Sockets)
      edge(<ns>, <cs1>, "<->",
        label: [NameServer: list attr. \ ChunkServer: attr. socket],
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

    let w = measure(d).width
    let factor = if w > size.width { size.width / w * 100% } else { 100% }
    scale(factor, reflow: true, d)
  }),
  caption: [Socket connection architecture: which side holds the socket as an attribute, which side keeps a listener thread, and which connections are opened on the fly.],
)

However, there is one problem a plain socket cannot solve on its own: when several threads both send requests and expect replies on the *same* shared socket (for instance, the nameserver querying a chunkserver it keeps a persistent connection to), nothing guarantees that a reply arrives back on the thread that is actually waiting for it — TCP only guarantees that bytes arrive in order, not that the next message read off the wire is the one a particular caller is blocked on. This is why a thread-safe wrapper class, ``QueueConn``, was built around ``socket``. It tags every outgoing request with a unique, incrementing request id and keeps one ``queue.Queue`` per in-flight request; a single dedicated thread is the only one allowed to read the socket, and when a reply comes in, it reads the request id echoed back in it and routes the message to the queue of the thread that is actually waiting for that specific reply — any message carrying no matching id (an unsolicited, server-pushed message) is instead forwarded to a generic handler. This is the mechanism that keeps a shared connection safe to use concurrently without ever delivering one caller's answer to a different caller.

== Storage Organization and Integrity

When the nameserver receives a request from the client to store a file (the file size is given inside the client's request), it first asks the chunkservers how much space they have used. Then, the nameserver simulates the best chunk distribution among the chunkservers:
```python
chunk_bindings = []
for chunk in chunks:
  chunkservers_indices = np.argsort(chunkservers_storage_bytes)
  for i in range(n_replicas):
    chunk_bindings.append(chunkservers_indices[i])
    chunkservers_storage_bytes[chunkservers_indices[i]]+=CHUNK_SIZE
```
Right after that, the nameserver asks the chunkservers to allocate the chunks (creating chunk files without actually writing anything inside yet), and once it succeeds, it stores in a lookup table the client's name, the filename, and the precise chunk locations:
```python
{
  'alice':{
  'filename':[
      {'host':CHUNKSERVER_HOST, 'port':CHUNKSERVER_PORT, file_index: 0},
      {'host':CHUNKSERVER_HOST, 'port':CHUNKSERVER_PORT, file_index: 1},...
    ]
  }
}
```
It then sends this placement back to the client as a JSON message. The client finally sends the chunks to the concerned servers; in this project, it is the client — not the chunkservers or the nameserver — that takes care of sending every replica.

When receiving the data and storing it in its chunk, the chunkserver also computes and stores an MD5 checksum in a dedicated file named ``checksums.txt``.

The chunkserver's storage layout is the following:

```text
chunkserver_storage
├── 1.bin
├── 2.bin
├── 3.bin
├── ...
└── checksums.txt
```

When the client asks to read a specific file or specific byte range, the nameserver sends the whole file's metadata back to it, and the client computes which chunks are actually needed. The chunkservers read the relevant chunks, verify that the checksum is correct, and send the chunks back to the client, which finally extracts the requested bytes from them.

== Limitations of the Implementation <sec-limitations>

This model is a deliberately simplified version of GFS, scoped to fit a course project rather than production use. The nameserver only ever organizes traffic — it never reads or writes file bytes itself, which keeps it lightweight and mirrors GFS's core separation of metadata from data.

There are still limitations to our implementation:
- *Replication is client-driven, not server-orchestrated.* Each chunk's ``N_REPLICAS`` copies are sent by the *client* directly to every target chunkserver, rather than being pipelined chunkserver-to-chunkserver as in GFS. This divides a client's effective upload bandwidth by ``N_REPLICAS`` — quantified in the Performance section.
- *No heartbeat.* There is no periodic liveness check between the nameserver and the chunkservers, so a dead chunkserver is only discovered the next time a request happens to target it, and nothing automatically restores the replicas it was holding.
- *Little verification between actors.* Beyond the chunk checksum, there is no authentication protocol — nothing stops a client from acting under another client's name, and chunkservers trust whatever the nameserver tells them.
- *Metadata lives only in memory* on the nameserver — discussed further in the Scalability section.
