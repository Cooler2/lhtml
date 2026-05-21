# LHT Tokenization Concept

**Status:** design note  
**Scope:** logical tokenization model discussed after the initial spec draft  
**Goal:** make LHT token streams compact, typed, streaming-friendly, and extensible without arbitrary token ids

---

## 1. Core Direction

LHT should be treated as a typed stream container, not as one universal token stream.

The source text may contain familiar authoring constructs such as:

```lht
<lhtml>
  <head>...</head>
  <style>...</style>
  <body>...</body>
  <script>...</script>
</lhtml>
```

But after tokenization, only the visible body becomes a DOM tree. Other parts become separate typed sections:

- metadata records
- resource declarations
- image definitions
- constants
- classes
- script/library manifests
- script streams or bytecode
- the body DOM stream

This avoids putting `<head>`, `<style>`, `<script>`, and `<lhtml>` into the runtime DOM. They are authoring syntax and document structure, not visible document nodes.

---

## 2. Typed Substreams

Different document regions use different grammars. They should therefore be tokenized as different stream types:

| Stream | Purpose |
|---|---|
| `DOC` | top-level document container, section switching, metadata |
| `STYLE` | resources, image definitions, constants, classes |
| `DOM` | visible body tree |
| `TEXT` | aggregated text storage and codec state for visible text runs |
| `LJS` | script source tokens or script bytecode |
| `LHV` | vector image drawing commands |

The document stream switches decoder state explicitly. A substream ends with a generic `END` token, after which the decoder returns to the interrupted parent stream.

Logical example:

```text
DOC_STREAM
  META title "LHT Basic Tour"

  STYLE_BEGIN
    STYLE_STREAM
      RESOURCE ...
      CLASS ...
    END

  BODY_BEGIN
    DOM_STREAM
      START body
        ...
      END
    END

  SCRIPT_BEGIN
    LJS_STREAM
      ...
    END
END
```

`BODY_BEGIN` is a `DOC`-level command that switches the decoder into DOM mode. It is not a DOM node. After `BODY_BEGIN`, the encoder emits the DOM preamble (`IMPORT`, `PIN_LIST`, `PIN_USE`, and optional `INLINE_VALUE` declarations) and then the first real DOM tree token: `START body`. The `body` element may carry attributes such as `class` and is closed by a matching `END` at depth zero of the DOM stream. `BODY_BEGIN` and `START body` are two different abstraction levels — one switches the stream, the other opens the root element.

The same numeric `END` value may be used in every stream. Its meaning is state-dependent:

- in `DOM`, it closes the current element or ends the body stream;
- in `STYLE`, it ends the style stream;
- in `LJS`, it ends the script stream;
- in `DOC`, it ends the current document section or the document itself.

This keeps encoding compact while preserving a simple stack-based decoder.

V1 uses this single universal `END`; there are no separate `END_NODE` or `END_STREAM` tokens.

`TEXT` is not a required nested substream inside DOM in v1. Visible text remains represented by DOM text-content items, while large document text may be aggregated into a separate text storage/codec layer for compression.

---

## 3. Standard Dictionaries Per Stream Type

Each stream type has one or more standard dictionaries. These dictionaries define the grammar vocabulary for that stream.

Examples:

| Dictionary | Entries |
|---|---|
| `DOC_CORE_V1` | section markers, metadata fields, resource/script manifest commands |
| `DOM_CORE_V1` | standard elements, attributes, enum values, structural commands |
| `STYLE_CORE_V1` | style directives, properties, pseudo-states, value constructors |
| `LJS_CORE_V1` | keywords, operators, punctuation, bytecode opcodes, core builtins |
| `LJS_CANVAS_V1` | canvas-related script API vocabulary |
| `LJS_STORAGE_V1` | storage API vocabulary |

Extensions are imported by adding more standard dictionaries. A new feature adds a new vocabulary instead of allowing arbitrary local grammar extensions.

For example:

```text
IMPORT LJS_CORE_V1 64
IMPORT LJS_CANVAS_V1 16
IMPORT LJS_STORAGE_V1 16
```

`IMPORT` carries an explicit count. If the dictionary is known, the client binds the first `count` entries. If the dictionary is unknown, the client still reserves `count` token slots so token numbering remains stable and structural skipping can continue. If `count` exceeds the number of entries in a known dictionary, the stream is invalid.

---

## 4. Sequential Token Assignment

Token numbers are assigned strictly in stream order.

There is no arbitrary token id chosen by the encoder. This keeps the decoder simple and avoids collision rules.

Conceptual state:

```text
nextToken = firstLocalToken
```

Every token-producing command assigns the current `nextToken`, then increments it:

```text
INLINE_VALUE DEFINE string "panel"
  -> token = nextToken
  -> nextToken++

IMPORT DOM_CORE_V1 count
  -> reserves/imports the first count entries in dictionary order
  -> nextToken advances for each appended entry
```

Token ids are local to the current stream dictionary. A `DOM` token id and an `LJS` token id are not the same namespace unless a future container explicitly defines shared ranges.

---

## 5. IMPORT, PIN_LIST, And PIN_USE

Encoders may want frequent standard tokens to receive short early token numbers. Instead of redefining standard entries by name, the encoder can bind entries from a standard dictionary by stable numeric entry indexes.

The v1 forms are:

```text
IMPORT DOM_CORE_V1 64
PIN_LIST DOM_CORE_V1 [element:block, attr:class, attr:width]
PIN_USE DOM_CORE_V1 element:dialog
```

Binary forms reference stable numeric entry indexes within the standard dictionary:

```text
IMPORT dictId count
PIN_LIST dictId count entryIndex[count]
PIN_USE dictId entryIndex
```

Behavior:

```text
IMPORT:
  reserve/import first count entries from dictionary
  nextToken += count

PIN_LIST:
  for each entryIndex:
    entry = dictionary[entryIndex]
    tokenTable[nextToken] = entry
    nextToken++

PIN_USE:
  entry = dictionary[entryIndex]
  tokenTable[nextToken] = entry
  emit/use tokenTable[nextToken]
  nextToken++
```

Benefits:

- frequent standard entries get short token ids;
- no arbitrary token assignment;
- no duplicate-name search when binding dictionary entries;
- no semantic mismatch between local names and standard names;
- extension dictionaries work the same way as core dictionaries.

`PIN_LIST` replaces single-entry `PIN`; a one-item list covers that case. `PIN_RANGE` is intentionally omitted because dictionaries should be ordered by expected frequency, making `IMPORT count` the useful contiguous-range operation.

---

## 6. IMPORT

`IMPORT` reserves/imports the first `count` entries from a standard dictionary into the current stream dictionary.

The order of dictionary imports affects local token numbers and is part of the stream encoding. The explicit `count` is also a compatibility guard: unknown dictionaries still advance `nextToken` by a known amount, and known dictionaries can reject impossible counts.

Example:

```text
PIN_LIST DOM_CORE_V1 [element:block, attr:class]
IMPORT DOM_CORE_V1 64
IMPORT DOM_FORMS_V1 16
```

Another document may import in a different order. Both are valid, because token numbers are stream-local and defined by the stream itself.

---

## 7. Local Definitions

Local definitions are restricted by stream type. This is an important part of validation and security.

For `DOM`, local definitions may include:

- class names
- element ids
- resource/image references
- string constants
- numeric constants

They should not define new grammar tokens such as arbitrary element tags or attribute names unless an extension dictionary explicitly allows it.

For `STYLE`, local definitions may include:

- class names
- constants
- resource names
- image definition names
- literal values

For `LJS`, local definitions may include:

- identifiers
- string constants
- numeric constants
- labels/function names if represented separately

They must not define:

- keywords
- operators
- punctuation
- bytecode opcodes
- privileged builtins

Those come only from standard script dictionaries.

This means a script stream cannot locally invent a token that behaves like `if`, `return`, `CALL`, or `Request`. It can only use those tokens if the appropriate standard dictionary is imported.

---

## 8. INLINE_VALUE Definitions And Uses

Local literals use one physical form, `INLINE_VALUE`, with two independent flags:

```text
USE           ; emit a one-shot inline value
DEFINE        ; bind the value to the next local token
DEFINE + USE  ; bind the value and use it immediately
```

### 8.1 DEFINE

`INLINE_VALUE DEFINE` creates a token but does not emit it as the current item. An optimizing encoder can do a prepass, identify frequent document-local entries, and define them early so they receive short token numbers.

Example:

```text
INLINE_VALUE DEFINE string "page"
INLINE_VALUE DEFINE string "hero"
INLINE_VALUE DEFINE string "LHT Basic Tour"

BODY_BEGIN
  ...
```

### 8.2 DEFINE + USE

`INLINE_VALUE DEFINE + USE` creates a token and immediately uses it at the current position. This is the streaming form for symbols or constants first seen at use site.

Example:

```text
ATTR class INLINE_VALUE DEFINE + USE string "hero"
TEXT INLINE_VALUE DEFINE + USE text "LHT Basic Tour"
```

For base DOM, `DEFINE + USE` is used for user-level values and strings, not for grammar tokens:

```text
ATTR class INLINE_VALUE DEFINE + USE string "hero"
TEXT INLINE_VALUE DEFINE + USE text "LHT Basic Tour"
```

Standard grammar tokens should usually be referenced from imported dictionaries or pinned standard entries.

---

## 9. Raw Literals Vs Interned Values

Not every value should be interned.

One-shot values can be emitted as raw literals:

```text
INLINE_VALUE USE string "LHT"
INLINE_VALUE USE uint 96
INLINE_VALUE USE color #D09020
```

Recurring values can be interned:

```text
INLINE_VALUE DEFINE string "LHT Basic Tour"
STRING_REF token

INLINE_VALUE DEFINE uint 12
INT_REF token

INLINE_VALUE DEFINE color #FFFFFF
COLOR_REF token
```

Or defined and used at first occurrence:

```text
INLINE_VALUE DEFINE + USE text "A small document with layout, text, images, a table, events, and storage."
```

In practice:

- strings benefit most from interning;
- repeated colors such as `#FFFFFF` may benefit;
- small integers often do not need interning unless they are extremely frequent;
- raw literals keep streaming encoders simple.

---

## 10. END-Delimited DOM And Self-Closing Elements

The initial draft used explicit child counts:

```text
NODE token childCount
  child...
```

This guarantees a bounded subtree but is awkward for true one-pass encoding. The encoder must know the number of children before it writes the node, or it must buffer/backpatch the subtree. Backpatching is especially awkward with variable-length integers.

The revised concept uses two meta-tokens. `START` precedes a content-bearing element and requires a matching `END`. A bare element token (without `START`) is self-closing:

```text
START block
  ATTR class hero
  START row
    img
      ATTR name logo
      ATTR width 96
  END
END
```

A bare element token reads its attributes and immediately returns to the parent context. No `END` is emitted or expected; no stack frame is pushed. This is more compact than a separate `VOID` prefix: a self-closing element costs one token instead of two.

Whether an element is self-closing is determined by the presence or absence of `START` — the decoder needs no dictionary lookup.

Advantages:

- true streaming encoder;
- no child-count backpatching;
- simple stack-based decoder;
- still easy to validate;
- self-closing elements are one token, not two;
- unknown subtrees can be skipped by depth counting.

Skip unknown subtree:

```text
depth = 1
while depth > 0:
  item = readItem()
  if item is START: read element token; depth++
  if item is END:   depth--
  else:             skip attributes only  ; bare element token
```

Bare tokens do not affect depth. Their attributes are terminated by the first non-attribute token, which is returned to the skip loop.

Raw payloads still carry lengths, so the decoder can skip them.

---

## 11. Attributes And Content Are Separated By Types

Ambiguity between attributes and children should be avoided through typed grammar, not through fragile syntax.

An attribute expects an `AttributeValue` expression. Element content expects `ContentItem` values.

Important distinction:

- a string used as an attribute value is a `STRING` value;
- visible text inside an element is a `TEXT_RUN` or text-content item;
- these are not the same token type, even if they use the same underlying bytes.

Example:

```text
START p
  ATTR class CLASS_REF muted
  TEXT_RUN STRING_REF "Hello"
END
```

`TEXT_RUN` cannot be consumed as an attribute value. `STRING_REF` alone does not mean visible content unless wrapped in a text-content command.

A simple DOM grammar can require:

1. After `START element`, attributes may appear.
2. The first non-attribute item begins content.
3. After content begins, attributes are no longer allowed until the matching `END`.

This avoids a separate `CHILDREN_BEGIN` marker while keeping the stream easy to validate.

V1 does not use an explicit `ATTRS_END` marker. The first non-attribute item starts content, and attributes are rejected after content has begun.

For bare (self-closing) element tokens, only the attribute phase exists. There is no content phase and no matching `END`. The first non-attribute token after the last attribute of a bare element is consumed by the parent context.

---

## 12. Scripts Are Separate Streams

Script grammar is too different from DOM/style grammar to share one token language.

An inline script should switch into an `LJS` stream or compiled bytecode substream:

```text
SCRIPT_BEGIN
  LJS_STREAM
    IMPORT LJS_CORE_V1 64
    INLINE_VALUE DEFINE name "setStatus"
    ...
  END
```

Script standard dictionaries define:

- keywords
- operators
- punctuation
- bytecode opcodes if bytecode form is used
- standard builtins
- capability-specific APIs

Local script definitions are limited to identifiers and constants. This keeps the grammar closed and makes validation much simpler.

---

## 13. Stream Switching In Text Form Tokenization

A text-form tokenizer can operate in one pass by switching tokenizers:

1. Document tokenizer reads document-level source.
2. On `<style>`, it invokes the style tokenizer until `</style>`, emits a `STYLE` substream, and returns.
3. On `<body>`, it invokes the DOM tokenizer until `</body>`, emits a `DOM` substream, and returns.
4. On inline `<script>`, it invokes the script tokenizer/compiler until `</script>`, emits an `LJS` substream or bytecode, and returns.
5. On external `<script src=...>` or `<library src=...>`, it emits manifest records rather than script content.

This avoids one giant grammar and lets each substream use the representation best suited to its domain.

---

## 14. Optional Document Symbol Exports

Some names naturally cross stream boundaries:

- classes defined in style are referenced by DOM `class` attributes;
- image definitions are referenced by `<img>` and canvas `drawImage`;
- resources are referenced by image definitions;
- DOM ids are referenced by scripts through `getElement`;
- library interfaces are referenced by later scripts.

A possible future mechanism is a document-level symbol table:

```text
STYLE DEFINE class "hero"
  -> export document symbol class:hero

DOM BIND document symbol class:hero
  -> local DOM token for same semantic class
```

However, automatic export/binding can create complexity and subtle ordering problems. It is not part of the current concept. For now this should remain a design idea:

> Future versions may define explicit export/import bindings for selected symbol categories. Local token numbers should remain stream-local.

If added later, exported symbols must be namespaced by category:

```text
class:hero
image:hero
id:hero
resource:hero
```

The same text in different categories must not collide.

---

## 15. Sketch: Tokenizing The Start Of `basic-tour`

Source:

```lht
<body class="page">
  <block class="hero">
    <row>
      <img name="logo" width=96 height=24 alt="LHT"/>
```

Possible DOM stream:

```text
BODY_BEGIN
  PIN_LIST DOM_CORE_V1 [
    element:body, element:block, element:row, element:img,
    attr:class, attr:name, attr:width, attr:height, attr:alt
  ]
  IMPORT DOM_CORE_V1 64

  INLINE_VALUE DEFINE string "page"
  INLINE_VALUE DEFINE string "hero"
  INLINE_VALUE DEFINE string "logo"

  START body
    ATTR class CLASS_REF page

    START block
      ATTR class CLASS_REF hero

      START row

        img
          ATTR name STRING_REF logo
          ATTR width INLINE_BYTE 96
          ATTR height INLINE_BYTE 24
          ATTR alt INLINE_VALUE USE string "LHT"
```

For a more streaming encoder, some entries could be defined at first use:

```text
START body
  ATTR class INLINE_VALUE DEFINE + USE string "page"

  START block
    ATTR class INLINE_VALUE DEFINE + USE string "hero"

    START row
      img
        ATTR name   INLINE_VALUE DEFINE + USE string "logo"
        ATTR width  INLINE_BYTE 96
        ATTR height INLINE_BYTE 24
        ATTR alt    INLINE_VALUE USE string "LHT"
```

Both modes use sequential token assignment. The difference is only whether the encoder chooses to predeclare frequent tokens or define them lazily.

---

## 16. Open Questions

- How much of `STYLE` should be structural records rather than a tokenized style grammar.
