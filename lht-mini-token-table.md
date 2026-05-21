# LHT Mini Token Table

**Status:** temporary implementation table  
**Purpose:** small hand-authored token table for the first `lhtc` vertical slice.

This is not the final standard dictionary. It exists so the reference utility can emit stable token dumps for `examples/minimal/index.lht` before the real dictionaries are designed.

---

## 0. Dictionary Summary

The current mini implementation imports several small dictionaries. Structural
dictionaries are stream-specific, while `ATTR` and `VALUE` are shared
dictionaries imported into whichever stream needs attributes or enum values.

| Dict ID | Name | Stream use | Import count | Current code range | Purpose |
|---:|---|---|---:|---|---|
| `01` | `DICT_DOC_MINI` | DOC | `5` | `05..09` | Document shell |
| `02` | `DICT_DOM_MINI` | DOM | `12` | `05..10` | Visible DOM tags and bare commands |
| `03` | `DICT_STYLE_MINI` | STYLE | `2` | `05..06` | Initial structural style records |
| `04` | `DICT_ATTR_MINI` | DOC, DOM, STYLE | `15` | `20..2E` | Shared attribute/property names |
| `05` | `DICT_VALUE_MINI` | DOM, STYLE | `10` | `40..49` | Shared enum value tokens |
| `06` | `DICT_LJS_MINI` | SCRIPT | `30` | `05..34` | Script keywords, operators, punctuation, and literal markers |

`IMPORT(dict_id,count)` imports the first `count` dictionary entries into the
current stream table. A decoder that knows the dictionary uses these entries; a
decoder that does not know the dictionary can still reserve `count` token slots
to keep subsequent local token numbers stable.

Imports are persistent for the whole document per stream kind. Entering `DOM` or
`STYLE` selects that stream's token table; it does not reset it. The reference
encoder currently emits the needed imports the first time it enters a stream.
Re-importing the same dictionary with the same count is intended to be a no-op;
re-importing it with an incompatible count should be fatal.

---

## 1. Meta Tokens

Mini binary files start with:

```text
4C 48 54 4D 01   ; "LHTM", mini format version 1
```

`LHTM` is a temporary implementation magic for the first vertical slice. It is deliberately distinct from the future normative `LHT1` document magic.

| Code | Name | Meaning |
|---:|---|---|
| `00` | `END` | Close current started element/substream |
| `01` | `START` | Next token starts a container element |
| `02` | `COMMAND` | Command namespace escape |
| `03` | `INLINE_VALUE` | Typed inline literal |
| `04` | `INLINE_BYTE` | One-byte unsigned inline literal |

---

## 2. Mini Commands

Commands are encoded as:

```text
02 commandCode
```

| Code | Name | Meaning |
|---:|---|---|
| `00` | `IMPORT` | Import a mini dictionary by `dict_id,count` |
| `04` | `BODY_BEGIN` | Switch from DOC stream to DOM stream; the next item must be `START body` |
| `05` | `STYLE_BEGIN` | Switch from DOC stream to STYLE stream |

---

## 3. Mini DOC Tokens

The `Entry` column is the stable dictionary entry index used by `IMPORT`,
`PIN_LIST`, and `PIN_USE`. The `Code in minimal stream` column is only the byte
assigned by the current fixture after `IMPORT DICT_DOC_MINI 5` into an empty
DOC token table.

| Entry | Code in minimal stream | Token | Kind | Notes |
|---:|---:|---|---|---|
| `0` | `05` | `element:lhtml` | container | Source root |
| `1` | `06` | `element:head` | container | Metadata container |
| `2` | `07` | `element:title` | container | Plain text title |
| `3` | `08` | `element:meta` | bare | Metadata record |
| `4` | `09` | `element:script` | container | Document script section |

---

## 4. Mini DOM Tokens

After `BODY_BEGIN`, the decoder switches to the DOM token table. The first DOM item must be `START element:body`.

As with DOC tokens, `Entry` is the stable dictionary entry index. The byte code
is a local stream assignment. DOM structural tokens use `DICT_DOM_MINI`; shared
attributes and enum values come from `DICT_ATTR_MINI` and `DICT_VALUE_MINI`.

| Entry | Code in minimal stream | Token | Kind | Notes |
|---:|---:|---|---|---|
| `0` | `05` | `element:body` | container | Visible DOM root |
| `1` | `06` | `element:block` | container | Text-hosting block |
| `2` | `07` | `element:row` | container | Horizontal layout |
| `3` | `08` | `element:spacer` | bare | Empty layout space |
| `4` | `09` | `command:p` | bare command | Paragraph break |
| `5` | `0A` | `command:br` | bare command | Line break |
| `6` | `0B` | `element:span` | container | Inline text run |
| `7` | `0C` | `element:a` | container | Link text run |
| `8` | `0D` | `element:table` | container | Table grid |
| `9` | `0E` | `element:col` | bare | Table column declaration; must appear before `tr` |
| `10` | `0F` | `element:tr` | container | Table row |
| `11` | `10` | `element:td` | container | Table cell |

---

## 5. Mini ATTR Tokens

`DICT_ATTR_MINI` is the shared attribute/property dictionary. The same attribute
tokens are used by DOC, DOM, and STYLE streams.

| Entry | Code in stream | Token | Kind | Notes |
|---:|---:|---|---|---|
| `0` | `20` | `attr:version` | uint | Used on `lhtml` |
| `1` | `21` | `attr:name` | name/string | Metadata name |
| `2` | `22` | `attr:content` | string | Metadata value |
| `3` | `23` | `attr:id` | name/string | DOM id |
| `4` | `24` | `attr:width` | uint | Pixel width |
| `5` | `25` | `attr:height` | uint | Pixel height |
| `6` | `26` | `attr:href` | string | Link target |
| `7` | `27` | `attr:fontFace` | enum `TFontFace` | `default=0`, `sans=1`, `serif=2`, `mono=3` |
| `8` | `28` | `attr:fontSize` | enum `TFontSize` | `tiny=0`, `small=1`, `normal=2`, `large=3`, `xlarge=4`, `xxlarge=5` |
| `9` | `29` | `attr:color` | color RGB565 | Text color |
| `10` | `2A` | `attr:background` | color RGB565 | Body or block background |
| `11` | `2B` | `attr:border` | color RGB565 | Block border |
| `12` | `2C` | `attr:padding` | uint | Uniform inner padding |
| `13` | `2D` | `attr:borderWidth` | uint | Uniform border width |
| `14` | `2E` | `attr:class` | string | Space-separated source class names |

---

## 6. Mini STYLE Tokens

`DICT_STYLE_MINI` currently contains just enough structure for class
declarations:

```text
STYLE_BEGIN
  IMPORT STYLE
  IMPORT ATTR
  IMPORT VALUE
  classDecl "notice"
    set attr:background color
    set attr:padding uint
  END
END
```

| Entry | Code in style stream | Token | Kind | Notes |
|---:|---:|---|---|---|
| `0` | `05` | `command:classDecl` | command | Starts a single `.class` declaration |
| `1` | `06` | `command:set` | command | Sets one shared attribute/property value |

---

## 7. Mini VALUE Tokens

| Entry | Code in stream | Token | Kind | Notes |
|---:|---:|---|---|---|
| `0` | `40` | `value:TFontFace:default` | enum value | Font family default |
| `1` | `41` | `value:TFontFace:sans` | enum value | Sans-serif family |
| `2` | `42` | `value:TFontFace:serif` | enum value | Serif family |
| `3` | `43` | `value:TFontFace:mono` | enum value | Monospace family |
| `4` | `44` | `value:TFontSize:tiny` | enum value | Tiny text |
| `5` | `45` | `value:TFontSize:small` | enum value | Small text |
| `6` | `46` | `value:TFontSize:normal` | enum value | Normal text |
| `7` | `47` | `value:TFontSize:large` | enum value | Large text |
| `8` | `48` | `value:TFontSize:xlarge` | enum value | Extra large text |
| `9` | `49` | `value:TFontSize:xxlarge` | enum value | Double extra large text |

Font enum value tokens are normal imported dictionary tokens, not inline values.
For example:

```text
27 41   ; attr:fontFace value:TFontFace:sans
28 46   ; attr:fontSize value:TFontSize:normal
```

Current attribute/value compatibility:

| Attribute | Accepted value tokens |
|---|---|
| `attr:fontFace` | `value:TFontFace:*` |
| `attr:fontSize` | `value:TFontSize:*` |

---

## 8. Inline Value Policy

For the mini slice:

- integers `0..255` use `INLINE_BYTE`;
- other integers use `INLINE_VALUE uint`;
- text content uses `TEXT "..."` in token dumps and maps to `INLINE_VALUE text` in the mini binary stream;
- string attributes use `INLINE_VALUE string`;
- `fontFace` values use imported `value:TFontFace:*` tokens;
- `fontSize` values use imported `value:TFontSize:*` tokens;
- color attributes use `INLINE_VALUE color` and are packed as RGB565 in the mini binary stream;
- name-like attributes are still dumped as strings until the name/string distinction is useful.

---

## 9. Current Scope

Accepted source surface:

```text
lhtml head title meta style body
block row spacer
p br span a
version id name content width height href
font fontFace fontSize
color background border padding borderWidth class
```

`font` is source shorthand only. The parser normalizes it into canonical
attributes before tokenization:

```text
font=serif,small -> fontFace=serif fontSize=small
font=large       -> fontSize=large
font=mono        -> fontFace=mono
```

Out of scope for this table: images, forms, scripts, compression, external dictionaries, and final token ordering.
