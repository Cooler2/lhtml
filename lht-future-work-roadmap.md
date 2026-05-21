# LHT Future Work Roadmap

**Status:** draft  
**Purpose:** possible directions for the next design and implementation passes after the binary encoding and tokenization discussions.

---

## 1. Minimal Vertical Slice

**Status:** baseline implemented.

The project now has a working minimal end-to-end implementation path:

```text
.lht source -> normalized tree -> tokenized binary stream -> decoded tree -> token dump / disassembly
```

Implemented artifacts:

- `examples/minimal/index.lht` — canonical tiny source document;
- `examples/minimal/index.lhb` — generated mini binary stream;
- `examples/minimal/decoded.dump` — decoded tree dump fixture;
- `examples/minimal/token.dump` — symbolic source token dump fixture;
- `examples/minimal/binary.dump` — disassembly-style binary dump fixture;
- `examples/minimal/render.bmp` — first bitmap render output for the mini DOM subset;
- `examples/layout-row/index.lht` — focused row/block/spacer layout example;
- `examples/layout-row/render.bmp` — bitmap render for the row layout example;
- `examples/layout-row/render-gdi.bmp` — experimental GDI render for the row layout example;
- `examples/font-basic/index.lht` — semantic font family/size example;
- `examples/font-basic/render.bmp` — bitmap render for semantic font attributes;
- `examples/font-basic/render-gdi.bmp` — experimental GDI render for semantic font attributes;
- `examples/color-basic/index.lht` — text, background, and border color example;
- `examples/color-basic/render.bmp` — bitmap render for color attributes;
- `examples/color-basic/render-gdi.bmp` — experimental GDI render for color attributes;
- `examples/visual-box/index.lht` — padding and border width box rendering example;
- `examples/visual-box/render.bmp` — bitmap render for box visual attributes;
- `examples/visual-box/render-gdi.bmp` — experimental GDI render for box visual attributes;
- `examples/class-basic/index.lht` — class attribute round-trip and resolver groundwork example;
- `examples/class-basic/render.bmp` — bitmap render through the resolved attribute path;
- `examples/class-basic/render-gdi.bmp` — experimental GDI render through the resolved attribute path;
- `examples/style-class-basic/index.lht` — first STYLE stream class declaration example;
- `examples/style-class-basic/render.bmp` — bitmap render using class declarations from STYLE;
- `examples/style-class-basic/render-gdi.bmp` — experimental GDI render using class declarations from STYLE;
- `examples/table-basic/index.lht` — first table layout example;
- `examples/table-basic/render.bmp` — bitmap render for equal-width table cells;
- `examples/table-basic/render-gdi.bmp` — experimental GDI render for equal-width table cells;
- `lht-mini-token-table.md` — temporary DOC/DOM/STYLE/ATTR/VALUE mini dictionaries and command table;
- `lht-mini-syntax.md` — source syntax accepted by the current mini parser;
- `tools/lhtc/lhtc.lpr` — console utility entry point;
- `tools/lhtc/src/LhtCli.pas` — CLI commands;
- `src/LhtDom.pas` — normalized tree model;
- `src/LhtParser.pas` — minimal text `.lht` parser;
- `src/LhtValidation.pas` — shared mini parser/style validation rules;
- `src/LhtDump.pas` — normalized tree dump;
- `src/LhtTokenTable.pas` — stream-aware mini token dictionary;
- `src/LhtStyle.pas` — minimal class style parser and stylesheet model;
- `src/LhtTokenDump.pas` — symbolic token stream dump;
- `src/LhtBinaryEncode.pas` — mini binary encoder;
- `src/LhtBinaryDecode.pas` — mini binary decoder;
- `src/LhtBinaryDump.pas` — disassembly-style binary dump;
- `src/LhtRenderTypes.pas` — render-side canvas, glyph, and text-metrics abstractions;
- `src/LhtCanvasBmp.pas` — headless 24-bit BMP canvas backend;
- `src/LhtCanvasGdi.pas` — experimental Win32 GDI canvas and text metrics backend;
- `src/LhtDebugFont.pas` — built-in 5x7 debug font with semantic size metrics;
- `src/LhtRender.pas` — mini DOM layout traversal using abstract canvas/text interfaces and baseline-aware line boxes.

Current `lhtc` commands:

```text
lhtc parse       examples/minimal/index.lht
lhtc dump        examples/minimal/index.lht
lhtc tokendump   examples/minimal/index.lht
lhtc tokendumpfile examples/minimal/index.lht examples/minimal/token.dump
lhtc encode      examples/minimal/index.lht examples/minimal/index.lhb
lhtc decode      examples/minimal/index.lhb
lhtc decodedump  examples/minimal/index.lhb examples/minimal/decoded.dump
lhtc bintokendump examples/minimal/index.lhb
lhtc bindump     examples/minimal/index.lhb
lhtc bindumpfile examples/minimal/index.lhb examples/minimal/binary.dump
lhtc render      examples/minimal/index.lht examples/minimal/render.bmp
lhtc rendergdi   examples/font-basic/index.lht examples/font-basic/render-gdi.bmp
lhtc checkminimal
lhtc checkexample examples/class-basic
lhtc checkvalidation
lhtc checkall
```

The implemented mini source surface is intentionally tiny:

- `lhtml`, `head`, `title`, `meta`, `body`;
- `style` with flat `.class { attr=value }` declarations;
- `block`, `row`, `spacer`;
- `table`, `col`, `tr`, `td` with equal-width columns and per-cell box styling;
- inline text inside text-hosting blocks;
- bare `<p>` and `<br>`;
- `span` and `a`;
- attributes: `id`, `version`, `name`, `content`, `width`, `height`, `href`,
  `fontFace`, `fontSize`, `color`, `background`, `border`, `padding`,
  `borderWidth`, `class`;
- no images/resources;
- no forms;
- no scripts;
- varint, `START`, `END`, `COMMAND`, `INLINE_VALUE`, `INLINE_BYTE`;
- `IMPORT dict,count`;
- `BODY_BEGIN`;
- separate imported DOC, DOM, STYLE, ATTR, and VALUE mini dictionaries.
- first debug bitmap rendering of the current DOM subset.
- renderer split into layout traversal, text metrics/font source, and canvas backend.
- semantic `font` shorthand normalized into canonical `fontFace` and `fontSize`.
- baseline-aware inline line boxes using max ascent/descent across text runs.
- experimental Win32 GDI render backend with real font metrics.
- typed RGB565 `color` values for `color`, `background`, and `border`.
- resolved box visual attributes for padding and border width.
- resolved text/box attribute path with class names preserved for future style declarations.
- stream-local imports that persist per document; shared ATTR/VALUE dictionaries are imported into streams that need them.
- first STYLE stream class declarations with inline DOM attributes overriding class attributes.
- parser validation for mini element names, attribute names, basic typed values,
  bare-tag closing errors, document root shape, and flat class style text.
- first table rendering slice with `col* tr*` structure, row height equal to the
  tallest cell, and no border-collapse model.

The binary stream is now a fully tokenized mini stream. It imports DOC and shared ATTR dictionaries at file start, emits DOC structure, switches through `BODY_BEGIN`, imports DOM plus shared ATTR/VALUE dictionaries for the DOM stream, and then emits the DOM root `body`. Imports are stream-local but persist for the document; entering a stream selects its token table rather than resetting it.

Remaining cleanup for this slice:

- refine parser validation for allowed child-element relationships beyond the
  current document-level checks;
- decide whether generated `.lhb` files remain committed fixtures long-term or become generated test artifacts after the corpus grows.

Recommendation:

Keep this slice small and stable. Use it as the baseline compatibility fixture before adding more vocabulary.

---

## 2. Vocabulary Inventory

A vocabulary inventory is still useful, but it should be maintained incrementally rather than completed before implementation.

Current draft:

```text
lht-vocabulary-v1.md
```

Use it as a living checklist:

- add entries only when they are implemented, specified in detail, or needed by examples;
- avoid adding HTML-like terms just because they are familiar;
- mark uncertain items as `candidate`;
- remove entries that are known not to be part of LHT;
- keep cleanup decisions explicit.

Recommendation:

Treat the vocabulary as generated design memory, not as the primary driver. It should follow the implementation slice.

---

## 3. Tokenization And Standard Dictionaries

Tokenization connects the source syntax, binary stream, parser, decoder, and future runtime implementations. A temporary mini dictionary now exists in code and documentation, but final dictionaries should still come after several working examples reveal real token frequency and context boundaries.

The eventual concrete artifact should be:

```text
lht-standard-dictionaries-v1.md
```

Current mini dictionaries:

| Dictionary | ID | Scope | Status |
|---|---:|---|---|
| `DICT_DOC_MINI` | `1` | `lhtml`, `head`, `title`, `meta` | implemented |
| `DICT_DOM_MINI` | `2` | `body`, `block`, `row`, `spacer`, `table`, `col`, `tr`, `td`, inline commands/runs | implemented |
| `DICT_STYLE_MINI` | `3` | initial style stream structural commands | reserved/implemented in token table |
| `DICT_ATTR_MINI` | `4` | shared DOC/DOM/STYLE attribute and property names | implemented |
| `DICT_VALUE_MINI` | `5` | shared enum value tokens | implemented |

Eventual standard dictionaries:

| Dictionary | Purpose |
|---|---|
| `DOC_CORE_V1` | document-level section markers, metadata, resource/script manifest records |
| `DOM_CORE_V1` | common elements, structural DOM commands, common DOM values |
| `ATTR_CORE_V1` | common attributes if attributes are split from DOM elements |
| `STYLE_CORE_V1` | core style properties, style commands, frequent style values |
| `EVENT_CORE_V1` | event names and event binding vocabulary |
| `LJS_CORE_V1` | script keywords, operators, punctuation, bytecode opcodes, core builtins |

Possible future `DOM_CORE_V1` entries:

```text
body
block
p
span
a
img
br
row
flow
spacer
ul
ol
li
table
col
tr
td
h1
h2
h3
```

Possible future core attributes:

```text
id
class
style
src
href
alt
title
width
height
align
valign
name
value
type
role
```

Each dictionary should define:

- numeric `dict_id`;
- symbolic name;
- version;
- ordered entries;
- reserved ranges;
- compatibility rule;
- whether entries are grammar tokens, values, commands, or enum values.

Open design detail:

- decide numeric `dict_id` ranges for standard, experimental, vendor-specific, and private dictionaries;
- decide whether attributes live in `DOM_CORE_V1` or in a separate `ATTR_CORE_V1`;
- decide whether frequent enum values live near the attributes that use them or in separate value dictionaries.

Recommendation:

Keep using the temporary mini token table while the implementation grows. Promote it to `lht-standard-dictionaries-v1.md` only after several examples can round-trip and token frequency starts to matter.

---

## 4. Text LHT Grammar

The text form should be specified enough that an encoder is not forced to invent syntax rules while being written.

The next artifact could be:

```text
lht-text-syntax.md
```

It should define:

- tag syntax;
- closing tags;
- self-closing syntax, if any;
- command-like bare tags such as `<p>`;
- attribute syntax;
- boolean attributes;
- quoted and unquoted values;
- string escaping;
- comments;
- whitespace handling;
- text run boundaries;
- color syntax;
- number syntax;
- binary blob syntax through hex or base64;
- where `<style>`, `<script>`, and document metadata are allowed;
- source-level to typed-value conversion.

Important rule to keep explicit:

`<p>` is not a block container in the current model. It is a paragraph separator/paragraph command. Examples may and should use it, but not as `<p>...</p>`.

Recommendation:

Keep the source grammar friendly, but keep the normalized internal model strict. The source can be ergonomic; the binary stream should be unambiguous.

---

## 5. Binary Stream Grammar

The binary encoding document defines byte forms. A separate grammar should define which sequences are legal.

The next artifact could be:

```text
lht-binary-stream-grammar.md
```

It should describe structures such as:

```text
Document    = Preamble Section* END
Section     = BODY_BEGIN DomStream | STYLE_BEGIN StyleStream | SCRIPT_BEGIN ScriptStream
DomStream   = DomPreamble RootNode END
RootNode    = START Element Attr* Content* END
Element     = token
Attr        = attrToken AttributeValue
Content     = Node | TextItem | InlineValue | Command
Node        = START Element Attr* Content* END | Element Attr*
```

The grammar needs to answer:

- when attributes end;
- whether attributes may appear after content begins;
- where `INLINE_VALUE USE` is legal;
- how text runs are represented;
- where `IMPORT`, `PIN_LIST`, `PIN_USE`, and `TEXT_CODEC` are legal;
- whether `TEXT_CODEC` may change inside a document;
- how unknown dictionaries and unknown tokens are skipped;
- which errors are fatal.

Recommendation:

Keep binary grammar deterministic and stack-based. Avoid requiring dictionary lookup just to know whether a stream item changes nesting depth.

---

## 6. Text Storage And LZSS4K

Text run compression is useful when many visible text fragments are aggregated into one text stream. The current direction is `LZSS4K`.

The remaining design work:

- decide how DOM content items refer to aggregated text;
- decide whether text storage is sequential or offset-based;
- decide whether text is compressed as one large block or as chunks;
- define compressed block headers;
- define uncompressed length storage;
- define fallback for unsupported text codecs;
- decide whether rendering may start before the full text stream is decompressed.

Recommendation:

Use chunked text storage rather than one monolithic compressed block. A chunk can carry:

```text
codec
compressedLength
rawLength
payload
```

This is friendlier to memory-limited clients and streaming decoders. Even if the first implementation loads everything, the format will not force that forever.

---

## 7. STYLE Representation

The main open architectural question is how much of `STYLE` should be structural records instead of a tokenized CSS-like grammar.

Options:

| Model | Pros | Cons |
|---|---|---|
| CSS-like token grammar | Familiar authoring model, flexible | More parser work on weak clients |
| Structural style records | Fast to decode, compact, validation-friendly | Less expressive, less CSS-like |
| Hybrid | Core stays simple, extensions remain possible | More design surface |

Recommendation:

Use a hybrid model, but make v1 structural.

Example direction:

```text
CLASS "hero"
  SET color color
  SET background color
  SET margin-left length
  SET padding length4
END
```

The source text may still look CSS-like if that is convenient for authors, but the binary form should be normalized into simple property records. This matches the goal of fast decoding on weak hardware.

---

## 8. Typed Value Model

The current value model should be consolidated into one reference table.

For every value type, define:

- source syntax;
- binary encoding;
- canonical form;
- equality/comparison rule;
- whether it can be interned;
- whether it can appear as an attribute value;
- whether it can appear as content;
- whether it can be used in style records;
- error cases.

Types to include:

```text
uint
nint
color
name
string
text
float32
fixed16_16
colorEx
blob
```

Recommendation:

Make this part of the binary encoding document or a small companion file. Typed values are simple individually, but they become important once parser, tokenizer, style, script, and validation all touch them.

---

## 9. Reference Encoder And Decoder

**Status:** first minimal version implemented, with minimal fixture checking.

Implemented:

- parse a small subset of `.lht`;
- build a simple normalized tree;
- emit a binary LHT stream;
- read the binary stream back;
- dump tokens in a human-readable form;
- produce a disassembly-style binary dump;
- write token/disassembly dumps to fixture files;
- check the current minimal fixture set.

Current CLI shape:

```text
lhtc parse input.lht
lhtc dump input.lht
lhtc tokendump input.lht
lhtc tokendumpfile input.lht output.dump
lhtc encode input.lht output.lhb
lhtc decode input.lhb
lhtc decodedump input.lhb output.dump
lhtc bintokendump input.lhb
lhtc bindump input.lhb
lhtc bindumpfile input.lhb output.dump
lhtc render input.lht output.bmp
lhtc checkminimal
```

Recommendation:

Keep the implementation deliberately small. It should validate the format decisions, not become the full browser. Prefer token dumps, binary dumps, and round-trip checks before rendering.

---

## 10. Test Corpus

A corpus of small documents will keep the design honest.

Current case:

- `examples/minimal` — DOC import, BODY_BEGIN, DOM import, nested blocks, bare `<p>`, `<br>`, `span`, `a`, `INLINE_BYTE`, string/text inline values, binary fixture, decoded dump fixture, token dump fixture, binary disassembly fixture.
- `examples/layout-row` — multiple rows, fixed-width blocks, horizontal and vertical spacers, full-width block, narrow wrapped text block.
- `examples/font-basic` — source shorthand `font=face,size`, canonical `fontFace` and `fontSize`, inherited font attributes, inline size changes, semantic families.
- `examples/color-basic` — body background, block background, border color, inherited text color, inline color overrides, RGB565 color encoding.
- `examples/visual-box` — block padding, border width, border color, and nested inline text using resolved box geometry.
- `examples/class-basic` — `class` attribute preservation through parse, token dump, binary encode/decode, and render traversal.
- `examples/style-class-basic` — source `<style>` class declarations, binary `STYLE_BEGIN`, shared ATTR/VALUE imports in STYLE, and class-based rendering.
- `examples/table-basic` — `table`, `col`, `tr`, `td` tokens, equal-width columns, per-cell box styling, row height from the tallest cell, binary fixtures, and bitmap/GDI renders.

Suggested next cases:

- images;
- repeated classes;
- repeated strings;
- `INLINE_BYTE`;
- `uint` and `nint`;
- `float32` and `fixed16_16`;
- `colorEx`;
- blob from hex;
- blob from base64;
- text compression;
- unknown dictionary import;
- invalid dictionary count;
- undefined token reference;
- malformed varint;
- unterminated node.

Recommendation:

Add expected token dumps and binary disassembly dumps before adding byte-for-byte binary assertions. Human-readable dumps will be easier to maintain while the binary layout is still moving.

---

## 11. Compatibility Profiles

Profiles make feature support explicit and keep old clients from guessing.

Possible profiles:

| Profile | Meaning |
|---|---|
| `LHT_MINIMAL` | DOM, text, basic attributes, no style/script/media extensions |
| `LHT_STYLE` | structural style records |
| `LHT_SCRIPT` | script stream or bytecode |
| `LHT_MEDIA` | images, blobs, resource references |
| `LHT_COMPRESSED_TEXT` | aggregated text storage with supported text codecs |

Recommendation:

Define profiles as capability bundles, not as separate file formats. A document can declare required and optional capabilities.

---

## 12. Error Handling

Error behavior should be specified early because weak clients benefit from simple failure rules.

Cases to define:

- unknown command;
- unknown dictionary;
- unsupported required dictionary;
- known dictionary with impossible `count`;
- token reference to an undefined slot;
- unknown value type;
- invalid varint;
- integer overflow;
- invalid UTF-8;
- invalid color payload;
- unsupported text codec;
- compressed text length mismatch;
- blob too large;
- unterminated node;
- attributes after content begins;
- unexpected `END`.

Recommendation:

Prefer simple fatal errors for malformed streams. Reserve graceful skipping for explicitly unknown but well-formed optional features.

---

## 13. Suggested Order

Recommended sequence:

1. Add the next smallest feature slice as a new focused example.
2. Expand renderer coverage feature by feature: table refinements, forms, images, styles, scripts, compression.
3. Keep tightening parser and binary validation when each slice adds new grammar.
4. Update vocabulary, grammars, and standard dictionaries from the working slice.

The minimal fixture set, mini syntax note, first bitmap render, focused layout examples, semantic font attributes, baseline-aware line boxes, experimental GDI backend, first display-list renderer path, basic color attributes, style class declarations, parser validation checks, and first table slice are now in place. The next architectural pressure points are table refinement, forms, images, and keeping the layout/paint boundary strict as features are added.

---

## 14. Layout Display List

Implemented in the reference tool as the first layout/paint boundary:

```text
src/LhtDisplayList.pas
src/LhtRender.pas
src/LhtRenderTypes.pas
src/LhtCanvasGdi.pas
```

The renderer now computes block positions and inline line boxes into a display
list first, then paints that list through the selected backend.

Target pipeline:

```text
DOM + resolved attributes
  -> layout stage
  -> display list
  -> paint stage
  -> backend surface
```

The current command set is deliberately small:

```text
FillRect   owner originX originY x y w h color
StrokeRect owner originX originY x y w h color
TextRun    owner originX originY x baselineY text fontFace fontSize color
```

Future commands:

```text
Image      x y w h imageRef
ClipPush   x y w h
ClipPop
```

Important details:

- each command keeps a reference to the DOM owner node;
- command coordinates are local to the owner block, with `originX/originY`
  supplied separately for full-page paint;
- text commands store local `baselineY`, not top-y;
- line boxes keep `ascent` and `descent` as layout data;
- render backends do not reflow text;
- GDI renders a full `TextRun` with `TextOut`;
- debug bitmap rendering falls back to drawing glyphs run by run;
- interactive browsers can repaint from the display list without recalculating layout;
- a changed block can later be repainted by filtering display commands by owner;
- dirty-rect repaint and layout inspection become much easier;
- layout dumps can become fixtures later.

Implemented types:

```text
TLhtDisplayCommandKind = (dckFillRect, dckStrokeRect, dckTextRun)
TLhtDisplayCommand = record ...
TLhtDisplayList = class ...
```

`TLhtCanvas.DrawTextRun` is the backend boundary. The base implementation draws
glyphs through `DrawGlyph`; the GDI backend overrides it and calls `TextOut` once
per run. `TLhtDisplayList.PaintOwner` can replay only commands that belong to one
DOM node, which is the first hook for block-level repaint.

Recommendation:

Keep the first display list deliberately small. It only needs rectangles and text
runs to replace the current renderer path. Images, clipping, palettes, alpha, and
debug overlays can be added after the core boundary is proven.

---

## 15. Reference Code And Specification

There is a useful version of "the code becomes the specification": a small, readable, intentionally boring reference implementation can clarify edge cases better than prose alone.

This is good when:

- the written spec defines the model and invariants;
- the reference code is explicitly labeled as reference behavior;
- token dumps and corpus tests make behavior visible;
- differences between prose and code are treated as spec bugs to resolve;
- the code is small enough to audit.

It is bad when:

- accidental parser behavior becomes normative;
- bugs become compatibility requirements;
- undocumented edge cases are discovered only by reading implementation details;
- later implementations must imitate quirks instead of following a clean model;
- performance shortcuts obscure the intended semantics.

Recommendation:

Use three layers:

1. **Normative documents** define the format, grammar, and required behavior.
2. **Reference implementation** demonstrates the intended interpretation.
3. **Test corpus** decides practical compatibility by checking observable input/output behavior.

In other words: code should not silently replace the spec, but it should be allowed to pressure-test it. The healthiest loop is:

```text
spec draft -> reference code -> corpus tests -> spec corrections
```

That gives the project the benefits of executable truth without letting implementation accidents become the language.
