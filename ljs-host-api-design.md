# LJS Host API Design

Status: design draft  
Scope: browser-facing LJS host API contract derived from LHT specification drafts

This document consolidates the script-facing host API described across the LHT
specification drafts. It is not based on example files. Examples can later be
updated to match this contract, but the authority comes from the spec notes
listed below.

## Source Documents

- `lht-spec-part3.md`: events, lifecycle, script language, DOM API, execution
  model, timers, libraries.
- `lht-spec-part4.md`: Request, response objects, storage/session, content
  negotiation.
- `lht-vocabulary-v1.md`: event handler attributes and element/attribute
  vocabulary status.
- `lht-security-design.md`: origin, active request rules, regular scripts vs
  isolated libraries, host capability boundaries.
- `lht-scripting-simplification.md`: no local exceptions, top-level `onError`,
  explicit failure values, library sandbox simplification.

Where older spec text conflicts with newer security/simplification notes, this
document marks the adopted direction explicitly.

## Design Goal

Define the stable author-facing contract for browser host APIs before wiring a
real DOM bridge into the current mini runtime.

The current implemented mini runtime supports namespaced member calls,
handler-checked argument lists, and first host object handles. The first
implemented handle is a drawing-only canvas context returned by
`Canvas.context()` under `lcCanvasBasic`. The full browser host API still needs
more runtime features: property access, callbacks, function references,
structured host objects, and event-loop integration. This document describes
the target contract those slices should converge toward.

## Authority Model

Host APIs are profile capabilities, not LJS language builtins.

Profiles:

| Profile | Authority |
|---|---|
| `isolated` | no ambient document, storage, network, timer, or DOM capability |
| `cli-debug` | debug/test output only |
| browser interactive profile | document DOM, events, timers, Request, storage/session according to security policy |
| library scope | isolated globals; no ambient document/storage/network/caller globals |

Adopted rule:

- regular document scripts may receive browser capabilities from the active
  browser profile;
- libraries do not receive ambient browser capabilities;
- libraries may receive only plain data, library interfaces, or explicit narrow
  capabilities passed by the caller;
- the DOM object API is not available in isolated library contexts.

## Document And Lifecycle Events

Normative basis: `lht-spec-part3.md` Sections 8.10 and 9.6.

Document lifecycle events fire on `document`, not on individual elements.

```js
document.on("layout",   initOverlays);
document.on("rendered", startAnimation);
document.on("load",     onAllReady);
document.on("resize",   adaptLayout);
document.on("unload",   saveState);
document.on("error",    reportError);
```

Lifecycle event table:

| Event | Meaning |
|---|---|
| `parsed` | body fully parsed |
| `layout` | layout complete |
| `rendered` | first frame drawn |
| `load` | background resources loaded |
| `unload` | document navigated away |
| `resize` | viewport resized and re-layout/render complete |
| `error` | current script execution aborted due to runtime error |

Open design item inherited from the spec: `layout` after every re-layout can
cause recursive layout loops. The design should either make `layout` initial
only, add a separate re-layout event, or suppress recursive layout dispatch in
the same frame.

## Element Events

Normative basis: `lht-spec-part3.md` Section 8 and
`lht-vocabulary-v1.md` Section 13.

Events use a bubble-only model:

- no capture phase;
- events originate at a target and bubble toward the root;
- each element has at most one handler per event type;
- `on` replaces an existing handler for that event type.

Markup handlers:

```lht
<button onClick=send>Send</button>
```

Script handlers:

```js
let btn = getElement("send-btn");
btn.on("click", send);
btn.off("click", send);
```

Event object base fields:

| Field | Type |
|---|---|
| `type` | string |
| `target` | element |
| `currentTarget` | element |

Event object methods:

| Method | Effect |
|---|---|
| `stop()` | stop bubbling |
| `preventDefault()` | suppress default action |

Initial event groups:

- pointer: `click`, `dblclick`, `mousedown`, `mouseup`, `mouseenter`,
  `mouseleave`, `mousemove`;
- keyboard: `keydown`, `keyup`, `keypress`;
- focus: `focus`, `blur`;
- form: `input`, `change`;
- scroll: `scroll`;
- lifecycle: `parsed`, `layout`, `rendered`, `load`, `unload`, `resize`,
  `error`.

## DOM API

Normative basis: `lht-spec-part3.md` Section 9.5.

### Element Lookup

```js
let el = getElement("my-id");
```

Adopted semantics:

- returns an element reference or `null`;
- missing ids are ordinary failure, not runtime errors;
- element references are weak references to DOM nodes;
- if the node is removed, the reference becomes null and access raises a
  runtime error.

### Attributes And Properties

Spec draft shape:

```js
el.width    = 200;
el.bgColor  = 0xFF3366;
el.text     = "new content";
el.disabled = true;
let w = el.width;
```

Adopted semantics:

- attribute values are exposed as typed properties;
- setting an attribute that does not apply to the element is a debug error and
  release no-op, matching the current spec draft;
- mutations that affect layout mark the document dirty;
- re-layout/re-render happens after the current script or event handler returns.

### Classes

```js
el.class = "highlighted";
el.addClass("active");
el.removeClass("active");
let yes = el.hasClass("highlighted");
```

### Structure

The current spec draft includes structural DOM mutation and traversal:

```js
let newDiv = createElement("div");
el.appendChild(newDiv);
el.insertBefore(newDiv, refChild);
el.removeChild(child);

let parent = el.parent;
let first  = el.firstChild;
let next   = el.nextSibling;
```

Security boundary:

- regular document scripts may use this API if the browser profile grants DOM
  authority;
- isolated libraries must not receive these element references;
- passing an element reference to a library would violate the current library
  sandbox rule unless a future constrained wrapper is specified.

### Tables

The draft table API:

```js
let t = getElement("data-table");
let row  = t.rows[2];
let cell = row.cells[1];
cell.text = "updated";
t.addRow([{text: "A"}, {text: "B"}]);
t.removeRow(0);
```

Open issue: this depends on arrays/records and broader value-model support.
Treat it as a later DOM convenience layer, not the first browser bridge slice.

## Canvas Capability

Normative basis: `lht-spec-part2.md` vector/canvas notes,
`lht-spec-part3.md` canvas reference, and `lht-security-design.md` Section 9.2.

The canvas context is a narrow capability object. It may be passed to a library
because it is not a DOM object and must not expose document traversal.

Allowed direction:

```js
let ctx = getElement("chart").context();
Chart.draw(ctx, data);
```

Security rule:

- drawing methods are allowed;
- `ctx.canvas`, `ctx.ownerDocument`, `ctx.parent`, `ctx.getElement`, and
  `ctx.on` are not exposed.

## Request API

Normative basis: `lht-spec-part4.md` Section 10.2 plus
`lht-security-design.md` Sections 6-8.

API shape:

```js
let req = Request(url, method);
req.body = data;
req.contentType = "text/plain";
req.timeout = 5000;
req.setHeader("X-Token", "abc");
req.onProgress = func(loaded, total) { };
req.send(callback);
req.abort();
```

Response fields:

| Field | Type |
|---|---|
| `status` | int |
| `ok` | bool |
| `body` | string |
| `bodyRaw` | Array(uint8) |
| `contentType` | string |

Adopted security direction:

- same-origin active requests are allowed;
- cross-origin readable responses require explicit server opt-in;
- public-origin documents must not use the client to probe private/local
  network targets;
- no automatic credentials are sent;
- custom cross-origin headers are not part of v1.

This supersedes the older `lht-spec-part4.md` sentence that network access is
unrestricted. That sentence is retained as spec debt, not the chosen direction.

## Storage And Session

Normative basis: `lht-spec-part4.md` Section 10.3 plus
`lht-security-design.md` Section 2.

API shape:

```js
storage.set(key, value);
storage.set(key, value, expires);
storage.get(key);
storage.remove(key);
storage.keys();
storage.size();
storage.clear();
```

`session` exposes the same interface.

Rules:

- `storage` is persistent and origin-scoped;
- `session` is current-session and origin-scoped;
- keys and values are strings;
- structured data is serialized by script;
- expired entries are discarded on read and hidden from `keys`/`size`.

Minimum capacities from the spec draft:

| Namespace | Minimum |
|---|---|
| `storage` | 16 KB per origin |
| `session` | 64 KB per origin |

Open conflict: `lht-spec-part4.md` says storage-full silently fails, while
`lht-scripting-simplification.md` recommends `set` returning `false`. Adopted
direction for a small but author-friendly API: `set` should return bool success.
This needs to be folded back into the main spec.

## Timers

Normative basis: `lht-spec-part3.md` Section 9.6.

```js
let id = setTimeout(callback, ms);
clearTimeout(id);

let id = setInterval(callback, ms);
clearInterval(id);
```

Rules:

- callbacks are dispatched from the event loop;
- timers never interrupt a running handler;
- callbacks queued while a handler runs execute after that handler returns and
  after DOM mutations flush;
- small `ms` values may be clamped by the implementation.

## Error Model

Normative basis: `lht-spec-part3.md` Sections 8.10.2 and 9.4 plus
`lht-scripting-simplification.md`.

LHT Script has no local exceptions in v1:

- no `try`;
- no `catch`;
- no `throw`.

Runtime error behavior:

1. Abort the current top-level script, event handler, timer callback, network
   callback, or library call.
2. Keep DOM mutations already performed by that execution.
3. Dispatch `document`'s `error` event with an error object.
4. Continue the event loop.

Error object fields:

| Field | Type |
|---|---|
| `message` | string |
| `code` | string |
| `source` | string |
| `line` | int |
| `function` | string |

If the `error` handler itself fails, nested error dispatch is suppressed.

Ordinary API failures should use `null`, `false`, or response/result objects.

## Library Scripts

Normative basis: `lht-spec-part3.md` Section 9.8 plus
`lht-security-design.md` Section 9.

Current stable direction:

- `<library>` is top-level only;
- libraries have isolated globals;
- libraries cannot access document globals;
- libraries cannot access DOM, storage, network, or caller globals;
- public interface is declared with `exports`;
- dependencies are injected by the caller.

The older `lht-spec-part3.md` dynamic loading/unloading text conflicts with
`lht-scripting-simplification.md`, which recommends no explicit unload in v1.
Adopted direction: no author-visible explicit unload in v1. A loaded library
lives at least until document unload; clients may reclaim internal cached code
when safe.

## First Implementation Slices

The current mini runtime is much smaller than this target. Good implementation
order:

1. Preserve current `cli-debug` host handler path as the test profile. Done.
2. Add runtime value support for host object handles. Started with
   `Canvas.context()` returning a drawing-only context handle.
3. Add property access AST/runtime support.
4. Implement `getElement(id)` returning a weak element handle.
5. Implement `el.text` read/write for text-hosting elements and spans.
6. Add event handler dispatch for `onClick`/`click`.
7. Add `document.on("error", ...)` after the top-level error model is wired.

This keeps the first browser bridge small while aligning it with the LHT spec
direction.

## Main Spec Debt To Reconcile

- `lht-spec-part4.md` unrestricted network sentence vs `lht-security-design.md`
  active request restrictions.
- storage `set` silent failure vs bool success return.
- library `.unload()` in `lht-spec-part3.md` vs no explicit unload in
  `lht-scripting-simplification.md`.
- `layout` lifecycle recursion semantics.
- table API dependency on arrays/records.
- whether lifecycle events exist as body/document attributes or only
  `document.on(...)` registrations.
