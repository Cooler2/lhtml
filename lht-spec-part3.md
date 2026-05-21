# Light HyperText Format (LHT) — Specification Draft, Part 3

**Version:** 0.1 (draft)
**Status:** Work in progress
**Continues from:** lht-spec-part2.md (sections 5-6)

---

## Table of Contents (this document)

7. [Inline Content](#7-inline-content)
8. [Events](#8-events)
9. [Scripts](#9-scripts)

(Sections 10–11 and Appendices are in lht-spec-part4.md.)

---

## 7. Inline Content

### 7.1 Overview

Inline content is text and text-like elements that flow within a line, wrapping to the next line when they don't fit. LHT uses a three-level model that explicitly separates three different kinds of inline entities:

| Level | Examples | Identity | In DOM | Events |
|---|---|---|---|---|
| **Text modifiers** | `<b>`, `<i>`, `<u>`, `<s>`, `<sub>`, `<sup>`, `<small>` | No | No | No |
| **Text runs** | `<span>`, `<a>` | Yes | Yes (leaf) | Yes |
| **Inline atoms** | `<img>` (inline) | No | No | No |

Text modifiers are pure style switches — they modify how subsequent text is rendered but have no identity and no DOM presence. Text runs have identity and can be addressed from scripts and event handlers. Inline atoms are fixed-size objects embedded in the text flow.

This separation keeps the text rendering pipeline simple (a single linear pass with a style stack) while still supporting interactive inline elements like links and script-updatable spans.

### 7.2 Text-hosting containers

Inline content may be placed directly inside **text-hosting** block elements: `<div>`, `<block>`, `<li>`, and `<td>`. No explicit wrapper element is required.

```
<div>
  This is a paragraph. Some words are <b>bold</b> and some are
  <a href="/link">linked</a>.
</div>
```

Paragraph breaks within a text-hosting block are expressed with `<p>` and `<br>` commands — bare tokens, not containers (Section 7.2.1). Block-level children and text may be freely mixed:

```
<div>
  Introduction: the chart below shows monthly revenue.
  <canvas id="chart" width=400 height=200/>
  Values are in thousands of USD.
</div>
```

**Non-text-hosting containers** — `<row>`, `<flow>`, `<table>`, `<tr>`, `<col>` — do not accept inline content directly. Inline content inside them is a tokenization error.

#### 7.2.1 `<p>` and `<br>` — paragraph and line breaks

`<p>` and `<br>` are paragraph-control commands. They are bare tokens — not containers, no children, no closing tag. The analogy: `<br>` is Shift+Enter (new line, same paragraph), `<p>` is Enter (new paragraph, with vertical spacing).

- **`<br>`** — forced line break within the current paragraph. Text continues on the next line; no extra vertical spacing is added.
- **`<p>`** — paragraph break. Ends the current paragraph and begins a new one, inserting inter-paragraph vertical spacing. Optionally resets paragraph-level attributes.

```
<div>
  First paragraph.
  <p>
  Second paragraph — spaced below the first.
  <br>
  Same paragraph, new line, no spacing.
  <p indent=1>
  Third paragraph with first-line indent.
</div>
```

In the binary stream both are bare tokens. `<p>` may be followed by `ATTR` commands that apply to the new paragraph; `<br>` carries no attributes.

Attributes on `<p>` (apply from this paragraph break until the next `<p>`, `<h*>`, or `END` of the containing block):

| Attribute | Type | Default | Effect |
|---|---|---|---|
| `indent` | length | 0 | First-line indent in pixels |
| `spacing` | length | from parent | Extra vertical space inserted above this paragraph break |
| `textAlign` | enum | from parent | `left`, `right`, `center`, `justify` |
| `class` | class-ref | — | Named style applied to this paragraph |

Default paragraph spacing is set by the containing block's `paraSpacing` attribute (defaults to 0 if not set).

#### 7.2.2 `<h1>`, `<h2>`, `<h3>` — headings

`<h1>`, `<h2>`, `<h3>` are text-hosting block containers — unlike `<p>`, they explicitly wrap their content with `START`/`END`. This makes the heading boundary unambiguous and allows the renderer to apply heading style to exactly the enclosed text.

Each heading element automatically applies its default class from the system bundle:

| Element | Default class | Typical font |
|---|---|---|
| `<h1>` | `.h1` | `default-heading-24` bold |
| `<h2>` | `.h2` | `default-heading-18` bold |
| `<h3>` | `.h3` | `default-sans-14` bold |

Authors may redefine these classes in their `<style>` block:

```css
.h1 { font: default-heading-32; color: primary; }
.h2 { font: default-heading-24; }
```

```
<div>
  <h1>Page Title</h1>
  Introductory text.
  <p>
  Second paragraph.
  <h2>Section One</h2>
  Section content.
</div>
```

In the binary stream headings use `START`/`END` like any block container. Explicit attributes override the default class:

```
START h1
  ATTR color CLASS_REF primary
  TEXT_RUN "Page Title"
END
```

#### 7.2.3 `<ul>`, `<ol>`, `<li>` — lists

`<ul>` (unordered) and `<ol>` (ordered) are block containers with predefined system-bundle classes that add default left padding. `<li>` is a text-hosting block element — like `<div>`, it accepts both inline content and block-level children (enabling nested lists and complex list items).

```
<ul>
  <li>Simple item</li>
  <li>Item with sub-list
    <ul>
      <li>Sub-item 1</li>
      <li>Sub-item 2</li>
    </ul>
  </li>
  <li><b>Bold item</b> with <a href="/x">a link</a></li>
</ul>

<ol type=1 start=3>
  <li>Third item</li>
  <li>Fourth item</li>
</ol>
```

**Marker rendering.** The client draws the marker (bullet or number) inside the left padding zone of each `<li>`. The system-bundle default `<li>` paddingLeft is wide enough to accommodate the marker without overlapping content. Authors who override `paddingLeft` on `<li>` are responsible for leaving room for the marker.

For `<ol>`, the client tracks a counter per list, incrementing it for each `<li>`. Nested `<ol>` elements have independent counters that reset to `start` (default 1).

**Attributes on `<ul>`:**

| Attribute | Type | Default | Effect |
|---|---|---|---|
| `marker` | string | `•` | Bullet character; `none` suppresses the marker |

**Attributes on `<ol>`:**

| Attribute | Type | Default | Effect |
|---|---|---|---|
| `type` | enum | `1` | Number format: `1` (1 2 3), `a` (a b c), `A` (A B C), `i` (i ii iii), `I` (I II III) |
| `start` | int | `1` | Starting counter value |

**Class overrides.** The predefined classes `.ul`, `.ol`, `.li` in the system bundle define default spacing and marker sizing. Authors may redefine them:

```css
.li { paddingLeft: 20; }
.ul { marker: "–"; }
```

### 7.3 Text modifiers

Text modifiers change the rendering style of the text they wrap. They have no identity, are not present in the DOM as nodes, and cannot be addressed from scripts.

| Element | Effect |
|---|---|
| `<b>` | Bold — switches to the bold variant of the current font |
| `<i>` | Italic — switches to the italic variant |
| `<u>` | Underline |
| `<s>` | Strikethrough |
| `<sup>` | Superscript — smaller font, raised baseline |
| `<sub>` | Subscript — smaller font, lowered baseline |
| `<small>` | One font size step smaller (e.g., 12 → 10) |

Modifiers may be nested freely. The renderer maintains a style stack: entering `<b>` pushes bold, exiting it pops. Entering `<b><i>` produces bold-italic:

```
<text>
  Normal, <b>bold, <i>bold-italic,</i> bold again,</b> normal.
</text>
```

Text modifiers may not contain text runs or inline atoms — only text and other modifiers. (A link inside bold is expressed by placing `<a>` inside `<b>`, not the other way; `<b>` wraps `<a>`.)

Text modifiers do not accept `class`, `id`, `onClick`, or any attribute other than those that directly map to font/style switches. If identity or events are needed, use a text run (`<span>`) instead.

### 7.4 Text runs

A text run is an inline element with identity. It flows with the surrounding text, wraps across lines, and can be addressed from scripts and event handlers.

#### 7.4.1 `<span>`

`<span>` is the generic text run. It applies a style and/or provides a scriptable identity for a range of text:

```
<text>
  Status: <span id="status" color=#008000>online</span>
</text>
```

Script access:
```js
getElement("status").text = "offline";
getElement("status").color = #FF0000;
```

Attributes:
- `id`, `class` — identity and styling
- `onClick`, `onMouseEnter`, `onMouseLeave` — event handlers
- `color`, `font`, `bold`, `italic`, `underline`, `bgColor` — style overrides for this run
- State variants via class (e.g., `.highlight:hover`)

#### 7.4.2 `<a>` — links

`<a>` is a text run that navigates to a URL when activated. It inherits all `<span>` capabilities and adds:

| Attribute | Type | Effect |
|---|---|---|
| `href` | string | URL to navigate to on click |
| `target` | enum | `same` (default) — current window; `new` — new window/tab |

Default visual treatment (may be overridden via class):
- Unvisited: `systemLink` color, underline
- Visited: `systemVisitedLink` color, underline
- Hover: client-defined highlight (typically slightly brighter)

```
<text>
  See the <a href="/docs/api">API documentation</a> for details.
</text>
```

`<a>` elements participate in the normal event system. An `onClick` handler on an `<a>` can call `event.preventDefault()` to suppress navigation.

#### 7.4.3 Content rules for text runs

A text run may contain:
- Text (strings)
- Text modifiers (`<b>`, `<i>`, etc.)
- Inline atoms (`<img>`)

A text run may **not** contain:
- Other text runs (no nested `<span>` or `<a>`)
- Block-level elements

This restriction keeps the hit-test and event model simple. If nested interactive regions are needed, restructure as sibling text runs:

```
<!-- wrong: nested <a> -->
<a href="/outer"><b>text <a href="/inner">link</a> more</b></a>

<!-- correct: sibling runs -->
<a href="/outer"><b>text </b></a><a href="/inner"><b>link</b></a><a href="/outer"><b> more</b></a>
```

#### 7.4.4 Line wrapping of text runs

Text runs wrap across lines naturally. Padding and borders on a text run are rendered only on the first and last line of the run (the open ends where the run continues to the next line have no padding/border). This matches the intuitive expectation for inline highlights and link underlines.

`nowrap` on a text run prevents line breaks within it — the run moves to the next line as a unit if it doesn't fit:

```
<text>
  Click <span nowrap><img name="send-icon"/> Send</span> to submit.
</text>
```

### 7.5 Inline atoms

An inline atom is a fixed-size object embedded in the text flow. It is treated as a single indivisible unit — like a large glyph — for the purposes of line breaking and layout.

#### 7.5.1 `<img>` as inline atom

`<img>` may appear inside a `<text>` element or text run, where it behaves as an inline atom:

```
<text>
  Status: <img name="ok-icon" width=12 height=12/> all systems operational.
</text>
```

Sizing follows the same rules as block-context `<img>` (Section 5.4): explicit `width`/`height` if given, otherwise natural size. Aspect ratio is preserved if only one dimension is given.

Vertical alignment within the line: the atom's bottom edge aligns to the text baseline by default. The `valign` attribute overrides this:

| Value | Meaning |
|---|---|
| `baseline` (default) | Bottom edge at text baseline |
| `middle` | Center of atom at mid-x-height |
| `top` | Top edge at line top |

#### 7.5.2 No other inline atoms in v1

In v1, `<img>` is the only inline atom. Inline form inputs (`<input>` embedded in text) and inline canvas are not supported in v1.

### 7.6 Line breaking

#### 7.6.1 Break opportunities

The line breaker may break the text flow at:
- Whitespace between words
- After a hyphen character (`-`) in a word
- At soft-hyphen codepoints (U+00AD) — the hyphen is rendered only when a break occurs there

Breaks may **not** occur:
- Inside a word (no arbitrary character breaks)
- Inside a `nowrap` span or `<text nowrap>` element
- Inside an inline atom

#### 7.6.2 Algorithm

Line breaking runs as a single forward pass over the inline content of a `<text>` element:

1. Accumulate words and inline atoms onto the current line.
2. When the next item would overflow the line width, emit the current line and start a new one.
3. Apply `textAlign` to each completed line.
4. The last line uses `textAlign` for `left`, `right`, `center`; `justify` falls back to `left` on the last line.

The line width is the `<text>` element's content width (parent inner width minus text padding). Items wider than the full line width overflow according to the `<text>` element's `overflowX` attribute.

#### 7.6.3 `justify` alignment

Justified text distributes extra horizontal space between words on each line (except the last). Pixels are distributed evenly; if exact distribution is impossible, extra pixels go to the leftmost gaps first. The algorithm is intentionally simple — no advanced justification (no glyph spacing, no hyphenation beyond soft-hyphens).

### 7.7 Script access to text runs

Text runs with an `id` are accessible from scripts via `getElement`:

```js
let s = getElement("status");
s.text = "offline";        /* replace entire text content */
s.color = #FF0000;         /* change color attribute */
s.class = "error-run";    /* replace class */
```

Setting `.text` replaces the text content of the run with a plain string (all previous formatting inside the run is discarded). Setting `.html` (if supported) allows setting content with inline markup — this is a v2 consideration.

Text modifiers have no script API. To make a range of text dynamically updatable, wrap it in a `<span>` even if no other identity is needed.

---

*End of Section 7.*

*Open questions:*

- *`<small>` size step — fixed to "one size down in the standard size sequence" (12→10→8), or a fractional multiplier (×0.85)? The discrete step is simpler and more predictable on bitmap fonts.*
- *`<sup>` / `<sub>` baseline shift — absolute (N pixels) or relative to font size? Relative is more correct but requires floating-point math on minimal clients.*
- *Justified text on minimal clients — may be omitted (fall back to left-align). Should this be a client capability flag?*
- *`<a target="new">` on minimal clients — may be ignored (all navigation in same window). No separate flag needed; just document this as acceptable degradation.*

---

## 8. Events

### 8.1 Overview

LHT uses a simple bubble-only event model. Events originate at a target element and propagate upward through the DOM tree toward the root. There is no capture phase. Each element may have at most one handler per event type at any given time.

### 8.2 Attaching handlers

#### 8.2.1 Via attributes

Event handlers are named functions attached as attributes in markup:

```
<button onClick=send>Send</button>
<input onChange=updateForm onFocus=highlightField/>
<div onMouseEnter=showTooltip onMouseLeave=hideTooltip>…</div>
```

Attribute names follow the pattern `on-<event-name>`. The value is a function name defined in script. The function receives a single event object argument.

#### 8.2.2 Via script API

Handlers may also be attached and removed at runtime:

```js
let btn = getElement("send-btn");
btn.on("click", send);         /* attach */
btn.off("click", send);        /* detach */
```

`on` and `off` take the event name (without the `on-` prefix) and a function reference.

**Single handler per event.** Each element holds at most one handler per event type. Calling `on` when a handler is already attached replaces it. To chain handlers, read the existing one, wrap it, and replace:

```js
let prev = btn.getHandler("click");
btn.on("click", func(e) {
  if (prev) prev(e);
  myExtraLogic(e);
});
```

### 8.3 The event object

Every handler receives an event object with the following fields:

| Field | Type | Description |
|---|---|---|
| `type` | string | Event name (`"click"`, `"keydown"`, etc.) |
| `target` | element | Element that originally triggered the event |
| `currentTarget` | element | Element whose handler is currently executing |

Methods:

| Method | Effect |
|---|---|
| `event.stop()` | Stops bubble propagation — no further handlers up the tree are called |
| `event.preventDefault()` | Suppresses the default client action (e.g. navigation for `<a>`, key insertion for inputs) |

Per-category additional fields are described in the sections below.

### 8.4 Propagation

After a handler executes, the event bubbles to the parent element, and so on up to the document root. Calling `event.stop()` halts this at the current element.

```
document
  └─ div (handler: log click)
       └─ button (handler: send)   ← click originates here
```

Click on button → `send(e)` runs on button, then `log click(e)` runs on div.
If `send` calls `e.stop()` → div handler is not called.

Events do **not** bubble out of inline text runs into their containing block by a separate path — a click on a `<span>` inside a `<p>` inside a `<div>` bubbles: span → p → div, in normal DOM order.

### 8.5 Pointer events

Fired by mouse or touch input.

| Event | Fires when |
|---|---|
| `click` | Primary button pressed and released on the element |
| `dblclick` | Two clicks in quick succession |
| `mousedown` | Primary button pressed |
| `mouseup` | Primary button released |
| `mouseenter` | Pointer enters the element's bounding rect (does not bubble) |
| `mouseleave` | Pointer leaves the element's bounding rect (does not bubble) |
| `mousemove` | Pointer moves within the element |

`mouseenter` and `mouseleave` do not bubble — they fire only on the element whose rect boundary was crossed, not on its ancestors.

Additional event fields:

| Field | Type | Description |
|---|---|---|
| `x` | int | Pointer X relative to target element's top-left corner |
| `y` | int | Pointer Y relative to target element's top-left corner |
| `pageX` | int | Pointer X relative to document origin |
| `pageY` | int | Pointer Y relative to document origin |

### 8.6 Keyboard events

Fired when the element (or one of its descendants) has focus.

| Event | Fires when |
|---|---|
| `keydown` | Key pressed (repeats while held) |
| `keyup` | Key released |
| `keypress` | Printable character produced (after keydown; deprecated in modern usage but retained for compatibility) |

Additional event fields:

| Field | Type | Description |
|---|---|---|
| `key` | string | Key name: `"Enter"`, `"Escape"`, `"ArrowUp"`, `"a"`, `"F1"`, etc. |
| `ctrl` | bool | Ctrl modifier held |
| `alt` | bool | Alt modifier held |
| `shift` | bool | Shift modifier held |

Key names follow a fixed vocabulary defined in the `event-types` bundle (Appendix). Printable characters are represented as their character string (`"a"`, `"A"`, `"1"`, `" "`, etc.). Special keys use PascalCase names (`"Enter"`, `"Backspace"`, `"ArrowLeft"`, `"PageUp"`, `"F1"`..`"F12"`).

### 8.7 Focus events

| Event | Fires when | Bubbles |
|---|---|---|
| `focus` | Element receives input focus | No |
| `blur` | Element loses input focus | No |

`focus` and `blur` do not bubble. To detect focus changes in a subtree, attach handlers to individual elements.

Focus is managed by the client: Tab key cycles through focusable elements in DOM order. Focusable elements are: all form inputs, `<button>`, `<a>`, and any element with an `onKeyDown`/`onKeyUp` handler or an explicit `focusable` attribute.

### 8.8 Form events

| Event | Fires when |
|---|---|
| `input` | Value changes (fires on every keystroke for text inputs) |
| `change` | Value is committed (fires when focus leaves the input, or on selection change for checkbox/radio/select) |

There is no built-in `submit` event on a form container — LHT has no `<form>` element. Form submission is handled entirely by script (typically an `onClick` handler on a button that reads input values and calls `fetch`).

### 8.9 Scroll events

| Event | Fires when |
|---|---|
| `scroll` | A `<scrollbox>` or the document viewport is scrolled |

Additional event fields:

| Field | Type | Description |
|---|---|---|
| `scrollY` | int | Current vertical scroll offset in pixels |

### 8.10 Lifecycle events

These fire on the `document` object, not on individual elements.

#### 8.10.1 Document processing pipeline

A document is processed in the following fixed order:

```
1. Parse <head> + <style>         → constants, classes, resource manifest ready
2. Parse <body>                    → DOM tree built              → fires: onParsed
3. Layout                          → all sizes and positions     → fires: onLayout
4. Render                          → first frame drawn           → fires: onRendered
5. Execute post-body scripts       → in declaration order:
     a. for each <library>/<script src> : load resource, execute top-level code
     b. for each inline <script>        : execute top-level code
6. Background resource loading     → images and other non-script
                                     resources finish loading    → fires: onLoad
```

**Post-body scripts and libraries** (step 5) execute in declaration order after the first frame is already on screen. Each script/library is fully loaded and its top-level code runs to completion before the next one starts. By the time any script's top-level code runs, all libraries declared above it are already initialized and their interfaces are bound.

For most initialization tasks no lifecycle events are needed — just place scripts after `</body>` and write code at the top level.

**Pre-body scripts** execute as encountered during parsing (before step 2 completes) and may subscribe to lifecycle events to defer size-dependent or render-dependent work.

**`onLoad`** fires when all background resources (images, fonts, etc.) have finished loading. It is unreliable as a general initialization point because external resources on slow servers may delay it arbitrarily. Script initialization should not depend on `onLoad`; it is intended for cases where the presence of fully loaded imagery is specifically required.

#### 8.10.2 Event table

| Event | Fires when | DOM | Sizes | Rendered |
|---|---|---|---|---|
| `onParsed` | Body fully parsed (step 2) | ✓ | ✗ | ✗ |
| `onLayout` | Layout complete (step 3, and after every re-layout) | ✓ | ✓ | ✗ |
| `onRendered` | First frame drawn (step 4) | ✓ | ✓ | ✓ |
| `onLoad` | All background resources loaded (step 6) | ✓ | ✓ | ✓ |
| `onUnload` | Document navigated away from | — | — | — |
| `onResize` | Viewport resized and re-layout+render complete | ✓ | ✓ | ✓ |
| `onError` | A script execution aborts due to an uncaught runtime error | ✓ | current | current |

```js
document.on("layout",   initOverlays);
document.on("rendered", startAnimation);
document.on("load",     onAllReady);
document.on("resize",   adaptLayout);
document.on("unload",   saveState);
document.on("error",    reportError);
```

`onError` is a top-level notification, not a local exception handler. When a runtime error occurs, the currently executing top-level script, event handler, timer callback, or network callback is aborted. The runtime then dispatches `onError` on `document` with an error object. The failed execution cannot be resumed.

The error object contains:

| Field | Type | Description |
|---|---|---|
| `message` | string | Human-readable error text |
| `code` | string | Stable error code, e.g. `"null-dereference"`, `"type-error"`, `"bounds-error"` |
| `source` | string | Script URL or `"inline"` |
| `line` | int | Source line if available, otherwise 0 |
| `function` | string | Function name if available, otherwise empty |

If `onError` itself causes a runtime error, the client logs it if possible and suppresses further nested `onError` dispatch for that error.

> **Open question.** `onRendered` could serve as a per-frame animation hook, but firing an event every frame has overhead and couples animation to the rendering pipeline in a non-obvious way. A dedicated animation API (e.g. `requestAnimationFrame`) may be cleaner. Decide before the event model is finalised.

#### 8.10.3 Re-layout

When a script or event handler mutates the DOM (adds or removes elements, or changes attributes that affect layout), the document is marked **dirty**. Re-layout and re-render happen automatically after the current script or event handler returns — all mutations within one execution are batched into a single layout pass.

Reading layout-dependent properties (element width, height, position) within the same execution context that made mutations returns **pre-mutation values**. If updated sizes are needed after a mutation, mutate in one handler and read in the subsequent `onLayout` firing.

`onLayout` fires after every layout pass — initial and re-layout alike. A handler that mutates the DOM will trigger another re-layout; guard mutations with a condition to avoid infinite loops.

> **Open problem.** Firing `onLayout` after every re-layout is dangerous: any DOM mutation in the handler causes immediate recursion (or at minimum redundant re-layout passes). Possible mitigations: fire `onLayout` only after the *initial* layout and suppress it during re-layout passes; require explicit opt-in per re-layout via a separate `onReLayout` event; or suppress `onLayout` if a re-layout was already triggered in the current frame. This needs a concrete resolution before the event model is considered stable.

---

## 9. Scripts

### 9.1 Overview

LHT Script is a lightweight imperative language with JS-inspired syntax. Design goals:

- Familiar to anyone who has written JavaScript or C
- Simple enough that a bytecode compiler fits in a few thousand lines
- Implementable interpreter on 286-class hardware
- No garbage collector — reference counting only

What's deliberately **not** in LHT Script: closures, prototypes, classes, `this` binding, generators, async/await, destructuring, spread, regex literals, `eval`. These omissions keep the VM small and the execution model predictable.

### 9.2 Language syntax

#### 9.2.1 Variables

Variables are declared with `let`. Scalar types are dynamic — a variable may hold any scalar value.

```js
let x = 10;
let name = "Alice";
let flag = true;
let elem = getElement("myDiv");
let nothing = null;
```

Top-level `let` declarations create **globals** with document lifetime. `let` inside a function creates a **local** that lives on the function's stack frame. There is no block scoping — `let` inside `if` or `while` is still function-scoped.

#### 9.2.2 Scalar types

| Type | Examples | Notes |
|---|---|---|
| `int` | `0`, `-5`, `255` | 32-bit signed integer |
| `float` | `3.14`, `-0.5` | Approximate real number; representation is implementation-defined |
| `string` | `"hello"`, `""` | Immutable UTF-8 string |
| `bool` | `true`, `false` | |
| `null` | `null` | Absence of value |
| `element` | result of `getElement(...)` | DOM node reference |
| `function` | function name used as value | Function pointer; no captured context |

Type is carried at runtime (type tag on each value). Operators check types and raise a runtime error on mismatch.

Floating-point representation is implementation-defined. A client may use hardware floating point, software IEEE-like arithmetic, fixed-point arithmetic such as 16.16, or another representation with comparable practical behavior. The specification does not guarantee single-precision bit patterns or exact cross-client rounding.

Authors should prefer integer arithmetic for layout, pixel coordinates, counters, and protocol values. For example, `x = width * 3 div 4` is preferable to `x = width * 0.75` when the result is a pixel coordinate. Floats are intended for domains where approximate real arithmetic is natural, such as chart scaling, geometry helpers, or animation curves.

#### 9.2.3 Typed arrays

For binary and numeric data, typed arrays provide compact storage without per-element type tags:

```js
let pixels = Array(uint8,  320 * 200);
let coords = Array(int16,  100);
let ids    = Array(uint32, 64);
let names  = Array(string, 20);
let mixed  = Array(any,    10);
```

Element types: `uint8`, `int8`, `uint16`, `int16`, `uint32`, `int32`, `float32`, `string`, `any`.

Access and mutation:
```js
pixels[i] = 255;
let v = coords[j];
let n = pixels.length;
```

Out-of-bounds access raises a runtime error.

`Array(any, n)` behaves like a JS array — each slot holds a dynamic value with a type tag.

#### 9.2.4 Functions

```js
function add(a, b) {
  return a + b;
}

function greet(name) {
  let msg = "Hello, " + name + "!";
  return msg;
}
```

Functions are first-class values — they can be assigned, passed as arguments, and stored in variables:

```js
let handler = greet;
btn.on("click", handler);
```

Functions do **not** capture their surrounding scope (no closures). If a function needs external data, it must receive it as a parameter or read it from a global.

Recursion is supported. Mutual recursion requires forward declaration:

```js
forward isEven;
function isOdd(n)  { return n == 0 ? false : isEven(n - 1); }
function isEven(n) { return n == 0 ? true  : isOdd(n - 1); }
```

#### 9.2.5 Control flow

```js
/* if / else */
if (x > 0) {
  doSomething();
} else if (x < 0) {
  doOther();
} else {
  doDefault();
}

/* while */
while (i < n) {
  process(arr[i]);
  i = i + 1;
}

/* for */
for (let i = 0; i < n; i = i + 1) {
  process(arr[i]);
}

/* break / continue */
while (true) {
  if (done()) break;
  if (skip()) continue;
  work();
}

/* ternary */
let abs = x >= 0 ? x : -x;
```

There is no `switch` statement — use `if / else if` chains.

#### 9.2.6 Operators

| Category | Operators |
|---|---|
| Arithmetic | `+  -  *  /  %` |
| Integer division | `div` |
| Comparison | `==  !=  <  >  <=  >=` |
| Logical | `&&  \|\|  !` |
| Assignment | `=` |
| String concat | `+` (when either operand is a string) |

No `===`/`!==` — the single equality operator compares value and type. No bitwise operators in v1.

#### 9.2.7 Error handling

LHT Script has no local exceptions in v1: no `try`, no `catch`, and no `throw`. Ordinary failure is reported through explicit return values or callback result objects. Runtime errors are fatal to the current script execution but not to the document or client.

When a runtime error occurs:

1. The current top-level script, event handler, timer callback, or network callback is aborted.
2. Batched DOM mutations already performed by that execution remain applied.
3. The runtime dispatches `document`'s `onError` event with an error object.
4. The event loop continues.

This is intentionally similar to a single top-level catch for the whole document, but without stack unwinding semantics and without the ability to resume the failed execution.

```js
document.on("error", func(e) {
  log(e.message);
  let status = getElement("status");
  if (status != null) status.text = "Script error: " + e.code;
});
```

Examples of runtime errors: null dereference, type mismatch, out-of-bounds array access, division by zero, calling a non-function, and using an unsupported API without checking capability.

### 9.3 Object literals

LHT Script supports simple key-value records as a convenience for grouping data:

```js
let point = { x: 10, y: 20 };
let label = point.x;
point.y = 35;
```

Object literals are not classes, do not have prototypes, and do not support methods (functions assigned to fields are just stored function pointers — calling `obj.fn()` does not set `this`). They exist purely for structured data grouping.

### 9.4 Scope and memory

**Globals** are declared at top level. They are allocated once when the document loads and freed when it unloads. Globals are shared across all scripts in the same document.

**Locals** are stack-allocated when a function is entered and freed on return. The stack is a fixed-size region per document (implementation-defined, typically 8–64 KB).

**Strings** and **typed arrays** are heap-allocated, managed by reference counting. A value is freed when no variable or array slot holds a reference to it. There are no cycles in the reference graph (no closures, no circular object references via ordinary assignment) — reference counting is therefore complete.

**Element references** (`element` type) are weak references to DOM nodes. An element reference does not keep the node alive; if the node is removed from the DOM, the reference becomes null and accessing it raises a runtime error.

### 9.5 DOM API

#### 9.5.1 Element access

```js
let el = getElement("my-id");          /* by id */
```

#### 9.5.2 Reading and writing attributes

Attribute values are accessed and set as typed properties:

```js
el.width    = 200;
el.bgColor  = 0xFF3366;               /* color as 0xRRGGBB int */
el.text     = "new content";          /* for span/p/etc. */
el.disabled = true;
let w = el.width;
```

Setting an attribute that does not apply to the element's type raises a runtime error at debug level; in release mode it is silently ignored.

#### 9.5.3 Classes

```js
el.class = "highlighted";             /* replace class list */
el.addClass("active");
el.removeClass("active");
el.hasClass("highlighted");           /* returns bool */
```

#### 9.5.4 DOM structure

```js
/* create and insert */
let newDiv = createElement("div");
newDiv.bgColor = 0xFFFFFF;
el.appendChild(newDiv);
el.insertBefore(newDiv, refChild);
el.removeChild(child);

/* navigate */
let parent = el.parent;
let first  = el.firstChild;
let next   = el.nextSibling;
```

#### 9.5.5 Table API

```js
let t = getElement("data-table");
let row  = t.rows[2];
let cell = row.cells[1];
cell.text = "updated";
t.addRow([{text: "A"}, {text: "B"}]);
t.removeRow(0);
```

#### 9.5.6 Canvas API

See Section 4.10.1 for the full canvas drawing API.

### 9.6 Execution model

LHT Script is **single-threaded**. There is no concurrency, no shared state between workers. Async behavior is achieved via event handlers, timers, and `Request` callbacks (see Section 10).

#### Static script initialization

Post-body scripts and libraries execute in declaration order before `onLoad` fires (pipeline step 5 — see §8.10.1). Each item is fully loaded and its top-level code runs to completion before the next begins:

```
<library src="utils.ls"  interface="Utils">   ← loads, runs, Utils bound
<library src="crypto.ls" interface="Crypto">  ← loads, runs, Crypto bound
<script src="main.ls">                         ← loads, runs; Utils+Crypto available
<script>
  /* inline: runs last; all of the above are ready */
  let h = Crypto.hash("hello");
</script>
```

Top-level code in a post-body script is the natural place for initialization — no event subscription needed.

#### Event loop

After all static scripts have initialized, the runtime enters the event loop:

1. Wait for an event (user input, network callback, lifecycle event).
2. Dispatch: call the registered handler synchronously to completion.
3. Apply batched DOM mutations → re-layout if dirty → re-render if changed.
4. Go to 1.

A handler runs to completion before the next event is processed. Long-running handlers block the UI.

#### Timers

```js
let id = setTimeout(callback, ms);    /* call once after ms milliseconds */
clearTimeout(id);

let id = setInterval(callback, ms);   /* call repeatedly every ms milliseconds */
clearInterval(id);
```

Timer callbacks are dispatched from the event loop — they never interrupt a running handler. If a timer fires while a handler is executing, the callback is queued and runs after the handler returns (and after DOM mutations are flushed).

`ms` is an integer number of milliseconds. A value of 0 schedules the callback for the next event loop iteration. The minimum effective interval is implementation-defined (on a 286, values below ~50 ms may be clamped).

### 9.7 Bytecode and VM

#### 9.7.1 Stack-based VM

LHT Script compiles to a stack-based bytecode. The VM maintains an operand stack and a call stack (return addresses and local variable frames). The main dispatch loop is:

```
fetch opcode (1 byte)
jump via dispatch table
execute
repeat
```

On a 286, one bytecode step takes approximately 15–25 clock cycles. A 10 MHz 286 executes ~400–650K steps/second — sufficient for UI logic.

The full opcode table is defined in Appendix B. The set comprises approximately 50–70 opcodes covering: stack manipulation, arithmetic, comparison, control flow, variable access, function call/return, DOM operations, and runtime error reporting.

#### 9.7.2 Script delivery

Three delivery levels are negotiated via content negotiation (Section 11):

| Level | Content-Type | Description |
|---|---|---|
| Source | `text/lhtml-script` | Canonical text; client compiles to bytecode on load |
| Bytecode | `application/lhtml-script` | Pre-compiled by server; client executes directly |

The server may pre-compile scripts to bytecode as an optimization. Clients that cannot compile (minimal class) request bytecode directly. Clients that can compile may accept source and compile locally (preserving reversibility for "View Source").

#### 9.7.3 Execution

All conforming script-capable clients execute bytecode with an interpreter. The interpreter is the only execution strategy defined by the base specification.

Clients may add private implementation optimizations, including threaded dispatch, native compilation, or JIT compilation. These optimizations are not observable by documents, are not negotiated, and are not required for conformance. A client that interprets every bytecode instruction directly is fully conforming.

### 9.8 Library scripts

A **library** is a script with an isolated global scope that exposes a typed interface object. Unlike regular scripts, a library:

- Has its own isolated global scope — no access to the document's globals.
- Cannot access the DOM.
- Declares its public interface with an `exports` statement.
- May hold private internal state (globals within its own scope).

#### 9.8.1 Static loading

```
<library src="crypto.ls" interface="Crypto">
```

The runtime loads `crypto.ls`, executes it in an isolated scope, and binds the exported object to the global name `Crypto`. `<library>` tags are top-level only (siblings of `<script>` and `<body>`).

#### 9.8.2 Dynamic loading and unloading

```js
let Crypto = loadLibrary("crypto.ls");   /* load; returns the interface object */
/* ... */
Crypto.unload();                          /* release the library and its scope */
```

`loadLibrary(url)` loads the script, executes it in an isolated scope, and returns the exported interface object. The caller assigns it to any variable — that variable becomes the interface name.

`.unload()` is a built-in method on every interface object. After it is called, the library's isolated scope and all its globals are freed. Further calls to any method on the interface object raise a runtime error. The caller's variable is not nulled automatically:

```js
Crypto.unload();
Crypto = null;   /* optional, but recommended */
```

#### 9.8.3 The `exports` statement

Inside a library file, `exports` is a statement keyword that declares the public interface:

```js
let _roundKeys = Array(uint8, 128);   /* private — not exported */

function hash(data) { ... }
function verify(data, sig) { ... }

exports { hash, verify };
/* shorthand: key name equals variable name */
/* explicit form: exports { hash: hash, verify: verify }; */
```

Rules:
- Only one `exports` statement is allowed per file.
- If `exports` is absent, the library exports an empty object.
- Library globals are private — accessible from outside only through the exported interface.

#### 9.8.4 Dependency injection

Libraries cannot load other libraries directly. Dependencies are wired by the calling script, which passes interface objects as arguments:

```js
let Base   = loadLibrary("base.ls");
let Crypto = loadLibrary("crypto.ls");
Crypto.init(Base);   /* explicit dependency injection */
```

This keeps the dependency graph visible and acyclic without a module resolution system.
