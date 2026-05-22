# LHTML

LHTML is an experimental document-format project.

The goal is to explore a small, deterministic alternative document stack:
text syntax, compact binary encoding, a minimal renderer, and a deliberately
small sandboxed scripting language.

This is not a browser, a web standard, or a production-ready format. The
specification and implementation are both still moving. Binary details,
runtime behavior, and source syntax may change as the design is tested.

The repository currently contains:

- draft LHT/LHTML design documents;
- a mini parser, encoder, decoder, dumper, and renderer;
- fixture-based checks for text, binary, and render behavior;
- an experimental LJS scripting runtime with isolated library support.

The project is mainly a format and runtime workbench. Its value is in testing
ideas about compact representation, deterministic tooling, and explicit script
authority boundaries.
