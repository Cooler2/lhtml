# Light HyperText Format (LHT) — Specification Draft

**Version:** 0.1 (draft)
**Status:** Work in progress
**Target audience:** Implementers, document authors, server developers

---

## Table of Contents

1. [Overview and Philosophy](#1-overview-and-philosophy)
2. [Stream Representation](#2-stream-representation)
3. [Document Model](#3-document-model)
4. [Layout](#4-layout)

(Sections 5-10 to follow: Resources & Images, Fonts, Events, Scripts, Network, Content Negotiation)

---

## 1. Overview and Philosophy

### 1.1 What LHT is

LHT is a binary document format for hypertext content, designed to be:

- **Compact** on the wire
- **Trivial to parse** even on constrained hardware (286-class and up)
- **Deterministic** in layout, within practical bounds
- **Reversible** to a human-readable text form
- **Tractable** in implementation — a complete parser fits in single-digit kilobytes of code

LHT is *not* HTML. It does not aim for HTML parity, semantic richness, or compatibility with the modern web platform. It is a clean-slate format inspired by the question: "If we designed a hypertext format today, knowing what we know, with constrained clients as a first-class target — what would it look like?"

### 1.2 Design principles

These principles guide every decision in the specification. Where principles conflict, earlier ones win.

**P1. Simplicity of the client.** The reference client should be implementable in a few thousand lines of code. The bytecode interpreter, layout engine, and parser should all be small and easily auditable. This is the first principle because it determines what's possible on the target hardware.

**P2. Predictability over flexibility.** The same document should produce essentially the same result on every conforming client. Small typographic variations are acceptable; structural variations (column counts, element overlap, content cutoffs) are not.

**P3. One way to do it.** Where the format admits multiple ways to express the same intent, the specification picks one and forbids the others. This applies to attributes (no `style=` parallel to attributes), encoding (UTF-8 only), units (one per dimension type), and so on.

**P4. The author writes once; the client adapts.** Documents declare logical intent (font sizes by name, colors by role, image variants with conditions). Clients select the concrete realization based on capabilities. Authors do not write per-client code paths.

**P5. The format is reversible.** A tokenized document can be losslessly converted to canonical text, and vice versa, modulo whitespace and comments. This makes "View Source" trivial and enables text-based authoring.

**P6. The server can be dumb.** A trivial HTTP server serving static files is a conforming server. Tokenization, validation, and bytecode compilation are optimizations, not requirements.

**P7. The client can be small.** A minimal client that only displays static documents (no scripts, no network) is a conforming client. Features beyond the minimum are negotiated.

### 1.3 Target environments

LHT is designed to run across a wide range of hardware, from constrained vintage systems to modern hardware. Concrete reference targets:

| Class | CPU | RAM | Display | Capabilities |
|---|---|---|---|---|
| Minimal | 286 | 640K | EGA 16c | Static documents, basic forms |
| Standard | 386 | 1-4M | VGA 256c | + scripts, AJAX, JPEG |
| Enhanced | 486+ | 4M+ | SVGA 16-bit | + native compilation, full features |

A conforming client identifies its class via content negotiation; servers and authors adapt accordingly.

LHT also runs on modern hardware as a minimalist alternative to HTML, but that is not its primary design target.

### 1.4 What's deliberately not in LHT

To maintain focus, several common web features are explicitly out of scope:

- **CSS animations and transitions.** Static layout only.
- **Complex selectors.** No `:nth-child`, descendant selectors, etc. Classes only.
- **Floats.** Layout uses only the five container types defined in Section 4 (plus the `table` element for tabular data).
- **Margins.** Spacing between elements is expressed with `<spacer>` and `padding` (Section 4).
- **WebGL, audio, video.** Out of scope for v1.
- **Canvas** is in v1 but with a defined minimal subset for constrained clients (see Section 4.10).
- **Real-time push (WebSocket).** Polling via AJAX is sufficient.
- **Web fonts in TrueType/OpenType.** Bitmap fonts only (Section 6).
- **Same-origin policy as a network barrier.** Isolation is data-based, not network-based.

These omissions are not technical limitations of the format — they are choices that keep the implementation tractable on the target hardware.

---

## 2. Stream Representation

### 2.1 Encoding fundamentals

An LHT document is a stream of bytes. The stream is parsed by a state machine that consumes one **token** at a time. A token is a variable-length unsigned integer (varint) that identifies either a built-in language element, a custom dictionary entry, or a control command.

#### 2.1.1 Varint encoding

Varints use the byte-tag continuation scheme:

- A byte with high bit `0` (`0x00..0x7F`) is the final byte of the varint.
- A byte with high bit `1` (`0x80..0xFF`) has the lower 7 bits as data and indicates more bytes follow.

| Value range | Bytes | Encoding |
|---|---|---|
| 0..127 | 1 | `0xxxxxxx` |
| 128..16383 | 2 | `1xxxxxxx 0xxxxxxx` (LSB first) |
| 16384..2097151 | 3 | `1xxxxxxx 1xxxxxxx 0xxxxxxx` |
| ... | ... | ... |

**Rationale.** This encoding is trivial to decode (mask, shift, test continuation bit) and gives the most common values single-byte representation. The little-endian-style ordering (LSB first) is chosen because it's marginally simpler to decode in a forward-only stream.

A reference decoder in 8086 assembly:

```
read_varint:
    xor   bx, bx          ; result = 0
    xor   cl, cl          ; shift = 0
.loop:
    lodsb                 ; al = next byte, si advances
    mov   dl, al
    and   dl, 0x7F        ; data bits
    movzx dx, dl
    shl   dx, cl          ; shift to position
    or    bx, dx
    add   cl, 7
    test  al, 0x80        ; continuation?
    jnz   .loop
    ret                   ; result in bx
```

Roughly 12 instructions, 25-30 cycles per varint on a 286.

#### 2.1.2 Token namespaces

Tokens are partitioned into ranges by purpose. The exact ranges are defined by the bundle system (Section 2.4), but conceptually:

| Range | Purpose |
|---|---|
| 0x00 | Reserved (null token) |
| 0x01..0x1F | Stream control commands |
| 0x20..0x7F | Built-in elements/attributes (frequent) |
| 0x80..0x3FFF | Built-in elements/attributes (less frequent) and bundle entries |
| 0x4000..0x1FFFFF | Document-local custom dictionary entries |

The exact assignment is per-bundle; bundles are versioned (Section 2.4).

### 2.2 Stream structure

A complete LHT document has the following top-level structure:

```
[MAGIC: 4 bytes]
[VERSION: varint]
[BUNDLES_USED: varint count, then varint id+version pairs]
[DOC_STREAM: typed substream sequence]
```

The DOC stream contains typed substreams in document order:

```
DOC_STREAM
  STYLE_BEGIN  ... END   ; style declarations (optional, may repeat)
  BODY_BEGIN   ... END   ; the visible content tree (required, exactly once)
  SCRIPT_BEGIN ... END   ; scripts (optional, may repeat)
END
```

#### 2.2.1 Magic

The first four bytes identify the stream type:

- `'LHT1'` (0x4C 0x48 0x54 0x31) — LHT document
- `'LHC1'` — LHT compiled (server-tokenized output of the canonical text form)
- `'LJS1'` — LHT Script (standalone bytecode-compiled script)
- `'LRS1'` — LHT Resource bundle (e.g., shared dictionaries)

#### 2.2.2 Version

A single varint indicating the format version. Version 1 is described by this document. Clients reject streams with unrecognized versions.

#### 2.2.3 Bundles used

Declares which built-in token bundles this document relies on. Each entry is a `(bundle_id, version)` pair. The client must support all declared bundles or reject the document.

Example: `[2, 1, 0x0001, 5, 1, 0x0002, 3]` means "two bundles used: bundle 1 version 5, and bundle 2 version 3."

#### 2.2.4 Substream preambles

Each substream begins with an optional preamble of dictionary-setup commands before its first structural token. The preamble may contain: bundle activations (`ADD_DICTIONARY`), token priority declarations (`PIN`), user-defined name bindings (`DEFINE`), and string or constant definitions (Section 2.3).

The preamble ends when the first structural token (such as `START`) is encountered.

**String constants are not required up front.** Strings may also be introduced inline within any substream via the `RAW_TEXT` and `RAW_TEXT_SAVE` commands (Section 2.3). This allows a streaming encoder to emit strings as they are encountered without buffering the entire substream.

#### 2.2.5 Document body (BODY substream)

The document's visible content tree is encoded in the BODY substream. The substream is opened by `BODY_BEGIN`, a DOC-level command that switches the decoder into DOM mode and resets the token table for the DOM grammar.

After any preamble, the first structural token in the BODY substream is `START body`. This is the root DOM node; it may carry attributes such as `class`. The entire visible tree is enclosed between this `START body` and its matching `END`, which also ends the substream.

`BODY_BEGIN` and `START body` are distinct: the former switches the stream decoder; the latter opens the root element at the DOM level.

### 2.3 Declaration commands and inline strings

Declaration commands define dictionary entries. Most appear in the declaration phase at the start of the stream; two — `RAW_TEXT` and `RAW_TEXT_SAVE` — may appear anywhere a string value is expected.

| Command | Operands | Purpose |
|---|---|---|
| `DICT_DEFINE_STRING` | `[token: varint] [length: varint] [bytes...]` | Defines a UTF-8 string bound to the token (declaration phase) |
| `DICT_DEFINE_INT` | `[token: varint] [value: varint]` | Defines an integer constant (declaration phase) |
| `DICT_DEFINE_COLOR` | `[token: varint] [rgb: 3 bytes]` | Defines a color constant (declaration phase) |
| `DICT_DEFINE_ALIAS` | `[token: varint] [aliased_token: varint]` | Defines a token as an alias (declaration phase) |
| `DICT_LOAD_BUNDLE` | `[bundle_id: varint] [version: varint]` | Activates a built-in bundle (declaration phase) |
| `RAW_TEXT` | `[length: varint] [bytes: UTF-8]` | Inline string used once, not saved (anywhere a string is expected) |
| `RAW_TEXT_SAVE` | `[token: varint] [length: varint] [bytes: UTF-8]` | Inline string, saved to dictionary under given token (anywhere) |

#### 2.3.1 Inline strings (`RAW_TEXT` / `RAW_TEXT_SAVE`)

Wherever a string-typed value is expected (an attribute value, a text content node, etc.), the parser may encounter:

- A normal token, which references a dictionary entry, **or**
- `RAW_TEXT` followed by length and UTF-8 bytes, **or**
- `RAW_TEXT_SAVE` followed by a token id, length, and UTF-8 bytes.

`RAW_TEXT_SAVE` both provides the string value at that position *and* binds it to the given token for subsequent references. This is functionally equivalent to a `DICT_DEFINE_STRING` followed by a reference, but emitted inline.

**Rationale.** A purely up-front dictionary forces the tokenizer to make all decisions about which strings are worth caching before emitting any output. For long or dynamically-generated documents this requires buffering the entire content. Inline `RAW_TEXT_SAVE` allows a tokenizer to make these decisions lazily: a string seen for the first time is emitted as `RAW_TEXT_SAVE` (paying a small overhead in case it recurs), and subsequent occurrences are 1-2 byte token references.

A trivial single-pass tokenizer may use only `RAW_TEXT` (never reusing strings) — it is still a conforming tokenizer, just less compact. A more sophisticated tokenizer chooses between `RAW_TEXT` and `RAW_TEXT_SAVE` based on a frequency heuristic.

#### 2.3.2 Parser dispatch for string-valued positions

When the parser expects a string value, it reads a token and dispatches:

```
parse_string_value():
    t = read_token()
    if t == RAW_TEXT:
        len = read_varint()
        return read_bytes(len)
    elif t == RAW_TEXT_SAVE:
        new_token = read_varint()
        len = read_varint()
        bytes = read_bytes(len)
        dictionary[new_token] = StringEntry(bytes)
        return bytes
    else:
        entry = dictionary[t]
        assert entry.type == STRING
        return entry.value
```

#### 2.3.3 Why no inline forms for non-string types

`RAW_*_SAVE` is provided only for strings, not for integers, colors, or other types. Two reasons:

1. **Strings dominate document content** — they are the long, recurring data that benefits most from inline emission and dictionary reuse. Other types are short and often appear in stable, themed sets (a few colors, a few sizes), best declared up front.
2. **Each inline form is an extra branch in the parser's hot path.** Limiting inline data to a single type keeps the dispatch logic minimal.

Non-string constants are declared in the declaration phase or via `<const>` declarations in the document head (Section 3.3).

### 2.4 Bundles

A bundle is a versioned set of token-to-meaning bindings, baked into client implementations. Bundles eliminate the need to define common terms in every document.

#### 2.4.1 Bundle structure

Each bundle has:

- A unique numeric ID
- A version number (incremented on changes)
- A set of token assignments — each token in the bundle has a fixed meaning, value, and type

Bundles are append-only across versions: version N+1 may add new tokens but must not redefine or remove existing ones. This guarantees backward compatibility within a major bundle ID.

If incompatible changes are needed, a new bundle ID is created.

#### 2.4.2 Standard bundles

The following bundles are standard (clients should support them by default):

| ID | Name | Contents |
|---|---|---|
| 1 | `core-elements` | Container element tokens (block, flow, row, fixed, scrollbox), table elements (table, col, tr, td), leaf elements (text, img, spacer, etc.) |
| 2 | `core-attributes` | Common attributes (width, height, padding, color, font, onClick, etc.) |
| 3 | `layout-values` | Common values (auto, fill, inherit, true, false, none) |
| 4 | `system-colors` | Named system colors (window, text, button-face, highlight, etc.) |
| 5 | `system-fonts` | Logical font names (default-sans-12, default-mono-10, etc.) |
| 6 | `event-types` | Event names (click, keydown, focus, etc.) |
| 7 | `script-runtime` | Script built-in function tokens (get-element, fetch, storage-get, etc.) |
| 8 | `mime-types` | Common MIME type strings |

Specific token assignments within each bundle are defined in a separate appendix (TBD).

#### 2.4.3 Custom bundles

Documents may reference custom bundles loaded via external resources. A common use case is per-site shared dictionaries — see Section 10 (Content Negotiation) for cache semantics.

### 2.5 Node structure

The DOM stream uses two meta-tokens to describe tree structure:

- `START` — precedes a content-bearing element token; the element must be closed by a matching `END`.
- `END` — closes the innermost open `START`, or ends the current substream when the open depth reaches zero.

A bare element token (one not preceded by `START`) is self-closing: it reads attributes and immediately returns to the parent context. No `END` is emitted or expected.

Attributes appear immediately after the element token, before any child content. The first non-attribute token signals the transition out of attribute context:

- For `START element`: the first non-attribute token is a child element or text content.
- For a bare element token: the first non-attribute token is consumed by the parent context.

Example:

```
START block
  ATTR class hero
  START p
    ATTR class muted
    TEXT_RUN "Hello"
  END
  img
    ATTR name logo
    ATTR width 96
END
```

`img` is a bare token — no `START` prefix, no stack frame, no `END`. The `END` at the bottom closes `block`.

**Why START/END instead of child counts?** Child counts require the encoder to know the number of children before writing the node header, or to buffer the subtree and backpatch the count. Backpatching is especially awkward with variable-length integers. `START`/`END` with bare self-closing tokens allows true one-pass streaming encoding with no backpatching.

**Stream self-description.** Whether an element is self-closing is explicit in the stream: presence or absence of the `START` meta-token. The decoder does not need a dictionary lookup to determine whether a matching `END` is expected. The tree structure can be reconstructed with no knowledge of element semantics.

**Skip algorithm for unknown subtrees:**

```
depth = 1
while depth > 0:
  item = readItem()
  if item is START: read element token; depth++
  if item is END:   depth--
  else:             skip attributes only  ; bare element token
```

Bare tokens do not affect depth. Their attributes are terminated by the first non-attribute token, which is returned to the skip loop. Raw payloads carry explicit byte lengths so they can be skipped without parsing their content.

**Streaming render.** This model permits streaming render: a client may begin laying out and rendering the document tree as tokens arrive, without buffering the full document. Together with `RAW_TEXT_SAVE` (Section 2.3.1), this allows a single-pass encoding server to produce output incrementally. Streaming render is optional; a minimal client may buffer the full document before rendering.

#### 2.5.1 Attribute encoding

Attributes are encoded with `ATTR` commands immediately after the `START` or `VOID` command of their element:

```
ATTR attr_token value
```

`attr_token` identifies the attribute (from a DOM bundle). `value` is a token reference, a raw literal (`RAW_INT`, `RAW_COLOR`, `RAW_STRING`), or an inline definition command. For structured attribute values (e.g., `border: width, color`), multiple value tokens follow in the fixed order defined by the attribute.

Example: `<button width=100 bgColor=blue>Send</button>` becomes:

```
START button
  ATTR width   RAW_INT 100
  ATTR bgColor ENUM blue
  TEXT_RUN "Send"
END
```

Attribute context ends when the first non-`ATTR` token is encountered. For `START` elements that token begins child content; for `VOID` elements it is consumed by the parent context.

#### 2.5.2 Compact attribute forms

For common attribute patterns, compact command variants reduce stream size. They are aliases — same semantics as `ATTR`, fewer bytes:

- `ATTR_FLAG attr_id` — boolean flag attribute (e.g. `bold`, `disabled`); no value token
- `ATTR_INT8 attr_id value` — integer attribute with value 0–255, value encoded in one byte
- `ATTR_REF attr_id value_token` — attribute referencing a named constant, color, font, or enum value

Encoders prefer compact forms where applicable.

### 2.6 Compression

Compression is optional and negotiated. The format defines two compression modes:

- **None** — raw token stream
- **Huffman** — static Huffman coding using a frozen frequency table prebuilt from a corpus of typical documents

The Huffman table is part of the format specification and shipped with every conforming client. It is not transmitted per-document.

LZ-family compression is *not* used in the base format. Once tokenized, the stream has few byte-level repetitions (each common term is a 1-byte token, not a repeated string), so LZ provides little benefit relative to its decoder cost. Static Huffman is well-matched to the highly skewed token frequency distribution.

For very long documents where LZ might still help, content negotiation may activate optional secondary compression (TBD, future version).

---

## 3. Document Model

### 3.1 The unified attribute model

LHT does not distinguish between "structural attributes" (HTML's `width`, `colspan`) and "presentational attributes" (CSS's `width`, `color`). All attributes live in a single namespace and are set via the same syntax.

In the textual form:

```
<button width=100 background-color=blue padding=8 onClick=send>
  Send
</button>
```

There is no `style=` attribute. There is no separate CSS file required. (CSS-like declarations *are* available — they're called *classes* and *constants*, defined later — but they are not the only way to apply visual properties.)

#### 3.1.1 Why one namespace

Three reasons:

1. **Simplicity.** One parser, one mental model, one bundle of attribute tokens.
2. **Authoring.** Authors don't choose between two syntactically-different ways to do the same thing.
3. **Tokenization.** A unified attribute namespace gives a single Huffman frequency profile, which compresses better than two separate ones.

#### 3.1.2 Attribute value types

Each attribute has a defined value type. Valid types include:

| Type | Encoding | Examples |
|---|---|---|
| `int` | varint | `width=100`, `tabindex=2` |
| `length` | varint | `padding=8` (pixels) |
| `fraction` | varint, units of 1/256 | `width=128` means 50% (128/256) |
| `color` | 3-byte RGB or color-token reference | `color=#FF0000`, `color=highlight` |
| `font` | font-token reference | `font=default-serif-12` |
| `bool` | 0 or 1, or flag form | `disabled`, `bold` |
| `string` | string-token reference | `placeholder="Type here"` |
| `function` | function-token reference | `onClick=send` |
| `image` | image-token reference | `image=user-icon` |
| `enum` | one of a fixed set of value tokens | `align=center` |

The type of an attribute is fixed by the attribute's definition (in a bundle or custom dictionary). Mismatches are errors caught at tokenization time.

### 3.2 Elements

#### 3.2.1 Element categories

Every element has a category, which determines what kind of children it may contain and how it is encoded in the binary stream:

| Category | Children allowed | Binary encoding | Examples |
|---|---|---|---|
| `container` | other elements (typed by container type — see Layout) | `START element … END` | `block`, `row`, `grid`, `h1`, `h2`, `h3` |
| `inline` | text, inline elements, references | `START element … END` | `span`, `a`, `b`, `i` |
| `leaf` | none | bare `element` token | `img`, `input`, `spacer`, `col` |
| `text-break` | n/a — modifies paragraph state for subsequent text | bare `element` token | `p`, `br` |
| `meta` | declarations only | DOC-stream commands | `head`, `body`, `class-def` |

The category is fixed by the element's definition. Putting children into a `leaf` or `text-break` element is an error. In the binary stream, `leaf` and `text-break` elements are bare tokens — no `START` prefix, no matching `END`. `container` and `inline` elements are always preceded by `START` and closed by `END`.

`text-break` elements appear only inside text-hosting containers. They do not create a subtree — they modify the paragraph context for the text that follows, up to the next `text-break` or the `END` of the containing block.

#### 3.2.2 The document root

The root of every LHT document is an `lhtml` element. The `version` attribute identifies the format version and is required.

```
<lhtml version=1>
  <head>
    ; document metadata only (title, author, keywords, etc.)
  </head>
  <style>
    ; resource declarations, image definitions, constants, class definitions
  </style>
  <style src='theme.lss'>    ; external stylesheet (optional)
  <body>
    ; the visible content tree
  </body>
  <script src='app.ls'>      ; scripts execute after body is rendered
  <script>
    ; inline script
  </script>
</lhtml>
```

`<head>`, `<style>`, and `<script>` are optional; `<body>` is required. Multiple `<style>` and `<script>` elements are permitted and processed in document order. `<style>` elements must appear before `<body>`. `<script>` elements may appear before or after `<body>`; those placed after are deferred until after the initial render — the body is displayed first, then scripts execute.

In the binary form, the format is identified by the `LHT1` magic bytes and the version varint (Section 2.2). The `<lhtml version=N>` root serves the same purpose in the canonical text form.

### 3.3 Constants

Constants are named values defined in `<style>` blocks. They work like `#define` in C — resolved at tokenization time by value substitution. Constants have no declared type; the type is inferred from the value's syntax and validated at the point of use.

#### 3.3.1 Definition

Constants are declared with the `const` keyword inside a `<style>` block:

```css
const primaryColor   = #3080C0;
const defaultPadding = 8;
const cardFont       = default-serif-12;
```

The effective type is inferred from the value:

| Value syntax | Effective type |
|---|---|
| `#RGB` or `#RRGGBB` | color |
| Integer (optionally followed by a unit suffix) | length / int |
| `N%` | fraction (converted to N×256/100, rounded) |
| Logical font name | font |
| Another constant name | alias (same type as aliased constant) |
| Quoted string | string |

An optional alphabetic suffix after an integer (`px`, `em`, or any other) is accepted and silently ignored — it serves as author documentation only and has no effect on the value.

#### 3.3.2 Reference

Anywhere an attribute value is expected, a constant name may be used:

```
<block padding=defaultPadding bgColor=primaryColor>
  ...
</block>
```

Constants may also appear inside class definitions in `<style>` blocks (Section 3.8).

#### 3.3.3 Conditional values

A constant may have multiple variant values selected by client capabilities. The first matching clause is used; if none match, the constant is undefined and any reference to it is a tokenization error.

```css
const primaryColor {
  when(minDepth=8): #3080C0;
  when(minDepth=4): #1050A0;
}
```

The predicates inside `when()` are the same fixed set as in Section 5.6. Multiple predicates within one `when()` clause are combined with AND.

#### 3.3.4 Aliasing

A constant may alias another:

```css
const primaryColor = #3080C0;
const linkColor    = primaryColor;
```

Cycles are errors caught at tokenization time. Arithmetic on constants is not supported.

#### 3.3.5 System constants

A set of constants is always available, provided by the host environment:

- `systemWindow`, `systemText`, `systemButtonFace`, `systemButtonText`
- `systemHighlight`, `systemLink`, `systemVisitedLink`
- `systemScreenWidth`, `systemScreenHeight`, `systemColorDepth`

These may be used anywhere a constant name is accepted.

### 3.4 Classes

A class is a named bundle of attributes defined in a `<style>` block using CSS-inspired syntax. Elements reference classes by name.

#### 3.4.1 Definition

```css
.card {
  bgColor: #F0F4F8;
  padding: 12;
  border: 1, #AAAAAA;
}
```

Class names follow the `.name` convention inside `<style>` blocks; they are referenced on elements without the dot.

#### 3.4.2 Application

```
<block class="card">
  ...content...
</block>
```

Class attributes are applied as defaults. Attributes set directly on the element override class attributes.

#### 3.4.3 Multiple classes

```
<block class="card highlighted">...</block>
```

Classes are applied in listed order; later classes override earlier ones on conflicts. Element-level attributes override all classes.

#### 3.4.4 State variants

A class may declare attribute overrides for interactive states using the `:state` suffix:

```css
.button {
  bgColor: systemButtonFace;
  color: systemButtonText;
  padding: 4 12;
}

.button:hover    { bgColor: #DDECFF; }
.button:active   { bgColor: #AACCEE; }
.button:disabled { color: #999999; }
```

Supported state names: `hover`, `active`, `focus`, `disabled`. When the element enters that state, its state attributes override the base class attributes.

### 3.5 Inheritance

By default, attributes do not inherit from parent to child. Each element is fully described by its own attributes plus its classes.

A small set of attributes inherits by default for typographic continuity:

- `font` (and font-related: `bold`, `italic`)
- `color` (foreground)
- `lineHeight`
- `textAlign`

Other attributes may be explicitly inherited using the value `inherit`:

```
<block padding=inherit>...</block>
```

This list is intentionally short. Wider inheritance produces hard-to-debug action-at-a-distance behavior; the chosen subset reflects what's nearly always desired in practice.

### 3.6 The `head` section

The `head` element contains document metadata only. Recognized children:

| Element | Purpose |
|---|---|
| `title` | Document title |
| `meta` | Document metadata (author, language, description, keywords, cover image URL, etc.) |
| `link` | External references (shared dictionaries, etc.) |

Resource declarations, image definitions, font definitions, constants, and class definitions all belong in `<style>` blocks (Section 3.8), not in `<head>`. Scripts belong in `<script>` elements (Section 3.7).

All `<head>` and `<style>` content is fully processed before body rendering begins.

### 3.7 The `script` element

`<script>` elements contain or reference LHT Script code. They may appear before or after `<body>`. Scripts placed **after** `<body>` are deferred: the document body is rendered first, and only then are scripts parsed and executed. This is the recommended placement for scripts that don't need to run before the initial render.

```
<script src='main.ls'>         ; external script, deferred
<script>
  ; inline script code
</script>
```

Scripts placed **before** `<body>` execute before layout and render, blocking the pipeline at that point. Use lifecycle events (`onParsed`, `onLayout`, `onRendered`) to defer work to the appropriate phase (Section 8.10).

### 3.8 The `<style>` block

`<style>` blocks are the primary declaration context in LHT. They contain: resource declarations, image definitions, font definitions, constants, and class definitions — in a CSS-inspired syntax. They may appear between `<head>` and `<body>` (one or more), and optionally load an external stylesheet:

```
<style src='theme.lss'>         ; external stylesheet, no inline content
<style>
  ; inline declarations
</style>
```

External and inline `<style>` elements may be mixed freely. All `<style>` content is processed before body rendering begins.

Resources and image definitions are declared with `@resource` and `@imageDef` directives (Section 5). Font fallback chains use `@fontDef` (Section 6). Example of a self-contained stylesheet:

```css
@resource ui-atlas   gif  "/assets/atlas.gif" required;
@resource logo-large jpeg "/assets/logo.jpg";

@imageDef hero       src=logo-large;
@imageDef user-icon  src=ui-atlas  crop="0,0,16,16";
@imageDef send-btn   src=ui-atlas  crop="16,0,32,16";

const primaryColor = #3080C0;

.heading { font: default-sans-18; color: primaryColor; }
.card    { padding: 8; border: 1 #CCC; }
```

The dependency direction is always one way: the document body references names defined in `<style>` blocks; stylesheets never reference anything from `<head>` or `<body>`.

#### 3.8.1 Comments

Line comments start with `;` or `//`. Block comments use `/* ... */`.

#### 3.8.2 Padding shorthand

The `padding` property accepts 1–4 values following CSS conventions:

| Form | Meaning |
|---|---|
| `padding: 8` | all four sides = 8 |
| `padding: 4 8` | top+bottom = 4, left+right = 8 |
| `padding: 4 8 6` | top = 4, left+right = 8, bottom = 6 |
| `padding: 4 8 6 12` | top = 4, right = 8, bottom = 6, left = 12 |

Individual sides: `paddingTop`, `paddingRight`, `paddingBottom`, `paddingLeft`.

The same shorthand applies to the `padding` attribute when set directly on an element, using space-separated values inside quotes: `<block padding="4 8">`.

#### 3.8.3 Border shorthand

```css
border: 1, #AAAAAA;           /* all four sides */
borderTop: 2, #336699;
borderRight: 1, #AAAAAA;
borderBottom: 1, #AAAAAA;
borderLeft: 0;               /* remove left border */
```

The per-side properties `borderTop`, `borderRight`, `borderBottom`, `borderLeft` override the all-sides `border` when both are specified for the same class or element.

### 3.9 The `body` section

The `body` is the visible content tree. The body acts as an implicit `scrollbox` sized to the viewport: vertical content beyond the viewport height becomes scrollable as the document's main scroll. Body content is laid out as a `block` by default.

```
<body>
  <block class="header">...</block>
  <block class="main">...</block>
  <block class="footer">...</block>
</body>
```

Authors typically do not need to think about the body's container semantics; they place block content inside, and the document scrolls naturally.

**Binary encoding.** In the binary stream, `<body>` is represented at two distinct levels. At the DOC-stream level, the `BODY_BEGIN` command switches the decoder into DOM mode and resets the token table for the DOM grammar. Inside the BODY substream, the first structural token is `START body`, which is the root DOM node and may carry attributes such as `class`. `BODY_BEGIN` is a DOC-stream command; `START body` is the first DOM node. They are not the same token and operate at different abstraction levels.

---

## 4. Layout

LHT defines a deterministic flow-based layout with five fixed container types and a separate `table` element for tabular data. The layout algorithm is single-pass, top-down, and produces predictable results across conforming clients (within the soft tolerances of font metrics — see Section 6).

### 4.1 The box model

Every block element occupies a rectangular box with the following structure, from outside to inside:

```
+-------------------------------+
| BORDER                        |
|  +-------------------------+  |
|  | PADDING                 |  |
|  |  +-------------------+  |  |
|  |  | CONTENT           |  |  |
|  |  +-------------------+  |  |
|  +-------------------------+  |
+-------------------------------+
```

There is no margin in LHT. Spacing between sibling elements is expressed by inserting `<spacer>` elements (Section 4.7). Spacing inside an element is expressed by `padding`.

#### 4.1.1 Border placement

Borders are **cosmetic**: they are drawn on top of the element's content, along the inside of its outer edge, without affecting the layout dimensions. An element's `width` and `height` do not change when a border is added or removed.

This eliminates a class of layout surprises common in HTML/CSS, where adding a `border` causes content to reflow because the box becomes larger. It also means borders can be added or removed dynamically (e.g., for hover highlights, selection indicators, focus rings) without triggering reflow — a critical property for interactive content.

**Author guidance.** A border drawn directly over content can visually overlap the content's leading edge. Authors who want a visible gap between border and content set `padding ≥ borderWidth`. The spec does not enforce this; it is a style consideration.

**Border overlaps padding, not content.** A border of width *B* is rendered starting from the outer edge inward, overlapping the padding zone. The content area is determined solely by `outer_size − padding`; border width does not reduce it. This model is uniform — the same rule applies to all elements and table cells. An author who wants a visible gap between border and content ensures `padding ≥ border_width`; if `border_width > padding`, the border visually overlaps the content edge (by author choice).

```
outer edge
│←— border_width —→│←— padding − border_width —→│ content │
```

**Pixel placement at boundaries.** Each element renders its own borders within its own bounding rectangle. When two elements are adjacent, each renders its borders independently — they do not "merge" or coalesce. If element A has `borderRight=1` and adjacent element B has `borderLeft=1`, two adjacent pixels are drawn (one in A's bounding rect, one in B's). For tables and similar regular structures where shared single-pixel borders are desired, use the table-level border attributes (Section 4.7) rather than cell-level borders on both sides.

#### 4.1.2 Sizing rule

The `width` and `height` attributes specify the *outer* size of the box. Only padding is subtracted to determine the content area; border is cosmetic and does not affect it:

```
content_width  = outer_width  − padding_left − padding_right
content_height = outer_height − padding_top  − padding_bottom
```

A block declares its size honestly. If the block's declared or computed width is larger than the inner width of its parent's container, this is a layout overflow — see Section 4.5.

### 4.2 Container types

There are four block container types plus the `<table>` element. Each has a fixed layout algorithm. All block containers support the `overlay` attribute (Section 4.2.5).

#### 4.2.1 `block`

Children are laid out vertically, top to bottom. Each child's width defaults to the container's inner width (`width=fill`). The container's height is the sum of children's heights, unless overridden by an explicit `height` attribute.

`<div>` is a recognized alias for `<block>`. They are identical in all respects.

`<block>` and `<div>` are **text-hosting**: inline content (text, text modifiers, text runs, inline atoms) may be placed directly inside them without an explicit wrapper element. Paragraph breaks within text-hosting blocks are expressed with `<p>` and `<br>` commands (Section 7.2.1). See Section 7 for the full inline content model.

#### 4.2.2 `flow`

Children are laid out as if they were words in a paragraph: packed left-to-right, wrapping to the next line when they don't fit. Each line's children are aligned according to `textAlign` (left, center, right, justify). The line height equals the height of the tallest child on that line.

`flow` is the appropriate container for collections of small blocks (image galleries, tag clouds, button groups) where the author wants natural wrapping behavior.

A `flow` container's content always fits its width — children that don't fit on the current line wrap to the next.

`<flow>` is **not text-hosting** — its children must be block-level elements with defined widths.

#### 4.2.3 `row`

Children are laid out horizontally, left to right, in a single line (no wrapping). Each child's width is determined by:

- An explicit `width` attribute, or
- `width=auto` (use minimum size required by content), or
- `width=fill` (use remaining horizontal space, divided among `fill` children).

If the children's combined width exceeds the row's inner width, this is a layout overflow handled per Section 4.5.

The container's height is the height of the tallest child.

`<row>` is **not text-hosting** — its children must be block-level elements.

#### 4.2.4 `scrollbox`

A `scrollbox` is a container with a fixed size and a vertical scrollbar. It accepts `width` and `height` attributes; both are required.

The scrollbox's inner content area is `width − scrollbar-width` wide and unlimited in height. Children are laid out as in a `block` (vertically, top to bottom). When the total height of children exceeds the scrollbox's height, the scrollbar becomes active.

`scrollbox` is the only way to obtain vertical scrolling within a region of the document. Vertical scrolling of the document as a whole is handled by the viewport (the document body is, in effect, an implicit scrollbox of viewport size).

Horizontal scrolling within a scrollbox is not supported. For horizontal overflow handling, see Section 4.5.

**Why a separate container for vertical scroll?** Vertical and horizontal scrolling have asymmetric layout impact:

- A horizontal scrollbar appears at the bottom of an element and adds height; it does not affect width-dependent layout above it.
- A vertical scrollbar appears at the side and reduces the effective inner width, which would force content to reflow at a different width — incompatible with a single-pass layout algorithm.

By isolating vertical scroll to a dedicated container with explicit dimensions, the layout algorithm remains single-pass everywhere.

Whether `<scrollbox>` is text-hosting (can it directly contain inline content?) is an open question, deferred to a future revision. For now, treat its children as block-level.

#### 4.2.5 The `overlay` attribute

Any block element may carry the `overlay` attribute, which removes it from the normal document flow:

```
<div overlay x=20 y=10 width=200>
  Tooltip content here.
</div>
```

An overlay element:

- Is **not** a container type of its own — it is a positioning mode on any block element. An `<overlay>` block (`<div overlay>`) has the same internal layout as a regular `<div>`.
- Is positioned by `x` and `y` attributes relative to its **immediate parent's** content box origin (top-left corner). `x` and `y` are required when `overlay` is set.
- Is clipped to its immediate parent's content box.
- Does **not** contribute to the parent's layout — the parent's height and width are computed as if the overlay element were absent.
- Is rendered **after** all normal-flow siblings of the same parent, in DOM order. Multiple overlay elements in the same parent are drawn in declaration order, later ones on top.

Typical uses: tooltips, dropdown menus, popups, floating badges, game-style HUD elements.

#### 4.2.5 `scrollbox`

A `scrollbox` is a container with a fixed size and a vertical scrollbar. It accepts `width` and `height` attributes; both are required.

The scrollbox's inner content area is `width − scrollbar-width` wide and unlimited in height. Children are laid out as in a `block` (vertically, top to bottom). When the total height of children exceeds the scrollbox's height, the scrollbar becomes active.

`scrollbox` is the only way to obtain vertical scrolling within a region of the document. Vertical scrolling of the document as a whole is handled by the viewport (the document body is, in effect, an implicit scrollbox of viewport size).

Horizontal scrolling within a scrollbox is not supported. For horizontal overflow handling, see Section 4.5.

**Why a separate container for vertical scroll?** Vertical and horizontal scrolling have asymmetric layout impact:

- A horizontal scrollbar appears at the bottom of an element and adds height; it does not affect width-dependent layout above it.
- A vertical scrollbar appears at the side and reduces the effective inner width, which would force content to reflow at a different width — incompatible with a single-pass layout algorithm.

By isolating vertical scroll to a dedicated container with explicit dimensions, the layout algorithm remains single-pass everywhere.

### 4.3 Sizing values

Attributes that take a length or fraction value accept the following:

| Value | Type | Meaning |
|---|---|---|
| Integer | length | Absolute size in pixels |
| Fraction (0..256) | fraction | Fraction of parent's inner dimension, units of 1/256 |
| `auto` | — | Determined by content |
| `fill` | — | Remaining space (in `row`, `flow`, and `table` columns) |

Other CSS-style units (`em`, `vh`, `%` as separate from fraction, `calc()`) are not supported.

The fraction encoding (1/256) gives ~0.39% precision, sufficient for any practical layout. Authors typically use round values like 64 (25%), 128 (50%), 192 (75%), 256 (100%).

### 4.4 The `nowrap` attribute

By default, content in `flow` containers and inline text content may break between any two whitespace-separated tokens. Setting `nowrap` on an element prevents breaks within it: the element either fits entirely on the current line or wraps as a unit to the next.

```
<flow>
  Click <text nowrap>[icon] Send</text> to submit.
</flow>
```

### 4.5 Horizontal overflow

If a child block declares a width greater than its parent container's inner width, the parent applies an overflow strategy determined by the child's `overflowX` attribute.

| Value | Behavior |
|---|---|
| `clip` (default) | Content is rendered, but anything beyond the parent's inner width is clipped. The block's declared width is honored for layout calculations within the block, but outside the parent's bounds it is invisible. |
| `scroll` | A horizontal scrollbar is shown at the bottom of the block. The block renders its full declared width into a viewport equal to the parent's inner width, scrollable horizontally. |
| `auto` | Equivalent to `scroll` if the block's declared width exceeds the parent's inner width, otherwise equivalent to `clip`. |

#### 4.5.1 Why `overflowX` is on the child, not the parent

The child block "knows" its own desired width — it's a property of its own content (a wide table, a large image, a fixed-width diagram). Whether scrolling makes sense for this content is a property of *that block*, not of every place it might be embedded.

Two adjacent blocks may have different overflow strategies in the same parent: one shows a horizontal scrollbar for a wide data table, the next clips a fixed-width preview image. The parent does not need to coordinate these decisions.

This also means a wide block carries its overflow behavior with it across reuse: a block declared with `overflowX=auto` adapts naturally to any parent context, scrolling when narrow, displaying flush when wide enough.

#### 4.5.2 Rendering with horizontal scroll

Rendering a scrolling block does not require an off-screen buffer. The block's content is laid out at its natural width. At render time, the engine sets a clip rectangle equal to the parent's inner width, and renders the block's content with a horizontal offset equal to the negative of the current scroll position. Pixels outside the clip rectangle are not drawn.

```
render(scrolling_block, parent_inner_rect):
    clipRect = parent_inner_rect ∩ scrolling_block.outer_rect
    set_clip(clipRect)
    for child in scrolling_block.children:
        render_child_at(child, child.x - scrolling_block.scrollX, child.y)
    restore_clip()
```

A horizontal scrollbar is drawn within the parent's bounds, immediately below the scrolling block, adding `scrollbar-height` pixels to the block's effective vertical footprint.

#### 4.5.3 No `overflowY` attribute

There is no `overflowY` attribute. Vertical overflow is handled by the `scrollbox` container (Section 4.2.5) or by allowing content to extend the height of its parent (the default for `block`, where height is the sum of children's heights).

### 4.6 The `spacer` element

`spacer` is a leaf element that occupies space without rendering content. It accepts `width` and `height` attributes.

```
<block>
  <text>First section</text>
  <spacer height=20/>
  <text>Second section</text>
</block>
```

Spacers are how LHT expresses spacing between elements. There is no margin attribute.

### 4.7 Tables

LHT provides a dedicated `table` element for tabular data. Tables are conceptually distinct from layout containers: their structure expresses *data* (rows of items with consistent columns), not just visual arrangement. For purely visual horizontal layout (e.g., header / main / sidebar), use `row` instead.

#### 4.7.1 Structure

```
<table>
  <col [width=...] [class=...] [bgColor=...] .../>     ; zero or more
  <col .../>
  ...
  <tr [class=...] [bgColor=...]>                        ; one or more
    <td [colspan=N] [rowspan=M] [class=...] ...>
      ...content...
    </td>
    ...
  </tr>
  ...
</table>
```

There are no `<thead>`, `<tbody>`, `<tfoot>`, or `<th>` elements. Header rows are expressed via classes (e.g., `<tr class="header">`).

#### 4.7.2 Columns

`<col>` elements appear before any `<tr>` and define column-level metadata. They are not rendered themselves; they configure how cells in their column are sized and styled.

`<col>` accepts:

- `width` — column width (see 4.7.4 below).
- `class` — applied to all cells in this column (cell attributes override).
- `bgColor`, `align`, `valign`, `font`, `color`, `padding` — defaults for cells in this column.
- `border-*` attributes — drawn on every cell in this column.

If fewer `<col>` elements are given than the table has columns, the remaining columns get default values (width=fill, no other attributes).

#### 4.7.3 Spans

`colspan=N` causes a cell to occupy N consecutive columns horizontally. `rowspan=M` causes it to occupy M consecutive rows vertically. Cells are placed left-to-right within each row, skipping positions already occupied by spans from previous rows. When a `<tr>` has fewer `<td>` elements than there are unoccupied positions in the row, the remaining positions are left empty.

Overlapping spans (two `<td>` elements attempting to occupy the same virtual cell) are a validation error.

#### 4.7.4 Column widths

Column widths must be one of:

- An integer (pixels): fixed width.
- A fraction (0..256): fraction of the table's inner width.
- `fill`: distribute remaining width equally among all `fill` columns.

The value `auto` is **not allowed** for column widths. Auto-sizing requires measuring content, which would force a multi-pass layout dependent on content that may vary across loads. Authors must specify column widths explicitly.

This is a deliberate restriction. If the data is too variable to plan column widths, use `flow` for free-form arrangement, or place the table inside an `overflowX=scroll` block.

#### 4.7.5 Row heights

Row heights are determined by the height of the tallest cell in the row, unless a `<tr>` specifies an explicit `height`. Cells with `rowspan > 1` distribute their content's height across the rows they occupy.

#### 4.7.6 Borders

Borders in tables follow the general cosmetic rule (4.1.1): they do not affect layout dimensions. Each level (table, col, tr, td) may declare borders independently; on cells, the most specific level wins.

**Specificity (most specific first):**

1. `<td>` — borders on the cell itself.
2. `<tr>` — borders applied to every cell in this row.
3. `<col>` — borders applied to every cell in this column.
4. `<table>` — outer border of the table; not propagated to cells.

When two borders are declared on perpendicular axes (e.g., `<col borderRight=1>` and `<tr borderBottom=1>`), both render — they don't conflict because they're on different edges of the cell.

When two borders are declared on the same edge at different specificity (e.g., `<col borderRight=1>` and `<td borderRight=2>` on a cell in that column), the more specific one wins (the `<td>` value).

**Convenience attributes for regular grid borders:**

| Attribute (on `<table>`) | Effect |
|---|---|
| `internalBorders=N` | N-pixel lines between every adjacent pair of cells, both horizontal and vertical |
| `internalHBorders=N` | N-pixel lines between rows only |
| `internalVBorders=N` | N-pixel lines between columns only |

These are convenience shortcuts equivalent to setting cell-level borders that produce the regular grid pattern. Cell-level borders override these convenience patterns where defined.

**Pixel placement.** Each border is rendered within the bounding rectangle of the level that declared it. A `<col borderRight=1>` draws one pixel on the right edge of every cell in that column — the pixel is inside the cell. A neighboring column does not draw a left-border by default, so there is no doubling. Authors who declare borders on both sides of an edge get two adjacent pixels (which appear as a 2-pixel line); this is rarely desired and easily avoided.

**Dynamic borders.** Because borders do not affect layout, they may be added or removed dynamically (typically from scripts or via `:hover`/`:focus` state classes) without triggering reflow. This makes it natural to highlight a cell on hover, indicate selection, or draw focus rings without disturbing the table's geometry.

#### 4.7.7 Backgrounds

Background colors apply at all four levels (table, col, tr, td) with painter's-algorithm layering: table → col → tr → td, in that order, each overlaying the previous. The most recently painted layer is what's visible.

```
<table bgColor=#FAFAFA>
  <col bgColor=#FFFFFF/>
  <col bgColor=#F0F0F0/>          ; second column tinted
  <tr>
    <td>cell 1.1</td>              ; bg = #FFFFFF (col 1)
    <td bgColor=#FFE0E0>cell 1.2</td>  ; bg = #FFE0E0 (cell override)
  </tr>
</table>
```

This makes zebra striping (`<tr class="even" bgColor=...>`), highlighted columns, and selection feedback straightforward.

#### 4.7.8 Layout

Because column widths are fixed up front (no `auto`), table layout is single-pass:

1. Resolve all column widths (integers, fractions, and `fill` distribution).
2. For each row, layout each cell with the corresponding column width(s) (combining widths for `colspan`).
3. The row's height is determined by the tallest laid-out cell in the row.
4. The table's height is the sum of row heights.

A table whose total column width exceeds the parent's inner width is subject to the table's `overflowX` attribute (Section 4.5), like any other block.

#### 4.7.9 Script access

Tables expose a structural API to scripts:

```
let t = getElement("my_table");
let row = t.rows[2];                      // third row
let cell = row.cells[1];                  // second cell of that row
cell.text = "new value";

t.addRow([{text: "1.1"}, {text: "1.2"}]); // append a row
t.removeRow(0);                          // remove first row
```

This API is specialized for tables rather than relying on generic DOM traversal — it makes table-manipulating scripts substantially more readable.

### 4.8 Layout determinism and tolerances

LHT layout is deterministic in **structure** but may vary in **fine typography**.

Guaranteed across conforming clients:

- The set of elements rendered, and their nesting.
- The relative ordering of siblings.
- The container type of each element (no element silently switching from `block` to `flow`).
- The presence or absence of horizontal scrolling on a given block.

Allowed to vary:

- The pixel-exact width of a text run (subject to font choice, see Section 6).
- The exact line break points within a paragraph (a few characters' worth of variation).
- The exact height of a glyph or line.

This soft typographic determinism reflects the practical reality that bitmap font rendering varies between hardware and configurations. Authors must not rely on pixel-exact text dimensions; they must leave reasonable space margins in containers that hold variable-width text.

### 4.9 Layout algorithm summary

The layout algorithm is a single recursive top-down pass:

```
layout(node, available_outer_width):
    1. Compute node's outer width:
       - explicit width attribute, or
       - inferred (e.g., width=fill ⇒ available_outer_width)
    2. Compute inner width by subtracting padding (border has zero
       layout effect, see 4.1.1).
    3. Dispatch by type:
       - block: layout children vertically inside inner width
       - flow: run line-breaking algorithm in inner width
       - row: layout children horizontally inside inner width
       - fixed: layout children at their absolute positions
       - scrollbox: layout children as block, with inner width =
         outer_width - scrollbar_width
       - table: resolve column widths, then layout cells
         (Section 4.7.8)
    4. If node's height was 'auto', set it to the height required by children.
    5. If a child's outer width exceeds inner_width, apply the child's
       overflowX strategy (Section 4.5).
    6. Return final outer rect.
```

No reflow, no resolution-dependent rules. A typical document lays out in a single top-down traversal — for a 100-element document, a few hundred function calls.

---

### 4.10 Canvas

`<canvas>` is a leaf element that provides a programmable drawing surface. All drawing is done via a script API; the element itself only defines the surface dimensions.

```
<canvas id="chart" width=400 height=300/>
<canvas id="game"  width=320 height=200 bgColor=#000000/>
```

`bgColor` sets the initial fill color (default: transparent). `width` and `height` are required.

#### 4.10.1 Drawing API

The canvas is accessed from script via `.context()`:

```js
let ctx = getElement("chart").context();
```

All coordinate arguments are in canvas-local pixels (origin at top-left). Drawing is immediate — each call takes effect at once; there is no explicit flush.

**Translate** (absolute, drawing only — does not affect clip coordinates):
```js
ctx.translate(dx, dy);    /* offset applied to all subsequent drawing calls */
ctx.translate(0, 0);      /* reset to canvas origin */
```

**Clip stack** (coordinates always canvas-absolute, independent of translate):
```js
ctx.clipRect(x, y, w, h);  /* push current clip, new clip = current ∩ rect */
ctx.resetClip();             /* pop — restore previous clip */
```

**Clear:**
```js
ctx.clear();         /* fill with bgColor (or transparent if none) */
ctx.clear(color);    /* fill with given color */
```

**Primitives:**
```js
ctx.fillRect(x, y, w, h, color);
ctx.strokeRect(x, y, w, h, width, color);
ctx.fillCircle(cx, cy, r, color);
ctx.strokeCircle(cx, cy, r, width, color);
ctx.strokeLine(x1, y1, x2, y2, width, color);
```

**Path API** (lines and circular arcs; no bezier curves):
```js
ctx.beginPath();
ctx.moveTo(x, y);
ctx.lineTo(x, y);
ctx.arc(cx, cy, r, a1, a2);  /* arc from a1 to a2 in degrees, connected to current point */
ctx.closePath();             /* line back to first point */
ctx.fill(color);
ctx.stroke(width, color);
```

Pie/sector example:
```js
ctx.beginPath();
ctx.moveTo(cx, cy);
ctx.arc(cx, cy, r, 0, 90);
ctx.closePath();
ctx.fill(#3366CC);
```

**Images and text:**
```js
ctx.drawImage("name", x, y);           /* natural size */
ctx.drawImage("name", x, y, w, h);     /* scaled */
ctx.fillText("str", x, y);             /* uses current inherited font and color */
ctx.fillText("str", x, y, font=default-mono-10, color=#FF0000);
```

`drawImage` uses the image definition system (Section 5) — the name refers to a logical image, not a resource directly.

#### 4.10.2 Support levels

Canvas support is declared via content negotiation:

| Level | Capabilities |
|---|---|
| `canvas=none` | Element not supported; rendered as empty space |
| `canvas=basic` | Primitives only (`fillRect`, `strokeRect`, `strokeLine`, `drawImage`, `clear`); no path API, no translate |
| `canvas=full` | Complete API as specified above |

A `canvas=basic` client ignores path API calls silently. Authors targeting constrained clients should check the capability level from script before using the path API.

---

*End of Sections 1-4 draft. Sections 5+ to follow:*

- *5. Resources and Images*
- *6. Fonts*
- *7. Inline Content (text runs, modifiers, atoms)*
- *8. Events*
- *9. Scripts*
- *10. Network and Storage*
- *11. Content Negotiation*
- *Appendices: bundle contents, canonical text form, etc.*

*Open questions to revisit:*

- *Exact bundle contents (token assignments) — appendix to be written.*
- *Textual canonical form syntax — to be specified for reversibility (P5).*
- *Bundle 0 / reserved tokens — final assignment.*
- *Validation: should server-side tokenizer be required to reject duplicate class names, undefined references, etc.? (Yes, but spec it formally.)*
- *Inline content rules for `flow` containers and text-bearing elements — full model in Section 7.*
