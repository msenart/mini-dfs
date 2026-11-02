#import "@preview/fletcher:0.5.8": diagram, node, edge
#import "../common.typ": *

// ---------- 3. Architecture ----------
= Architecture

== Overview

#figure(
  layout(size => {
    let d = diagram(
      spacing: (30mm, 30mm),
      node-stroke: 0.8pt,
      node-inset: 8pt,
      edge-stroke: 0.9pt,

      // Nodes: NameServer en haut, client à gauche, chunkservers sur une ligne
      node((3, 0), [*NameServer* \ (metadata)], fill: ns-fill, shape: rect, corner-radius: 3pt, name: <ns>),
      node((0, 2), [*Client* \ Alice], fill: cl-fill, shape: rect, corner-radius: 3pt, name: <alice>),
      node((1.5, 2), [Chunkserver 1], fill: cs-fill, shape: rect, corner-radius: 3pt, name: <cs1>),
      node((3, 2), [Chunkserver 2], fill: cs-fill, shape: rect, corner-radius: 3pt, name: <cs2>),
      node((4.5, 2), [Chunkserver 3], fill: cs-fill, shape: rect, corner-radius: 3pt, name: <cs3>),
      node((6, 2), [Chunkserver 4], fill: cs-fill, shape: rect, corner-radius: 3pt, name: <cs4>),

      // Plan de contrôle : Alice <-> NameServer (deux flèches séparées)
      edge(<alice>, <ns>, "->", bend: 20deg, label: [1. file name], label-side: left, label-fill: true),
      edge(<ns>, <alice>, "->", bend: 20deg, label: [2. chunk handles \ + locations], label-side: left, label-fill: true),

      // NameServer <-> chunkservers (pointillés, une seule étiquette)
      edge(<ns>, <cs1>, "<->", stroke: (dash: "dashed"), label: [A. allocate / \ remaining storage?], label-pos: 0.5, label-side: right, label-fill: true),
      edge(<ns>, <cs2>, "<->", stroke: (dash: "dashed")),
      edge(<ns>, <cs3>, "<->", stroke: (dash: "dashed")),
      edge(<ns>, <cs4>, "<->", stroke: (dash: "dashed")),

      // Plan de données : Alice -> cs1, puis pipeline cs1 -> cs2 -> cs3
      edge(<alice>, <cs1>, "->", label: [3. chunk], label-side: left, label-fill: true),
      edge(<cs1>, <cs2>, "->", label: [4. forward], label-side: left, label-fill: true),
      edge(<cs2>, <cs3>, "->", label: [5. forward], label-side: left, label-fill: true),
    )
    let w = measure(d).width
    let factor = if w > size.width { size.width / w * 100% } else { 100% }
    scale(factor, reflow: true, d)
  }),
  caption: [The NameServer allocates space on the chunkservers in advance (dashed). Alice asks it where to store the chunks, then sends each chunk once, to its first replica (chunkserver 1 here). The chunkservers then pipeline the chunk on to the other replicas themselves (chunkserver 4 isn't picked as a replica for this particular chunk, so it's left out of the chain).],
)

#v(1.5em)

The database architecture is shown in the schematic right above, illustrating a client requesting to store a file in the database. When the client asks the nameserver to store a file, the nameserver then asks the chunkservers for their remaining storage. Considering this, it evaluates the best file arrangement for the chunkservers: the client's file is going to be split into chunks of regular size and then sent to the concerned servers. The nameserver sends back to the client the information about which chunkserver each chunk should go to. Finally, the client splits the data itself and sends it to one of the concerned chunkservers, along with a stack of the destinations for its replicas.

== Software architecture

The chosen language to build the project is Python, and the object-oriented architecture represents the different actors:

```text
project/
├── __init__.py
├── __main__.py       # entry point
├── chunk_server.py   # Chunkserver class
├── client.py         # Client class
├── globals.py        # shared constants and settings
├── name_server.py    # Nameserver class
└── utils.py          # helper functions
```

The project takes the form of a Python module which uses built-in Python modules only to establish connections:
- `cmd` so that the user can interact with the database during runtime.
- `socket` to establish TCP connections between the actors.
- `threading` to make the different actors act in parallel.

== Metadata Traffic Management
The network traffic is organized with TCP connections only. To establish a connection between two actors, one socket listens and the other calls it to connect.
Once the connection is accepted on both sides, it is handled in a dedicated socket, with the listening side also starting a dedicated thread to keep listening on other incoming connections. It is shown below.
#v(0.5em)
- Caller:
```python
self.call_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
call_sock.connect((host, port))
```
- Listener:
```python
self.listen_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.bind((host, port))
sock.listen()
while self.is_running:
  client_conn, client_addr = self.client_sock.accept()
  threading.Thread(target=self._listen_client, args=(client_conn,client_addr), daemon=True).start()
...
```
#v(0.5em)
All sent packets are either JSON packets or raw byte packets. JSON packets contain light data, such as requests from one machine to another, or responses to those requests. For example, when the nameserver asks a chunkserver for its remaining storage, the request it sends is this:
```python
{'action':'storage'}
```
When the chunkserver receives the request, it sends back to the nameserver:
```python
{'action':'storage', 'memory':<memory>}
```

To send a raw byte chunk, the sender (client or chunkserver) first sends a JSON header, then the raw bytes:
```python
{'action':'write', 'chunk_index':chunk_index} # header

'E8In&56"&"rbiZIUZ_...'                       # raw bytes
```

The sockets are organized this way:
- Client $<->$ Nameserver: the client has the nameserver socket as an attribute, whereas the nameserver handles the client socket in a dedicated thread that always listens to it.
- Nameserver $<->$ Chunkserver: since the nameserver has to compute the best placement for an incoming file, it needs to know about all the chunkservers from a single thread, so the nameserver groups every chunkserver socket into a list attribute. Each chunkserver, conversely, only has the nameserver socket as a single attribute.
- Client $<->$ Chunkserver: a connection is opened and closed on the fly to write and read chunks directly from the source. For a given connection, the chunkserver is always the listener; the caller is usually the client, but during pipelined writes a chunkserver forwarding a chunk to the next replica becomes the caller itself, reconnecting to that next chunkserver's very same client-facing listening socket.

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

      // Alice <-> NameServer (Sockets), bent to route around the chunkserver column
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

      // Chunkserver <-> Chunkserver (pipelined write forwarding, same on-the-fly
      // socket and the same listening endpoint as Alice <-> Chunkserver above)
      edge(<cs1>, <cs2>, "<->",
        label: [Forward (write pipeline) \ Caller $<->$ Listener \ (same endpoint as above)],
        label-pos: 0.5, label-side: right, label-fill: true),
      edge(<cs2>, <cs3>, "<->"),
      edge(<cs3>, <cs4>, "<->"),
    )

    let w = measure(d).width
    let factor = if w > size.width { size.width / w * 100% } else { 100% }
    scale(factor, reflow: true, d)
  }),
  caption: [Socket connection architecture: which side holds the socket as an attribute, which side keeps a listener thread, and which connections are opened on the fly.],
)

#v(1.5em)

However, there is one problem a plain socket cannot solve on its own: when several threads both send requests and expect replies on the same shared socket (for instance, the nameserver querying a chunkserver it keeps a persistent connection to), nothing guarantees that a reply arrives back on the thread that is actually waiting for it. TCP only guarantees that bytes arrive in order, not that the next message read off the wire is the one a particular caller is blocked on. This is why a thread-safe wrapper class, `QueueConn`, was built around `socket`. It tags every outgoing request with a unique, incrementing request id and keeps one `queue.Queue` per in-flight request; a single dedicated thread is the only one allowed to read the socket, and when a reply comes in, it reads the request id echoed back in it and routes the message to the queue of the thread that is actually waiting for that specific reply. Any message carrying no matching id (an unsolicited, server-pushed message) is instead forwarded to a generic handler. This is the mechanism that keeps a shared connection safe to use concurrently without ever delivering one caller's answer to a different caller.

== Storage Organization and Integrity
=== Writing
When the nameserver receives a request from the client to store a file (the client has already computed the number of chunks itself, from the file's size on disk, and sends that count, not the raw byte size, inside the request), it first asks every chunkserver how many chunks it is already holding, with a dedicated request `getall_storage`. Each chunkserver just counts its own `.bin` files, so the nameserver only ever learns a chunk count, never an actual byte count, which is good enough since every chunk is the same fixed `CHUNK_SIZE`. It then simulates the best placement: for each chunk to allocate, it picks whichever chunkservers currently hold the fewest chunks, and immediately bumps their simulated counts so the next chunk's pick already accounts for the ones just assigned:
```python
chunks_held = get_chunk_counts_from_every_chunkserver()
servers_number = min(len(chunks_held), N_REPLICAS)
chunk_bindings = []
for chunk in chunks:
    chosen = argsort(chunks_held)[:servers_number]    # the servers_number least-loaded chunkservers
    chunk_bindings.append(chosen)
    for server in chosen:
        chunks_held[server] += 1                      # tracked for the next chunk's pick, not yet real
```
Right after that, the nameserver asks the chunkservers to allocate the chunks (within a directory lock named `dir_lock`, creating chunk files without actually writing anything inside yet), and once it succeeds, it generates a unique, incrementing file ID and stores the client's name, the filename, and the precise chunk locations under that ID:
```python
{
  1:{
    'clientname':'alice',
    'filename':'filename',
    'chunk_handles':[
      {'host':CHUNKSERVER_HOST, 'port':CHUNKSERVER_PORT, file_index: 0},
      {'host':CHUNKSERVER_HOST, 'port':CHUNKSERVER_PORT, file_index: 1},...
    ]
  }
}
```
The file ID is the real identity of a stored file: a client may write two different files under the same name, each getting its own fresh ID and both being kept. It is sent back to the client as part of the JSON reply, and the client prints it as a receipt. `read` and `lsf` still take a plain filename for convenience, though. The nameserver resolves it internally to the most recently written file with that name for that client (older copies remain reachable only by the ID printed at write time).

The client then writes each chunk through pipelined replication: rather than sending the chunk's bytes to every replica itself (was the first implementation), the client sends them once, to the first chunkserver in that chunk's replica list, together with the list of the remaining replicas as an extra `forward_to` field in the write header:
```python
{'action':'write', 'file_index':file_index, 'forward_to':[{'host':..., 'port':..., 'file_index':...}, ...]}
```
That chunkserver writes the chunk locally exactly as before, and, if `forward_to` is non-empty, opens its own connection to the next chunkserver in the list, forwards the same header shape (with `forward_to` popped by one) and the same chunk bytes, and only acknowledges its own caller once that next hop has acknowledged in turn. This chains the replicas together (client $->$ chunkserver A $->$ chunkserver B $->$ chunkserver C), with the final acknowledgment unwinding back up the chain to the client, instead of the client opening `N_REPLICAS` connections and sending the same bytes that many times itself.

When receiving the data and storing it in its chunk, the chunkserver also computes an MD5 checksum and records it, together with the chunk's byte length, as one line (`<checksum> <length>`) in a dedicated file named `checksum.txt`.

The chunkserver's storage layout is the following:

```text
chunkserver_storage
├── 0.bin
├── 1.bin
├── 2.bin
├── ...
└── checksum.txt
```
(chunk files are numbered from `0`, the way `process_allocate_request`'s `file_index` assigns them; the real `storage/ds1/` listing shown in the Demonstration section above confirms this: `0.bin, 1.bin, 2.bin, 3.bin`.)
=== Reading
When the client asks to read a specific file or specific byte range, the nameserver sends back the whole file's metadata (the ordered list of chunks, each carrying up to `N_REPLICAS` chunkserver locations), and the client works out which of those chunks actually overlap the requested range.

For each needed chunk, in order, the client does not pick a replica ahead of time: it tries the replicas one at a time, in the order the nameserver listed them, until one of them actually hands back a good copy of the chunk:
```python
for i, replicas in enumerate(chunks_needed):
    data = None
    for replica in replicas:                 # try every replica for this chunk, in order
        try:
            with connect(replica.host, replica.port) as sock:
                send(sock, {'action': 'read', 'file_index': replica.file_index})
                response = recv(sock)
                if response['status'] != 'ok':
                    continue                  # this replica is missing/corrupted: try the next one
                data = recv_bytes(sock)
                break                         # got a good copy, stop trying replicas for this chunk
        except ConnectionError:
            continue                          # this replica is unreachable: try the next one

    if data is None:
        raise RuntimeError(f"chunk {i} was unavailable or corrupted on every replica")

    out_file.write(trim_to_requested_range(data, i))   # see below
    # ... then the loop moves on to chunk i + 1
```

A chunkserver never hands back a chunk without checking it first. Before replying, it re-derives the same two invariants the writer recorded in `checksum.txt` at write time (the chunk's length and its MD5 checksum) and compares them against what is actually on disk right now:
```python
def process_read_request(file_index):
    chunk = read_bytes(f"{file_index}.bin")
    ref_checksum, ref_length = checksum_file[file_index]   # recorded when the chunk was written

    if len(chunk) != ref_length:            # cheap check first: catches truncation/padding fast
        return {'status': 'nok', 'payload': 'unexpected length'}
    if md5(chunk) != ref_checksum:          # only hash the chunk once the length already matched
        return {'status': 'nok', 'payload': 'corrupted'}

    return {'status': 'ok'}, chunk          # only a chunk that passes both checks is sent back
```
A chunkserver that fails either check replies `nok` instead of the bytes, which is exactly what sends the client's loop above on to the next replica for that same chunk. A single bad or unreachable replica never fails the read outright, as long as at least one of its siblings still has a good copy. It is oonly when every replica of a chunk fails that the client gives up on the whole read: a `RuntimeError` above is caught further up in `send_read`, which deletes the partial output file rather than leaving a truncated one behind.

Once a chunk is retrieved, the client trims it to the requested byte range (the full chunk in the middle of the range, only the tail of the first chunk and the head of the last one at the edges), appends it to the output file, frees it, and moves on to the next chunk, until every needed chunk has been fetched and the requested range is fully reassembled on disk.

== Handling exceptions

Exception handling might be the weakest part of the project. It was quite messy: as it was not written in Java, so we can't know at every moment which method could raise an Exception. This was all the more important since we have manipulated unstable objects such as threads and sockets. However, we could notice mainly three scenarios when exception handling can be well managed: 
- For socket instance handling: we have used the structure `with self.socket as sock:`
- Whenever performing a network request: we wrap it in a `try:... except Exception as ex:... finally:...` to handle sudden disconnections.
- Whenever we perform a network request that succeded, but the remote request performance failed: this happens when we want to store a file that is too heavy to be stored in the database. A JSON message `{'status':'nok', 'payload':<message>}` is returned to the sender, indicating through the payload that the operation has failed.

== Limitations of the Implementation <sec-limitations>

This model is scoped to fit a course project rather than production use. The nameserver only ever organizes traffic: it never reads or writes file bytes itself, which keeps it lightweight and mirrors GFS's core separation of metadata from data. Replication also mirrors GFS: it is chunkserver-pipelined rather than client-driven, so that the client's connection is not overloaded. Finally, the preallocation with the lock before actually writing the chunks made the writing process more secure.

There are still limitations to our implementation:
- No heartbeat: there is no periodic liveness check between the nameserver and the chunkservers, so a dead chunkserver is only discovered the next time a request happens to target it, and nothing automatically restores the replicas it was holding.
- Little verification between actors: beyond the chunk checksum, there is no authentication protocol, nothing stops a client from acting under another client's name, and chunkservers trust whatever the nameserver tells them.
- Metadata lives only in memory on the nameserver: this is discussed further in the Scalability section.
