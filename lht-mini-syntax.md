# LHT Mini Syntax

**Status:** reference implementation note  
**Scope:** source syntax accepted by the first `lhtc` vertical slice.

This is not the full LHT text syntax. It documents the small source subset used by
the current parser, tokenizer, binary encoder, decoder, and fixture corpus.

---

## 1. Purpose

The mini syntax exists to keep the reference encoder honest while the format is
still growing.

Current pipeline:

```text
.lht source -> normalized tree -> mini token stream -> mini binary -> decoded tree
```

The canonical fixture is:

```text
examples/minimal/index.lht
```

---

## 2. Character Model

The current implementation treats input as a byte string. It does not yet validate
UTF-8 or define source encodings.

For the mini slice, examples should stay ASCII unless a future text-encoding pass
explicitly expands this.

---

## 3. Tags

Tags use angle brackets:

```text
<name>
</name>
```

Names may contain:

```text
A..Z a..z 0..9 _ -
```

Whitespace is allowed after `<` and before `>`:

```text
< block >
</ block >
```

This is accepted by the parser, but canonical examples should use compact normal
tag spelling:

```text
<block>
</block>
```

---

## 4. Container Tags

The mini dictionary currently supports these container elements:

```text
lhtml
head
title
body
style
script
block
row
table
col
tr
td
span
a
```

Container elements must be closed:

```text
<block>Text</block>
```

Mismatched or unclosed container tags are fatal parser errors.

---

## 5. Bare Tags And Commands

The current bare tags are:

```text
meta
spacer
col
p
br
```

They do not push a stack frame and do not require a closing tag.

Canonical forms:

```text
<meta name="description" content="...">
<spacer height=8>
<p>
<br>
```

Important model rule:

```text
<p>
```

is a paragraph separator command, not a paragraph container. Do not write:

```text
<p>text</p>
```

The current parser also accepts XML-style self-closing tags:

```text
<spacer height=8/>
```

This is an implementation convenience, not the preferred mini-LHT style.

---

## 6. Attributes

Attributes appear inside opening or bare tags:

```text
<block id="intro">
<spacer height=8>
```

Supported mini attributes:

```text
version
name
content
id
width
height
href
class
font
fontFace
fontSize
color
background
border
padding
borderWidth
```

Values may be double-quoted, single-quoted, or unquoted:

```text
id="intro"
id='intro'
height=8
class=notice
color=#49C
background=#F8F7F1
padding=12
borderWidth=2
```

Unquoted values continue until whitespace or `>`.

If an attribute has no `=`, the parser currently stores it as:

```text
name="true"
```

Boolean attributes are not used by the mini fixtures yet.

There is no escaping inside quoted strings yet. The value ends at the next
matching quote.

---

## 7. Text

Text between tags becomes text nodes after whitespace normalization.

The current normalization:

- collapses runs of spaces, tabs, CR, and LF into one space;
- trims leading and trailing whitespace from each parsed text segment;
- drops empty normalized text segments.

Example:

```text
Hello,
  world
```

becomes:

```text
Hello, world
```

Text split by inline elements remains split into separate text nodes:

```text
Text <span>inside</span>.
```

normalizes as:

```text
TEXT "Text"
START span
  TEXT "inside"
END span
TEXT "."
```

This means whitespace around inline elements is not fully HTML-like yet. That is
acceptable for the mini slice and should be revisited during renderer work.

---

## 8. Current Document Shape

The canonical shape is:

```text
<lhtml version=1>
<head>
  <title>Title</title>
  <meta name="description" content="Description">
</head>

<style>
.notice { background=#EEF7FF; border=#49C; padding=12 }
</style>

<body>
  ...
</body>
</lhtml>
```

The parser currently builds a synthetic root:

```text
#document
```

The binary encoder expects `lhtml` as the document element and treats `body` as a
special transition:

```text
DOC stream imports DOC+ATTR -> BODY_BEGIN -> DOM stream imports DOM+ATTR+VALUE -> START body
```

Imports are stream-local but persistent for the document. Entering `DOM` selects
the DOM token table; it does not reset previously imported DOM dictionaries.
`<style>` is encoded as a separate STYLE stream via `STYLE_BEGIN` before the DOM
body stream.
`<script>` is encoded as a separate SCRIPT stream via `SCRIPT_BEGIN`. Script
language internals are documented in `ljs-*` files.

---

## 8.1 Current Style Shape

The mini style slice supports only flat class declarations:

```text
<style>
.notice { background=#EEF7FF; border=#49C; borderWidth=2; padding=12; color=navy }
.accent { color=red }
</style>
```

Supported style properties are the same names from the shared mini attribute
dictionary. Inline DOM attributes override class attributes during rendering.

---

## 8.2 Comments

Source comments use XML/HTML-style comment delimiters:

```text
<!-- comment text -->
```

Comments are discarded by the mini parser. They are not represented in the DOM,
token dump, binary stream, or canonical decode output.

Unterminated comments are fatal parser errors.

---

## 9. Current DOM Shape

The minimal DOM subset is:

```text
body
  block
  row
  table
    col
    tr
      td
  spacer
  span
  a
  p
  br
  text
```

Typical patterns:

```text
<block id="intro">
  Text.
  <p>
  More text with a <span id="status">span</span>.
  <br>
  A <a href="/docs">link</a>.
</block>

<row id="actions">
  <block width=120>Left</block>
  <spacer width=8>
  <block width=120>Right</block>
</row>

<table width=520>
  <col>
  <col>
  <tr>
    <td>Name</td>
    <td>Status</td>
  </tr>
</table>
```

The first table slice is deliberately simple:

- `table` contains zero or more `col` declarations followed by `tr` rows;
- `col` is a bare tag and must appear before the first `tr`;
- `tr` contains `td` cells;
- columns are equal width by the maximum cell count in the table;
- every `td` owns its own background, border, padding, and text layout;
- row height is the maximum rendered cell height in that row;
- there is no border-collapse model.

---

## 10. Current Typed Values

The mini encoder currently treats:

- `version`, `width`, `height`, `padding`, and `borderWidth` as unsigned integer attributes;
- `font` as source shorthand for `fontFace` and/or `fontSize`;
- `fontFace` as standard enum `TFontFace`: `default=0`, `sans=1`, `serif=2`, `mono=3`;
- `fontSize` as standard enum `TFontSize`: `tiny=0`, `small=1`, `normal=2`, `large=3`, `xlarge=4`, `xxlarge=5`;
- `color`, `background`, and `border` as RGB565 color attributes;
- integer values `0..255` as `INLINE_BYTE`;
- larger unsigned integers as `INLINE_VALUE uint`;
- font family values as imported `value:TFontFace:*` tokens;
- font size values as imported `value:TFontSize:*` tokens;
- color values as `INLINE_VALUE color`;
- `class` as `INLINE_VALUE string`;
- text nodes as `INLINE_VALUE text`;
- other attributes as `INLINE_VALUE string`.

The mini text syntax does not yet parse:

- signed integers;
- floats;
- fixed-point values;
- blobs;
- names as a distinct typed value.

Supported color source forms in the mini slice:

```text
#RGB
#RRGGBB
black white red green blue navy gray silver yellow
```

The mini binary stream stores these as RGB565. Decoding back to text produces a
canonical `#RRGGBB` value after RGB565 quantization.

`font` shorthand is normalized before tokenization. Comma-separated values are
recognized by semantic type:

```text
font=serif,small -> fontFace=serif fontSize=small
font=large       -> fontSize=large
font=mono        -> fontFace=mono
```

---

## 11. Unsupported In Mini Slice

The current parser/tokenizer slice does not support:

- entities;
- string escapes;
- images;
- forms;
- lists;
- style attributes;
- text compression;
- resource manifests;
- full validation of allowed child elements outside the current table slice.

Unsupported element and attribute names are rejected by the parser before
tokenization. Style declarations are also validated against the shared mini
attribute dictionary.

---

## 12. Error Policy

Current fatal parser errors include:

- expected tag or attribute name is missing;
- an element name is not in the mini DOC/DOM surface;
- an attribute name is not in the mini attribute surface;
- a typed attribute value is invalid for its mini type;
- table structure is invalid: `col` appears after `tr`, `table` contains
  something other than `col`/`tr`, `tr` contains something other than `td`, or
  `td` contains block/table structure;
- quoted attribute value is unterminated;
- closing tag is malformed;
- a closing tag is used for a bare tag such as `<br>` or `<p>`;
- closing tag does not match the current open element;
- a container element remains unclosed at EOF;
- document root is not exactly one `<lhtml>` element;
- document has anything other than `<head>`, `<style>`, `<script>`, or `<body>`
  directly under `<lhtml>`;
- document does not contain exactly one `<body>`;
- style text is not a flat class-declaration mini stylesheet.

The parser does not yet report line/column positions. It reports byte positions
for some syntax errors.

---

## 13. Near-Term Cleanup

Next parser/validation pass should:

- refine allowed child-element validation beyond the current document-level
  checks;
- decide whether self-closing syntax remains accepted;
- improve error messages with line and column;
- decide whitespace behavior around inline elements before renderer behavior
  depends on it.
