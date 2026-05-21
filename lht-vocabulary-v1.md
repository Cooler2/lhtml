# LHT Vocabulary v1

**Status:** draft inventory  
**Purpose:** complete source-level inventory of DOC/DOM tags, attributes, predefined values, and declaration names before assigning standard dictionary tokens.

This document answers "what words exist in LHT v1?" It does not assign token ids. Standard dictionaries should be derived from this vocabulary after the surface is stable.

---

## 1. Entry Status

| Status | Meaning |
|---|---|
| `v1` | Intended for base LHT v1 |
| `optional-v1` | Valid in v1, but clients may advertise support separately |
| `candidate` | Useful, but needs one more design pass before freezing |
| `extension` | Not base v1; may become an extension |
| `legacy-alias?` | Appears in older prose/examples; decide whether to keep as alias or remove |
| `archive` | Design archive only; not part of v1 |

---

## 2. Source Categories

| Category | Creates DOM node | Binary shape | Notes |
|---|---:|---|---|
| DOC element | sometimes | DOC stream command or metadata record | Top-level document structure |
| DOM container | yes | `START element ... END` | May contain child nodes |
| DOM leaf | yes | bare element token + attributes | No children |
| Bare command | no | bare token + optional attributes | Changes text/paragraph state |
| Text modifier | no | inline style push/pop | No identity, no events |
| Text run | yes | inline run record | Scriptable inline range |
| Inline atom | usually no | inline atom record | Rendered as a glyph-like item |
| Declaration | no | style/DOC declaration record | Resources, images, constants, classes |
| Attribute | no | attribute token + typed value | Valid only in declared contexts |
| Enum value | no | value token | Predefined value for attributes/declarations |

---

## 3. DOC-Level Elements

| Name | Kind | Context | Status | Notes |
|---|---|---|---|---|
| `lhtml` | DOC element | root | v1 | Required root; carries `version` |
| `head` | DOC element | child of `lhtml` | v1 | Metadata only |
| `title` | DOC element | child of `head` | v1 | Plain text title |
| `meta` | DOC leaf | child of `head` | v1 | Name/content metadata pair |
| `style` | DOC element | child of `lhtml` | v1 | Inline style/resource/class declarations; may also reference external style |
| `script` | DOC element/leaf | child of `lhtml` | v1 | Inline script or external script via `src` |
| `library` | DOC leaf | child of `lhtml` | v1 | Isolated script library |
| `body` | DOM container root | child of `lhtml` | v1 | Visible document tree; maps to `BODY_BEGIN` plus `START body` in binary |

`head`, `style`, `script`, and `library` are source-level document constructs. Binary representation may normalize them into DOC substreams and declaration records rather than ordinary DOM nodes.

---

## 4. DOM Elements

### 4.1 Block And Layout Elements

| Name | Kind | Text-hosting | Status | Notes |
|---|---|---:|---|---|
| `body` | DOM container root | yes | v1 | Implicit vertical document flow |
| `block` | DOM container | yes | v1 | Main vertical block container |
| `div` | DOM container | yes | legacy-alias? | Older prose uses it as equivalent to `block`; recommendation: remove or make source alias for `block` only |
| `flow` | DOM container | no | v1 | Wraps child blocks/items into rows |
| `row` | DOM container | no | v1 | Horizontal layout container |
| `fixed` | DOM container | no | candidate | Absolute child positioning; mentioned in layout model, not used in examples |
| `scrollbox` | DOM container | no | v1 | Fixed-size vertical scrolling region |
| `spacer` | DOM leaf | no | v1 | Empty layout space; takes `width`/`height` |
| `canvas` | DOM leaf | no | optional-v1 | Programmable drawing surface; capability gated |

### 4.2 Text-Hosting Blocks

| Name | Kind | Status | Notes |
|---|---|---|---|
| `h1` | DOM container | v1 | Text-hosting heading; default `.h1` class |
| `h2` | DOM container | v1 | Text-hosting heading; default `.h2` class |
| `h3` | DOM container | v1 | Text-hosting heading; default `.h3` class |
| `ul` | DOM container | v1 | Unordered list |
| `ol` | DOM container | v1 | Ordered list |
| `li` | DOM container | v1 | Text-hosting list item |

### 4.3 Table Elements

| Name | Kind | Status | Notes |
|---|---|---|---|
| `table` | DOM container | v1 | Tabular data; not layout grid |
| `col` | DOM leaf | v1 | Column metadata; appears before `tr` |
| `tr` | DOM container | v1 | Table row |
| `td` | DOM container | v1 | Text-hosting table cell |

LHT intentionally does not define separate table section/header elements. Header rows and cells are ordinary `tr`/`td` elements styled with classes.

### 4.4 Inline Text Vocabulary

| Name | Kind | DOM node | Status | Notes |
|---|---|---:|---|---|
| `p` | bare command | no | v1 | Paragraph break; may carry paragraph attributes |
| `br` | bare command | no | v1 | Line break; no attributes |
| `b` | text modifier | no | v1 | Bold style push |
| `i` | text modifier | no | v1 | Italic style push |
| `u` | text modifier | no | v1 | Underline style push |
| `s` | text modifier | no | v1 | Strikethrough style push |
| `sup` | text modifier | no | candidate | Baseline shift rule still open |
| `sub` | text modifier | no | candidate | Baseline shift rule still open |
| `small` | text modifier | no | candidate | Size step rule still open |
| `span` | text run | yes | v1 | Scriptable inline text range |
| `a` | text run | yes | v1 | Link text run |
| `img` | DOM leaf or inline atom | yes in block context; no in inline context? | v1 | Logical image reference by `name`; inline usage behaves as atom |
| `text` | explicit text container | yes | legacy-alias? | Older prose uses it; current examples place inline text directly in text-hosting blocks |

### 4.5 Forms

| Name | Kind | Status | Notes |
|---|---|---|---|
| `input` | DOM leaf | candidate | Used in examples; exact input types/attributes need formal table |
| `button` | DOM container | candidate | Used in examples; text-hosting clickable control |
| `textarea` | DOM leaf/container | candidate | Mentioned conceptually, not specified |
| `select` | DOM container | candidate | Mentioned conceptually, not specified |
| `option` | DOM container/leaf | candidate | Needed if `select` is kept |
| `form` | DOM container | archive | Current model has no built-in form container; submission is scripted |

---

## 5. DOC And Style Declarations

| Name | Kind | Context | Status | Notes |
|---|---|---|---|---|
| `@resource` | declaration | `style` | v1 | Names a physical resource or conditional resource variants |
| `@imageDef` | declaration | `style` | v1 | Defines a logical image |
| `const` | declaration | `style` | v1 | Named typed constant |
| `.class` | declaration | `style` | v1 | Named bundle of attributes |
| `.class:state` | declaration | `style` | v1 | State-specific class attributes |
| `when` | declaration clause | `@resource`, `@imageDef`, constants | v1 | Capability predicate branch |
| `@fontDef` | declaration | `style` | extension | Downloadable font extension only |
| `compose` | declaration operation | `@imageDef` | extension | Future idea; base v1 should prefer script/canvas-generated images |

---

## 6. Global Attributes

| Name | Type | Context | Default | Status | Notes |
|---|---|---|---|---|---|
| `id` | name | DOM nodes, text runs | none | v1 | Script lookup key |
| `class` | class-list | DOM nodes, text runs, `p` | none | v1 | Space-separated class names in source |
| `role` | name/enum | DOM nodes | none | candidate | Accessibility/semantic hint; not otherwise specified |
| `title` | string | DOM nodes | none | candidate | Tooltip/accessibility hint; conflicts only by name with `<title>` source element |
| `name` | name | `img`, `input`, `meta`, resource/image declarations | context-specific | v1 | Logical image name, field name, metadata name |
| `value` | typed value | form controls | control-specific | candidate | Needs form spec |
| `disabled` | bool | controls, interactive elements | false | v1 | Also usable as class state |
| `focusable` | bool | DOM nodes | inferred | v1 | Allows keyboard focus |

---

## 7. Layout Attributes

| Name | Type | Context | Default | Status | Notes |
|---|---|---|---|---|---|
| `width` | length/fraction/enum | block/layout/leaf/table/col/canvas/img/input | `auto` or context-specific | v1 | `fill` valid in selected contexts |
| `height` | length/fraction/enum | block/layout/leaf/canvas/img | `auto` or content | v1 | Required for `canvas`; required with `width` for `scrollbox` |
| `x` | length | overlay/fixed-positioned children | none | v1 | Required with `overlay` |
| `y` | length | overlay/fixed-positioned children | none | v1 | Required with `overlay` |
| `overlay` | bool | block-level elements | false | v1 | Removes element from normal flow |
| `padding` | length1-4 | block/table/text run/cell/classes | 0 | v1 | CSS-like 1-4 value shorthand in source |
| `paddingLeft` | length | block/table/text run/cell/classes | from `padding` | v1 | Edge-specific form |
| `paddingRight` | length | block/table/text run/cell/classes | from `padding` | v1 | Edge-specific form |
| `paddingTop` | length | block/table/text run/cell/classes | from `padding` | v1 | Edge-specific form |
| `paddingBottom` | length | block/table/text run/cell/classes | from `padding` | v1 | Edge-specific form |
| `border` | border shorthand | block/table/text run/cell/classes | none | v1 | Usually `width, color` |
| `borderLeft` | border/length | block/table/col/tr/td/classes | none | v1 | Edge-specific border |
| `borderRight` | border/length | block/table/col/tr/td/classes | none | v1 | Edge-specific border |
| `borderTop` | border/length | block/table/col/tr/td/classes | none | v1 | Edge-specific border |
| `borderBottom` | border/length | block/table/col/tr/td/classes | none | v1 | Edge-specific border |
| `align` | enum | table/col/tr/td/block? | context-specific | v1 | Horizontal content alignment |
| `valign` | enum | table/col/tr/td/inline `img` | `top` or `baseline` | v1 | Vertical alignment |
| `overflowX` | enum | block/table/text host | `clip` | v1 | `clip`, `scroll`, `auto` |
| `nowrap` | bool | flow children, text hosts, text runs | false | v1 | Prevents line break within item |
| `bgColor` | color | block/text/table/col/tr/td/canvas/classes | transparent/inherit? | v1 | Background color |

There is no `margin` and no `overflowY` in v1.

---

## 8. Text Attributes

| Name | Type | Context | Default | Status | Notes |
|---|---|---|---|---|---|
| `font` | font-name | text-hosting elements, text runs, classes | inherited/default | v1 | Logical bitmap font name |
| `color` | color | text-hosting elements, text runs, classes | inherited/system | v1 | Foreground color |
| `bold` | bool | text modifiers/classes/text runs | false | v1 | Also represented by `<b>` |
| `italic` | bool | text modifiers/classes/text runs | false | v1 | Also represented by `<i>` |
| `underline` | bool | text modifiers/classes/text runs | false | v1 | Also represented by `<u>` |
| `strikethrough` | bool | text modifiers/classes/text runs | false | v1 | Also represented by `<s>` |
| `lineHeight` | length | text-hosting elements/classes | font intrinsic | v1 | Baseline distance |
| `textAlign` | enum | text-hosting elements, `p`, classes | `left` | v1 | `left`, `right`, `center`, `justify` |
| `letterSpacing` | length | text-hosting elements/classes | 0 | v1 | No kerning/ligatures |
| `wordSpacing` | length | text-hosting elements/classes | 0 | v1 | Extra spacing between words |
| `paraSpacing` | length | text-hosting blocks/classes | 0 | v1 | Default spacing for bare `<p>` |
| `indent` | length | `p` | 0 | v1 | First-line indent from paragraph break |
| `spacing` | length | `p` | from parent | v1 | Extra vertical space before paragraph |

---

## 9. Link, Media, And Resource Attributes

| Name | Type | Context | Default | Status | Notes |
|---|---|---|---|---|---|
| `href` | string/URL | `a` | required | v1 | Navigation URL |
| `target` | enum | `a` | `same` | v1 | `same`, `new`; minimal clients may ignore `new` |
| `src` | resource/image/script URL or name | `style`, `script`, `library`, `@imageDef` | required where used | v1 | Meaning is context-specific |
| `alt` | string | `img` | empty | v1 | Fallback/accessibility text |
| `crop` | rect4 | `@imageDef` | none | v1 | `x,y,w,h` source rectangle |
| `flipX` | bool flag | `@imageDef` | false | v1 | Horizontal mirror |
| `flipY` | bool flag | `@imageDef` | false | v1 | Vertical mirror |
| `tint` | color | `@imageDef` | none | v1 | Color remap/multiply |
| `patch9` | rect4 | `@imageDef` | none | v1 | Fixed margins for 9-patch rendering |
| `placeholder` | image-name | `@imageDef` | built-in placeholder | v1 | Fallback logical image |
| `required` | bool flag | `@resource` | false | v1 | Early-load hint |
| `data` | blob/base64 | `@resource` | none | v1 | Inline small resource bytes |
| `interface` | name | `library` | required | v1 | Global binding name for isolated library |
| `integrity` | string | `library`, maybe external resources | none | v1 | Hash check for externally loaded code |

---

## 10. Table Attributes

| Name | Type | Context | Default | Status | Notes |
|---|---|---|---|---|---|
| `colspan` | uint | `td` | 1 | v1 | Horizontal cell span |
| `rowspan` | uint | `td` | 1 | v1 | Vertical cell span |
| `internalBorders` | length | `table` | none | v1 | Both horizontal and vertical internal grid lines |
| `internalHBorders` | length | `table` | none | v1 | Horizontal internal grid lines |
| `internalVBorders` | length | `table` | none | v1 | Vertical internal grid lines |

Column defaults use common attributes on `col`: `width`, `class`, `bgColor`, `align`, `valign`, `font`, `color`, `padding`, and border edge attributes.

---

## 11. List Attributes

| Name | Type | Context | Default | Status | Notes |
|---|---|---|---|---|---|
| `marker` | string/enum | `ul` | bullet | v1 | `none` suppresses marker |
| `type` | enum | `ol`, `input` | `1` for `ol`; text for `input`? | candidate | Overloaded; input values need form spec |
| `start` | int | `ol` | 1 | v1 | Initial ordered-list counter |

---

## 12. Form Attributes

Form controls are used in examples, but the exact v1 surface is not fully specified yet.

| Name | Type | Context | Default | Status | Notes |
|---|---|---|---|---|---|
| `type` | enum | `input` | `text` | candidate | Suggested: `text`, `password`, `number`, `checkbox`, `radio`, `range` |
| `placeholder` | string | `input`, `textarea` | empty | candidate | Hint text |
| `checked` | bool | checkbox/radio input | false | candidate | Needs final input model |
| `min` | int/float | number/range input | none | candidate | Needs numeric form model |
| `max` | int/float | number/range input | none | candidate | Needs numeric form model |
| `step` | int/float | number/range input | 1 | candidate | Needs numeric form model |
| `multiline` | bool | input? | false | candidate | Prefer separate `textarea` if kept |

Recommendation: freeze `input` and `button` first, defer `textarea`, `select`, and advanced controls unless examples require them.

---

## 13. Event Handler Attributes

Source may spell these as camelCase (`onClick`) or canonical token names may normalize them to event names without `on`.

| Attribute | Event | Context | Status |
|---|---|---|---|
| `onClick` | `click` | interactive DOM nodes/text runs | v1 |
| `onDblClick` | `dblclick` | interactive DOM nodes/text runs | v1 |
| `onMouseDown` | `mousedown` | interactive DOM nodes/text runs | v1 |
| `onMouseUp` | `mouseup` | interactive DOM nodes/text runs | v1 |
| `onMouseEnter` | `mouseenter` | interactive DOM nodes/text runs | v1 |
| `onMouseLeave` | `mouseleave` | interactive DOM nodes/text runs | v1 |
| `onMouseMove` | `mousemove` | interactive DOM nodes/text runs | v1 |
| `onKeyDown` | `keydown` | focusable elements | v1 |
| `onKeyUp` | `keyup` | focusable elements | v1 |
| `onKeyPress` | `keypress` | focusable elements | v1 |
| `onFocus` | `focus` | focusable elements | v1 |
| `onBlur` | `blur` | focusable elements | v1 |
| `onInput` | `input` | form controls | v1 |
| `onChange` | `change` | form controls | v1 |
| `onScroll` | `scroll` | `scrollbox`, viewport | v1 |
| `onParsed` | `parsed` | document | v1 |
| `onLayout` | `layout` | document | candidate |
| `onRendered` | `rendered` | document | candidate |
| `onLoad` | `load` | document | v1 |
| `onUnload` | `unload` | document | v1 |
| `onResize` | `resize` | document | v1 |
| `onError` | `error` | document | v1 |

Open detail: lifecycle events should probably remain document-level script registrations (`document.on(...)`) rather than ordinary attributes on `body`.

---

## 14. Capability Predicates

| Name | Type | Status | Values/meaning |
|---|---|---|---|
| `minDepth` | int | v1 | Minimum color depth: `1`, `4`, `8`, `15`, `16`, `24` |
| `minCpu` | enum | v1 | `8086`, `286`, `386`, `486`, `586`, `686+` |
| `hasFpu` | bool | v1 | FPU available |
| `hasMmx` | bool | v1 | MMX or similar SIMD available |
| `minRamKb` | int | v1 | Minimum RAM in KB |
| `minWidth` | int | v1 | Minimum display width |
| `minHeight` | int | v1 | Minimum display height |
| `media` | enum | v1 | `screen`, `print`, `speech` |
| `canvas` | enum | v1 | `none`, `basic`, `full` |

---

## 15. Predefined Values

### 15.1 Boolean And Null-Like Values

```text
true
false
none
null
inherit
```

`null` is script-facing; `none` is usually an attribute enum value.

### 15.2 Sizing And Overflow

```text
auto
fill
clip
scroll
```

`auto` is not valid for table column widths.

### 15.3 Alignment

```text
left
right
center
justify
top
middle
bottom
baseline
```

`justify` may degrade to `left` on minimal clients.

### 15.4 Link Targets

```text
same
new
```

### 15.5 List Markers And Ordered List Types

```text
none
disc
1
a
A
i
I
```

`disc` is a proposed canonical enum for the default unordered marker; source may also allow a literal marker string.

### 15.6 States

```text
hover
active
focus
disabled
visited
```

`visited` applies mainly to links. `disabled` applies to controls and class variants.

### 15.7 Resource Types

```text
gif
jpeg
bitmap
font
style
script
lhv
lhd
```

`font` is extension-facing in base v1. `lhd` appears in examples/discussion as dictionary resource type and should be specified if external dictionaries remain in v1.

### 15.8 Input Types

```text
text
password
number
checkbox
radio
range
button
```

Candidate until the form control model is written.

### 15.9 Canvas Levels

```text
none
basic
full
```

### 15.10 CPU Classes

```text
8086
286
386
486
586
686+
```

---

## 16. System Names

### 16.1 System Colors

```text
systemText
systemWindow
systemButtonFace
systemButtonText
systemLink
systemVisitedLink
highlight
highlightText
```

This list should be completed before creating `STYLE_CORE_V1` or a color/value dictionary.

### 16.2 Built-In Font Names

Families:

```text
default-sans
default-serif
default-mono
default-heading
```

Common logical names:

```text
default-sans-8
default-sans-10
default-sans-12
default-sans-14
default-sans-18
default-serif-10
default-serif-12
default-serif-14
default-serif-18
default-mono-8
default-mono-10
default-mono-12
default-heading-18
default-heading-24
default-heading-32
```

Style suffixes:

```text
bold
italic
bold-italic
```

---

## 17. Recommended Dictionary Placement

This is a preliminary mapping, not a token assignment.

| Vocabulary area | Suggested dictionary |
|---|---|
| `lhtml`, DOC substreams, `head`, metadata records | `DOC_CORE_V1` |
| DOM elements and bare commands | `DOM_CORE_V1` |
| Common attributes | `ATTR_CORE_V1` or early entries in `DOM_CORE_V1` |
| Common enum values: `fill`, `auto`, alignments, booleans | `DOM_VALUE_V1` or early entries in `DOM_CORE_V1` |
| Style properties and class/state declarations | `STYLE_CORE_V1` |
| Resource types, image operations, capability predicates | `RESOURCE_CORE_V1` |
| Event names and handler attributes | `EVENT_CORE_V1` |
| Script keywords, operators, builtins | `LJS_CORE_V1` |

Recommendation for the first implementation: use one practical `DOM_CORE_V1` for elements, common attributes, and common values, then split only when token frequency or decoder simplicity justifies it.

---

## 18. Cleanup Decisions Exposed By This Inventory

1. Decide whether `div` remains a source alias for `block` or is removed from v1 prose.
2. Decide whether explicit `<text>` remains in source syntax. Current examples use direct inline text inside text-hosting blocks.
3. Specify the form surface: at minimum `input`, `button`, `type`, `value`, `placeholder`, `checked`, `disabled`.
4. Decide whether `fixed` is a v1 container or an extension/candidate.
5. Resolve text modifier open details: `small`, `sup`, `sub`.
6. Confirm whether inline `<img>` creates a script-visible DOM node or remains an atom without identity in inline context.
7. Complete the system color list.
8. Decide whether lifecycle event attributes exist, or only `document.on(...)` registrations.
9. Specify external dictionary resource type `lhd` if dictionaries can be loaded as resources.
