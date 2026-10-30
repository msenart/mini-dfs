// Values shared by more than one section file (currently: diagram fill colors
// used by the two architecture diagrams). Centralized here instead of in
// main.typ because #include'd section files don't inherit main.typ's scope —
// anything a section needs must be imported explicitly from this file.
#let ns-fill = rgb("#fde7c8")
#let cs-fill = rgb("#d6e6f7")
#let cl-fill = rgb("#d9f0d3")
