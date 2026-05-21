# LHT (Light HyperText) — Design Discussion Archive

This document captures the full design conversation for the LHT format — a binary hypertext document format targeting constrained vintage hardware (286-class and up) as a first-class citizen.

The discussion took place over an extended chat session and produced two specification draft documents (lht-spec-part1.md, lht-spec-part2.md). This file summarizes the design decisions, the reasoning behind them, and the open questions, organized so the work can be continued in a different environment (e.g., Claude Code with a proper repository).

---

## Project context

**Author profile:** Belarus-based games programmer (C++/Delphi, DirectX/OpenGL/assembly). Author of the Apus Game Engine. Freelance work upgrading old C++ games (DX9/DX11). DIY enthusiast (STM32). Interest in retro computing (x86), F1, astronomy.

**Origin:** Discussion began as a refinement of an LHT concept originally drafted with DeepSeek. The initial proposal included basic ideas (binary token stream, varint encoding, dictionary-based compression) but had inaccuracies and gaps. This conversation rebuilt the concept on a more solid foundation.

**Goal:** A binary hypertext format that can be parsed and rendered on a 286 with limited RAM, while remaining usable on modern hardware. Inspired by the question: "If we designed a hypertext format today, knowing what we know, with constrained clients as a first-class target — what would it look like?"

---

## Design philosophy

Established principles that guided every decision:

- **P1. Simplicity of the client.** Reference client should be implementable in a few thousand lines of code.
- **P2. Predictability over flexibility.** Same document → essentially same result on every conforming client.
- **P3. One way to do it.** No `style=` parallel to attributes, one encoding (UTF-8), one unit per dimension type.
- **P4. The author writes once; the client adapts.** Documents declare logical intent (font sizes by name, colors by role); clients select concrete realizations.
- **P5. The format is reversible.** Tokenized form ↔ canonical text form, lossless modulo whitespace.
- **P6. The server can be dumb.** Trivial HTTP serving static files is conforming. Tokenization/compilation are optimizations.
- **P7. The client can be small.** Minimal client (no scripts, no network) is conforming.

**Target hardware classes:**
- Minimal: 286, 640K RAM, EGA 16c (static documents, basic forms).
- Standard: 386, 1-4M, VGA 256c (+ scripts, AJAX, JPEG).
- Enhanced: 486+, 4M+, SVGA 16-bit (+ native compilation, full features).

---

## Key decisions made

### Stream representation

- **Varint encoding** with continuation-bit (MIDI/Protobuf style), LSB first. Decoder is ~12 instructions on 8086.
- **Token namespaces** partitioned by purpose (control commands, built-ins by frequency, document-local custom).
- **Magic numbers:** `LHT1` (document), `LHC1` (compiled), `LJS1` (script), `LRS1` (resource bundle).
- **Bundles:** versioned sets of token-to-meaning bindings, baked into clients. Append-only across versions for backward compatibility.
- **Standard bundles:** core-elements, core-attributes, layout-values, system-colors, system-fonts, event-types, script-runtime, mime-types.
- **Custom dictionaries** for per-document and per-site shared tokens.

### Interleaved raw text (key revision)

Originally the design required all strings to be predeclared in a build phase. This was changed:

- **`RAW_TEXT`** — inline string, used once.
- **`RAW_TEXT_SAVE`** — inline string saved to dictionary for reuse.

These commands are allowed anywhere a string is expected. This enables single-pass tokenization (no need to buffer entire document to compute string frequencies). Streaming render is also enabled by this change, though optional.

Inline raw is provided **only for strings**, not other types — strings dominate document content; other types (int, color) are short and best declared up-front.

### Compression

- **Static Huffman** with frozen frequency table prebuilt from a corpus, baked into clients.
- **No LZ-family compression** — once tokenized, byte-level repetition is rare; LZ overhead exceeds benefit for short documents.

### Document model

- **Unified attribute namespace.** No separation of "structural attributes" vs "presentational/style attributes." Everything is just attributes on elements.
- **Constants** declared in head, referenced anywhere by name. Type-checked. Conditional values via `<when>` clauses.
- **Classes** as named bundles of attributes. Multiple classes per element (later wins). State variants (hover, active, focus, disabled).
- **Limited inheritance** — only typographic properties (font, color, line-height, text-align) inherit by default. Others require explicit `inherit` value.
- **System constants** for OS theming integration (system-window, system-text, etc.).

### Layout (significantly evolved through discussion)

**Final container set (5 + table):**
- `block` — vertical flow
- `flow` — inline-flow with wrapping (text-like behavior for blocks)
- `row` — single-line horizontal arrangement
- `fixed` — absolute positioning
- `scrollbox` — vertical scroll with fixed dimensions
- `table` — separate concept for tabular data with `<col>`, `<tr>`, `<td>`, colspan/rowspan

**Box model:**
- **No margin.** Spacing via `<spacer>` element + padding only.
- **Borders cosmetic** — don't affect layout dimensions; can be added/removed dynamically without reflow.
- **Margin-box-style sizing** is moot since no margin; effectively border-box.

**Sizing values:**
- Integer (px), fraction 0..256 (256ths of parent), `auto`, `fill`.
- No `em`, `vh`, `%` separate from fraction, `calc()`.
- **`auto` not allowed for table column widths** — explicit specification only.

**Vertical scroll:** only via `scrollbox` container or implicit body viewport. No `overflow-y` attribute.

**Horizontal scroll:** `overflow-x` attribute on the **child block** (not parent — important detail). Values: `clip` (default), `scroll`, `auto`. Rendered via clipping + offset, no off-screen buffer needed.

**Tables:**
- `<col>` for column-level metadata (width, alignment, defaults for cell attributes)
- `<tr>`, `<td>` with colspan/rowspan
- No `<thead>`/`<tbody>`/`<tfoot>`/`<th>` — express via classes
- Borders on four levels (table > col > tr > td) with specificity, no merging at pixel level
- `internal-borders`, `internal-h-borders`, `internal-v-borders` convenience attributes
- Layered backgrounds (table → col → tr → td)
- Specialized script API (`table.rows[i].cells[j]`)

### Resources and Images (Section 5 of spec)

**Three-level model:**
1. Resources — physical binary assets (GIF, JPEG, font files).
2. Image definitions — logical references with operations (crop, flip, tint, 9-patch).
3. DOM image references — by name only.

**Image operations are render recipes, not new bitmaps:**
- crop = source rectangle
- flip-x/flip-y = iteration direction (zero overhead on x86)
- tint = palette remap on indexed, multiply on truecolor
- 9-patch = render-time loop
- compose = future extension idea; the only operation that creates a new bitmap (cached)

**Conditional resources/images** via `<when>` clauses with fixed predicate set:
- min-colors, min-cpu, has-fpu, has-mmx, min-ram-kb, min-width, min-height, media
- AND-only logic (no OR, no NOT)
- Tabular evaluation, no expression parser

**Atlases** are just regular GIF/JPEG files. No special atlas format. Single shared palette for indexed atlases (DOOM-style palette zoning recommended).

### Fonts (Section 6 of spec)

- **Bitmap fonts only** in v1.
- **Logical names**: `default-sans-12`, `default-serif-14-italic`, etc. Discrete sizes (8/10/12/14/18/24 — not arbitrary).
- **Fallback chains** for multilingual coverage (Latin custom + Cyrillic from default).
- **LFNT format** — compact bitmap font format with 1bpp mandatory, 2bpp optional. Multiple Unicode ranges per file.
- **Built-in coverage**: Latin + Cyrillic for sans/serif/mono/heading families.
- **Soft typographic determinism** — text layout NOT pixel-exact across clients (allows different fonts, hinting, AA). Structure is deterministic, fine typography is not.
- **No kerning, no ligatures** — at low resolutions barely perceptible, complicates renderer.
- **Algorithmic bold/italic** for fonts without dedicated variants (smear/shear).
- **Vector font idea (deferred):** Author has a concept for stroke-based vector fonts with built-in hinting via stroke semantics + copy/mirror operations. Not specified in v1; mentioned as future direction.

### Events (concept agreed, not yet specified)

- **Single handler per event per element** (not multiple, like DOM). For chained handlers, use "interrupt-style" pattern: read old, wrap, replace.
- **Bubble-only propagation**, no capture phase.
- **Standard event set**: pointer (click, dblclick, mouseup/down, enter/leave, move), keyboard (down/up/press), form (change, input, focus, blur, submit), lifecycle (load, unload, resize).
- Event handlers attached as attributes (`on-click=funcName`) or via script API.
- Event object minimal: target, currentTarget, type, plus per-category specifics.

### Scripts (concept agreed, not yet specified)

- **JS-like syntax**, but stripped: no closures, no prototypes, no classes, no `this`-binding.
- **Dynamic typing for scalars** + **typed arrays** for binary/efficient data:
  - `Array(uint8, ...)`, `Array(int16, ...)`, `Array(uint32, ...)`, `Array(string, ...)`, `Array(any, ...)`.
  - Binary views over buffers.
- **Compilation on the client** (not server). Server sends source by default.
- **Optional pre-compiled bytecode** for minimal clients via content negotiation.
- **Stack-based VM**, ~50-70 opcodes. Reference counting for memory. try/catch for runtime errors.
- **Functions are first-class values** (just function pointers, no captured context).
- **Tiered execution**: interpreter for cold code, optional JIT to native for hot code (386+).

### Network and Storage (concept agreed, not yet specified)

**Fetch:**
- `fetch(url, method, callback, data?, options?)` — callback is required, data optional.
- Auto-detection of body format from data type (object → URL-encoded; object with binary fields → multipart; binary array → raw octet-stream; null → empty).
- **Request object** for advanced cases (configure, send, abort, progress polling).
- Single-threaded async event loop. No threads.
- Response auto-parsed by Content-Type.
- Methods: GET, POST, PUT, DELETE.
- Redirects followed by default.
- Cross-origin allowed (no CORS).

**Storage:**
- `storage` (persistent) and `session` (until browser close) namespaces.
- Origin-isolated.
- String → string only (use JSON for structures).
- Optional `expires_seconds` parameter; lazy expiration.
- `keys()`, `size()` (in bytes), etc.

**Security model:**
- Network: unrestricted (request to any host allowed).
- Data: isolated by origin (storage, DOM between documents).
- Scripts from same origin: shared context (HTML-like).
- External scripts: shared by default, `sandboxed` opt-in for isolation via message passing.

### Content negotiation

Three-tier server model:
- **Tupid server**: serves source files as-is.
- **Smart server**: tokenizes, validates, caches, may compile scripts.
- **Both modes** valid; clients support both.

Client capability headers indicate what it accepts (format, compression, image types, color depth, CPU class, cached dictionaries). Server adapts.

For scripts, three delivery levels: source, tokenized source, compiled bytecode.

---

## Specification documents produced

Two markdown files were created during the conversation:

1. **lht-spec-part1.md** (934 lines, ~30 KB) — Sections 1-4:
   - Overview and Philosophy
   - Stream Representation (varint, tokens, bundles, RAW_TEXT)
   - Document Model (attributes, elements, constants, classes, head/body)
   - Layout (containers, box model, sizing, overflow, table, spacer, determinism, algorithm)

2. **lht-spec-part2.md** (497 lines, ~18 KB) — Sections 5-6:
   - Resources and Images (3-level model, operations, atlases, conditional)
   - Fonts (logical names, soft determinism, LFNT format, fallback chains, attributes)

These are draft documents. They've gone through several revisions during the conversation as decisions were refined.

---

## Open questions / next steps

### Sections to write

- **Section 7. Inline Content** — Three-level model (text modifiers, text runs, inline atoms). Critical foundation for sections 8-9.
- **Section 8. Events** — Concept agreed; needs formal specification.
- **Section 9. Scripts** — Largest section. Language syntax, type system, VM bytecode, opcodes, DOM API, async model.
- **Section 10. Network and Storage** — Fetch API, Request object, storage, security model.
- **Section 11. Content Negotiation** — Headers, server tiers, dictionary caching.
- **Appendices:**
  - Bundle contents (token assignments) — large reference table.
  - Canonical text form syntax.
  - LFNT binary format specification.
  - Sample documents.

### Specific open questions

- **Bundle token assignments** — exact byte values for every token in standard bundles (huge reference table, tedious but necessary).
- **Canonical text form** — exact syntax for the human-readable representation. Should be reversible to/from binary form (P5).
- **Bundle 0 / reserved tokens** — final assignment of special tokens.
- **`<img>` categorization** — is it a leaf element, or an inline atom in flow text? Depends on Section 7.
- **RGB vs RGBA** in tint and color attributes — likely RGB-only in v1, transparency via GIF transparent index.
- **LHT-native bitmap format** — was mentioned as `bitmap` resource type; may be unnecessary if GIF coverage is sufficient.
- **Vector font format** — author has concept but it's a separate undertaking.
- **JSON-like serialization** for fetch() request bodies with nested objects — decided on bracket-notation (PHP/Rails style), but exact rules need writing.
- **Script error handling details** — try/catch syntax, exception types, error event on document.
- **Sandboxed scripts** — exact message-passing API.
- **Validation rules** for tokenizing servers — formal list of what causes 5xx vs warnings.

### Things to revisit later

- **Streaming render** — agreed it's possible but optional. May want a small section formalizing what minimal client guarantees are when not implementing it.
- **Dynamic content scenarios** — how does AJAX-replaced content interact with classes, constants, etc.? Probably scripts manipulate DOM directly and styling re-applies; needs formal description.
- **Form elements** — agreed they exist (text, multiline, password, number, checkbox, radio, select, range, button) but exact attributes and script API for each not yet enumerated.

### Practical next steps in Claude Code

1. **Set up repository:** `git init lht-spec/`, drop in part1.md, part2.md, this archive.
2. **Define structure:**
   - `spec/` — main specification parts.
   - `appendices/` — bundle contents, LFNT format, etc.
   - `examples/` — sample documents in canonical text form.
   - `discussion/` — design discussions, ADRs (Architecture Decision Records) for major decisions.
3. **Continue with Section 7 (Inline Content)** — most foundational of the unwritten sections; needed for events and scripts.
4. **Consider a reference implementation** in parallel — even a partial one would help validate decisions. Probably starting with a tokenizer/detokenizer (text ↔ binary) since that exercises sections 1-4 thoroughly.

---

## Notable design tensions / discussions worth re-reading

A few points went through multiple iterations and the reasoning matters:

1. **Streaming render** — first dismissed, then re-evaluated when it became clear that interleaved RAW_TEXT removed the main blocker (need to predeclare strings). Now: optional but possible.

2. **Inline elements** — first considered eliminating entirely (everything via state machine), then settled on three-level model (text modifiers without identity, text runs with identity, inline atoms). This is still an open design point; needs Section 7 to formalize.

3. **Containers count** — went from 5 to 6 (adding flow), then back to 5 (removing grid in favor of explicit table element). Each change improved the model.

4. **overflow attribute placement** — moved between parent and child. Settled on **child** (the wide block declares its overflow strategy). More semantically natural.

5. **Border collision** — initial claim that adjacent borders "merge" was wrong at pixel level. Revised to: each level renders its own borders; for regular table grids, use table-level convenience attributes.

6. **Auto column widths** — considered, then rejected. Multi-pass layout for tables would compromise the single-pass principle, and content-dependent widths produce unstable layouts.

7. **Cookies vs localStorage** — eliminated cookies entirely in favor of explicit storage + script-managed auth tokens.

---

## Summary of LHT in one paragraph

LHT is a binary hypertext format with these core properties: tokens replace strings via dictionary references; documents declare classes, constants, and image definitions in a head section; layout uses six element types (block, flow, row, fixed, scrollbox, table) with deterministic single-pass calculation, no margins (only spacer + padding), cosmetic borders (don't affect layout), and only-vertical scrolling outside dedicated overflow-x containers; resources and images use a three-level model (physical resource → logical image with render-time operations → DOM reference) supporting client-capability-based variants; fonts are bitmap with logical names selecting concrete files per client; scripts use a JS-like language with dynamic scalar typing plus typed arrays, compiled on client (optionally pre-compiled by server); content negotiation lets servers and clients meet at any of three sophistication levels; storage is origin-isolated key-value with optional expiration; network is unrestricted but data is isolated. The design targets 286-class hardware as a first-class citizen, with implementation expected to fit in single-digit kilobytes of code.
