// ============================================================
//  Report — Typst
//  Compile with: typst compile main.typ
//
//  The report body lives in sections/*.typ and is pulled in via #include
//  near the bottom of this file. Shared values used by more than one
//  section (diagram colors) live in common.typ, since #include'd files
//  don't inherit this file's scope.
// ============================================================

// ---------- Metadata (edit these) ----------
#let titre = "mini-dfs"
#let sous-titre = "A Simplified Distributed File System Inspired by the Google File System"
#let auteurs = ("Mathieu SENART",) // add more names here if this was a team project
#let encadrant = "TODO: supervisor name"
#let organisme = "TODO: school / institute name"
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
//  Abstract
// ============================================================
#page(numbering: none)[
  #align(center)[#text(size: 14pt, weight: "bold")[Abstract]]
  #v(0.5cm)
  This report presents mini-dfs, a simplified distributed file system built as a university project and directly inspired by the Google File System (GFS). The system separates metadata management from data storage: a single NameServer tracks how files are split into chunks and where each chunk is replicated, several ChunkServer processes store the raw chunk bytes and verify their integrity with MD5 checksums, and Client processes talk to both to write and read files. All communication runs over plain TCP sockets and a custom length-prefixed JSON protocol, without any third-party networking library. A thread-safe wrapper, QueueConn, multiplexes concurrent requests and replies over a single shared socket connection using per-request identifiers, so that a reply always reaches the specific caller waiting for it. Chunk replication itself follows GFS's pipelined model: a client sends each chunk once, and the chunkservers forward it on to the other replicas themselves. The project is exercised through an interactive command-line interface and a pytest suite that boots a full in-process cluster for each test. We describe the architecture, measure write/read performance over loopback TCP for different payload sizes and chunkserver counts — including the reduction in client upload bandwidth that pipelined replication brings — and discuss the simplifications still made relative to GFS (no heartbeat-based failure detection, no metadata persistence) together with the concrete scalability trade-offs they imply.
]

// ============================================================
//  Tables of contents
// ============================================================
#set page(numbering: "i")
#counter(page).update(1)
#outline(title: "Table of Contents", indent: auto, depth: 3)

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

#include "sections/introduction.typ"
#include "sections/product.typ"
#include "sections/architecture.typ"
#include "sections/tests.typ"
#include "sections/conclusion.typ"

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
