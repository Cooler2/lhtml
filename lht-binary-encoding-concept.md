# LHT Binary Encoding Concept

**Status:** draft / not yet in spec  
**Goal:** concrete byte-level encoding for the LHT token stream

---

## 1. Reserved Meta-Values

The varint value itself determines whether a byte sequence is a meta-token or a dictionary token:

| Value | Name | Meaning |
|---|---|---|
| `00` | `END` | Close innermost `START`, or end current substream |
| `01` | `START` | Open content-bearing element; next varint = element token |
| `02` | `COMMAND` | Meta-command; next byte = subcommand id, followed by arguments |
| `03` | `INLINE_VALUE` | Inline literal and/or custom token declaration; next byte = header, followed by data |
| `04` | `INLINE_BYTE` | Raw unsigned byte literal; next byte = value 0..255 |
| `05..7F` | token | Single-byte dictionary token (123 slots) |
| `80..` | token | Multi-byte varint dictionary token (128+) |

A single `read_varint()` call returns either a meta-value (0..4) or a dictionary token id (5+). No separate dispatch is needed.

A bare dictionary token (not preceded by `START`) is a self-closing element or attribute value — no stack frame is pushed, no `END` is expected.

---

## 2. Token Space (05+)

Token ids are assigned sequentially by the substream preamble (via `IMPORT`, `PIN_LIST`, `PIN_USE`, and `INLINE_VALUE` declarations). The first 123 ids (05..7F) fit in one byte; these should be occupied by the most frequent elements, attributes, and values.

The dictionary entry for each token carries its semantic type (element, attribute, value, string, etc.). This type is used by the semantic parser to interpret the token in context. The structural parser (skip algorithm) does not need it.

---

## 3. COMMAND Subcommands (02)

`COMMAND` is the escape for all infrequent meta-operations. The subcommand byte follows immediately:

| Subcommand | Name | Arguments | Purpose |
|---|---|---|---|
| `00` | `IMPORT` | dictId:varint, count:varint | Reserve/import the first `count` entries from a standard dictionary |
| `01` | `PIN_LIST` | dictId:varint, count:varint, entryIdx[count]:varint | Assign consecutive tokens to selected dictionary entries |
| `02` | `PIN_USE` | dictId:varint, entryIdx:varint | Assign current nextToken to a dictionary entry and immediately use it |
| `03` | reserved | | |
| `04` | `BODY_BEGIN` | — | Switch decoder to DOM mode |
| `05` | `STYLE_BEGIN` | — | Switch decoder to STYLE mode |
| `06` | `SCRIPT_BEGIN` | — | Switch decoder to LJS mode |
| `07` | `TEXT_CODEC` | codec:byte | Select codec for aggregated text-run storage |
| `08`+ | reserved | | |

`IMPORT` reserves `count` token slots even when `dictId` is unknown. This allows old or minimal decoders to keep token numbering stable and continue structural parsing. If `count` exceeds the number of entries in a known dictionary, the stream is invalid.

Token tables are stream-local but document-persistent. `BODY_BEGIN`,
`STYLE_BEGIN`, and future stream switches select the token table for that stream
kind; they do not reset it. A dictionary should be imported in the stream where
its tokens are used, but it only needs to be imported once per document per
stream kind. Re-importing the same dictionary/count in the same stream is a
no-op; an incompatible re-import is a malformed stream.

`PIN_LIST` replaces the single-entry `PIN`; a one-item list covers that case. `PIN_RANGE` is intentionally omitted because standard dictionaries are expected to be ordered by frequency, making `IMPORT count` the useful contiguous-range operation.

Subcommand ids `08` and above are reserved for future use (additional dictionary operations, compression hints, etc.).

---

## 4. INLINE_VALUE Values (03)

`INLINE_VALUE` encodes a literal value and may optionally define a custom dictionary token for that value. The header byte follows `03`:

```
bits 0..3: value type (0..15)
bits 4..5: reserved, must be zero in v1
bit 6:     DEFINE - bind the value to the next available token id
bit 7:     USE    - emit/use the value at the current stream position
```

Combinations:

| Flags | Meaning |
|---|---|
| `USE` | Plain inline value; no token is created |
| `DEFINE` | Define a custom token for later use; nothing is emitted |
| `DEFINE + USE` | Define a custom token and use the value immediately |

The `00` flag combination is reserved. Special/standard dictionary token types cannot be declared through this mechanism; `INLINE_VALUE` declarations are only for custom literal values.

| Type nibble | Name | Data | Semantics |
|---|---|---|---|
| `0` | `uint` | varint | unsigned integer; prefer `INLINE_BYTE` for 0..255 |
| `1` | `nint` | varint | negative integer, `value = -(raw + 1)` |
| `2` | `color` | 2 bytes, little-endian RGB565 | compact opaque color value |
| `3` | `name` | varint length + UTF-8 | identifier: script variable/function name, attribute name |
| `4` | `string` | varint length + UTF-8 | string constant or text attribute value |
| `5` | `text` | varint length + UTF-8 | visible text run inside an element |
| `6` | `float32` | 4 bytes, little-endian IEEE-754 binary32 | approximate real number |
| `7` | `fixed16_16` | 4 bytes, little-endian signed int32 | fixed-point real number, `value = raw / 65536` |
| `8` | `colorEx` | 4 bytes, ARGB8888 | full 32-bit color value with alpha |
| `9` | `blob` | varint length + raw bytes | binary data blob |
| `A..F` | reserved | | |

All three string types (`name`, `string`, `text`) encode identically at the byte level — varint length followed by UTF-8 data. The type tag carries semantic intent:

- **`name`** — an identifier used as a script symbol, function name, or attribute name. Must be a valid identifier token. The validator rejects non-identifier characters.
- **`string`** — a string constant or the text value of an attribute (e.g. `placeholder="Your name"`, `href="/docs"`). No character restrictions beyond valid UTF-8.
- **`text`** — visible text content inside a DOM element (a text run). Renderable by the layout engine. Whitespace handling follows text-run rules.

### 4.1 Binary Blobs

`blob` stores arbitrary binary data as a varint byte length followed by raw bytes. It is intended for small inline assets and script constants such as embedded images, lookup tables, masks, prebuilt bytecode fragments, or other prepared binary data.

In source LHT, the same value may be written as hex or base64 for authoring convenience. Binary LHT stores only the decoded bytes; the original textual representation is not preserved.

`blob` is distinct from `string` and `text`: it has no UTF-8 requirement, no text-run semantics, and no automatic text compression.

### 4.2 Color Encodings

LHT binary should support two inline color encodings in v1:

- **`color`**: compact opaque RGB565, stored as a little-endian 16-bit value with bit layout `rrrrrggg gggbbbbb`. This is the preferred form for simple opaque colors when small size and old-client friendliness matter.
- **`colorEx`**: full ARGB8888, stored as four bytes in `A, R, G, B` order. This is used when alpha or full 8-bit-per-channel precision is required.

RGB565 is preferred over ARGB4444 for the compact form because the common case is opaque UI and document colors, where preserving green precision is usually more useful than spending four bits on alpha. Transparency remains available through `colorEx`.

The compact form is also enough for short hex colors such as `#49C`: after expansion to 8-bit channels, the values quantize naturally into RGB565. Many more precise source colors may also be acceptable as `color` after rounding, especially on VGA-like targets where the palette precision is 6-6-6 anyway.

Canonical encoders should use `color` when the source color is opaque and can tolerate RGB565 quantization, and `colorEx` when alpha is not fully opaque or exact 8-bit channel values must be preserved.

### 4.3 Real Number Encodings

LHT binary should support two inline real encodings in v1:

- **`float32`**: IEEE-754 binary32, stored little-endian. This is the escape hatch for values that need the range, precision, or bit-level behavior of a normal single-precision float.
- **`fixed16_16`**: signed 16.16 fixed point, stored as a little-endian `int32`, with `value = raw / 65536`. Its range is approximately `-32768.0 .. 32767.99998474121`.

The motivation is not compactness: both encodings are 4 bytes. The motivation is execution model. Clients with a fast FPU can decode either representation to native float once and continue normally. Clients without a fast FPU can keep `fixed16_16` values as integers and perform comparisons, additions, subtractions, and many multiplications without touching floating-point code.

This matters for older or smaller targets. On a Pentium-class machine, the FPU path may be preferable. On a 286-class target, even if a numeric coprocessor exists, fixed-point arithmetic may still be simpler or faster when the value range allows it.

Encoder policy:

- Prefer `fixed16_16` when the value is finite, within the fixed range, and can be represented exactly as `raw / 65536`.
- Use `float32` when fixed-point would lose required precision, exceed the fixed range, or when preserving the source `float32` representation matters.
- If an encoder has a lossy/compact mode, it may choose `fixed16_16` with an explicit tolerance, but the canonical lossless mode should not silently round arbitrary real values into fixed-point.

Decoders should treat the two encodings as semantically equivalent real-number constants, while being free to choose their internal representation. A no-FPU decoder may expose fixed values directly and convert `float32` only on demand or via a slower software fallback.

Because LHT binary has no array literal at this level, each constant is encoded independently. There is no need for a homogeneous numeric block encoding or shared scale in v1.

### 4.4 Inline Byte

`INLINE_BYTE` (`04`) is a short form for the most common numeric literals in the 0..255 range:

```
04 0C   ; uint 12
04 FF   ; uint 255
```

It is semantically equivalent to `INLINE_VALUE` with `USE + uint`, but it avoids the header byte. This matters for small dimensions, counters, indices, enum-like values, and other short constants. Canonical encoders should prefer `INLINE_BYTE` over `03 80 xx` for unsigned byte values in the 0..255 range.

---

## 5. Text-Run Compression

Natural-language text runs do not need to be compressed one by one. An encoder may aggregate document text runs into a common text storage stream and compress that stream as a whole. This is useful for documentation-like LHT files where visible text can easily reach 50..100 KB.

The v1 codec set should stay deliberately small:

| Codec byte | Name | Meaning |
|---|---|---|
| `00` | `raw` | Uncompressed UTF-8 text bytes |
| `01` | `lzss4k` | LZSS with a 4096-byte sliding window |

`lzss4k` profile:

- Window: 4096 bytes.
- Minimum match length: 3 bytes.
- Match length: 3..18 bytes.
- Back-reference token: 12-bit offset + 4-bit length field (`length = field + 3`).
- Control byte: 8 items, one bit per item; each item is either a literal byte or a 2-byte back-reference.
- Decoder memory requirement: one 4 KB ring buffer plus a small bit/control reader.

This profile is chosen over plain Huffman because a shared text stream contains repeated words, terms, phrases, and UTF-8 byte sequences. It is chosen over LZH/DEFLATE because the decoder is smaller, faster, and uses little memory. It also has a good chance of matching or being close to existing system-library LZSS-style routines on older platforms.

Encoders should keep `raw` when LZSS does not reduce size after headers. Decoders must always support `raw`; `lzss4k` is the preferred compressed profile for v1 text storage.

---

## 6. Skip Algorithm

The stream is structurally self-describing using only values 00..04:

```
depth = 1
while depth > 0:
  v = read_varint()
  if v == 00 (END):       depth--
  elif v == 01 (START):   read_varint()   ; consume element token
                          depth++
  elif v == 02 (COMMAND): skip_command()  ; read subcommand + fixed args
  elif v == 03 (INLINE):  skip_inline()   ; read header byte + data
  elif v == 04 (BYTE):    read_byte()      ; consume inline byte value
  else:                   skip_attrs()     ; bare token: skip following ATTRs
```

No dictionary lookup is required to skip an unknown subtree.

---

## 7. Encoding Examples

### 7.1 Simple element with attributes

Source: `<spacer width=12 height=8/>`

```
token(spacer)          ; bare token = self-closing
token(attr:width)
04 0C                  ; INLINE_BYTE 12
token(attr:height)
04 08                  ; INLINE_BYTE 8
```

If `spacer`, `attr:width`, `attr:height` are all in the 05..7F range: **7 bytes total**.

### 7.2 Content-bearing element

Source: `<h1>Page Title</h1>`

```
01 token(h1)           ; START h1
token(text_run)
03 85 0A "Page Title"  ; INLINE_VALUE USE + text "Page Title" (10 bytes)
00                     ; END
```

### 7.3 Preamble fragment

```
02 00  dictId(DOM_CORE_V1)  40                     ; IMPORT first 64 entries
02 01  dictId(DOM_CORE_V1)  02 entry(block) entry(class) ; PIN_LIST by dictionary entry index
02 07  01                                           ; TEXT_CODEC lzss4k
03 C4  04 "hero"                                    ; DEFINE + USE string "hero"
```

---

## 8. Open Questions

None in this draft. The current v1 decisions are:

- `IMPORT` replaces `ADD_DICTIONARY` and reserves an explicit token count.
- `PIN_LIST` replaces single-entry `PIN`.
- `PIN_USE` covers rare standard tokens that should be pinned and emitted immediately.
- `PIN_RANGE` is omitted; dictionary frequency order plus `IMPORT count` covers the useful range case.
- `INLINE_VALUE` uses one header byte with a 4-bit type and `DEFINE` / `USE` flags.
- Integer inline values use `uint` varint and `nint` negative varint; fixed-width integer inline types are omitted.
- Standard dictionaries may define unique enum value tokens. These value types
  are not user-declarable in the stream, but imported dictionary entries may
  provide compact predefined values such as `value:TFontFace:sans` and
  `value:TFontSize:normal`.
