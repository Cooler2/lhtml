# LHT Script Simplification — Design Note

**Status:** proposal  
**Scope:** simplify LHT Script while preserving practical document interactivity  
**Goal:** make scripting feel useful as document glue, without turning it into a full general-purpose JavaScript clone

---

## 1. Guiding idea

LHT Script should be an event glue language:

- read and write element properties
- respond to clicks, input, timers, and network callbacks
- validate forms
- update small pieces of DOM
- call small helper libraries
- do modest integer/string/array work

It should not try to be a full application runtime in v1. Every general-purpose language feature has implementation cost: parser complexity, bytecode complexity, memory management, debug semantics, and edge cases. The strongest version of LHT is the one where a small client can implement the whole runtime confidently.

---

## 2. Proposed v1 language core

Keep:

- `let`
- `function`
- function references for callbacks
- `if` / `else`
- `while`
- `for`
- `break` / `continue`
- `return`
- integer arithmetic
- string concatenation
- booleans and `null`
- typed arrays
- element references
- callback-based async APIs

Consider optional or v2:

- object literals created by user code
- `Array(any)`
- recursion
- dynamic library unloading
- `try` / `catch` / `throw`

The v1 language should be boring, predictable, and easy to compile to a compact bytecode.

---

## 3. Remove `try` / `catch` / `throw` from v1

### 3.1 Why remove it

Exceptions are convenient in large languages, but expensive in a tiny VM.

They require:

- handler stack management
- stack unwinding
- rules for thrown values
- rules for errors thrown inside `catch`
- interaction with callbacks and event dispatch
- bytecodes such as `PUSH_HANDLER`, `POP_HANDLER`, `THROW`
- more complicated debugging and conformance tests

They also encourage an API style where ordinary failure is hidden in exceptional control flow. LHT APIs can instead use explicit result values.

### 3.2 Replacement: explicit failure values

Use `null`, `false`, or response/result objects.

Element lookup:

```js
let el = getElement("status");
if (el != null) {
  el.text = "ready";
}
```

Network:

```js
let req = Request("/api/items", "GET");
req.send(func(r) {
  if (!r.ok) {
    showError(r.error);
    return;
  }

  getElement("list").text = r.body;
});
```

Storage:

```js
let saved = storage.get("draft");
if (saved == null) {
  saved = "";
}
```

Array access:

```js
if (i >= 0 && i < arr.length) {
  arr[i] = value;
}
```

This style is more verbose than exceptions, but it is explicit, easy to compile, and easy to understand on constrained systems.

### 3.3 Runtime errors without catch

The VM still needs runtime error behavior. Without `try/catch`, the rule can be simple:

- A runtime error aborts the current script callback or top-level script.
- The failed execution cannot be resumed.
- The runtime dispatches `document.onError` with an error object.
- The client records the error in a debug log if available.
- The event loop continues.
- The document is not navigated away from and the client does not crash.

Examples of runtime errors:

- null dereference
- type mismatch
- out-of-bounds typed array access
- division by zero
- calling a non-function
- using unsupported API on the current client

### 3.4 `onError`: one top-level catch

`onError` is the proposed replacement for local exceptions. It behaves like a single catch at the top of the event loop:

- It receives errors from top-level scripts, event handlers, timer callbacks, network callbacks, and library calls made from those executions.
- It runs after the failed execution has already been aborted.
- It cannot resume the failed execution.
- It should be used for logging, diagnostics, user-visible failure messages, and emergency cleanup.

Example:

```js
document.on("error", func(e) {
  log(e.message);

  let status = getElement("status");
  if (status != null) {
    status.text = "Script error: " + e.code;
  }
});
```

Suggested error object:

| Field | Type | Meaning |
|---|---|---|
| `message` | string | Human-readable error text |
| `code` | string | Stable machine-readable code |
| `source` | string | Script URL or `"inline"` |
| `line` | int | Source line if available, otherwise 0 |
| `function` | string | Function name if available, otherwise empty |

The object may be extended by debug clients, but portable scripts should rely only on the fields above.

If `onError` itself fails, the client should log the secondary error and suppress nested `onError` dispatch for that failure. This prevents infinite error loops:

```js
document.on("error", func(e) {
  /* If this handler fails, do not recursively call onError forever. */
});
```

`onError` is not for ordinary API failure. Network errors, missing optional elements, storage capacity failure, and unsupported optional features should still be reported through explicit result values.

In release clients, some DOM mistakes may be specified as no-op instead of runtime error. The spec should be explicit per API.

Recommended distinction:

| Situation | Behavior |
|---|---|
| `getElement` misses | returns `null` |
| invalid property for element | no-op in release, debug error |
| typed array out of bounds | runtime error aborting current callback |
| network failure | response object with `ok=false` |
| storage full | `storage.set` returns `false` |
| unsupported feature | capability check or `null` result |

---

## 4. API shape without exceptions

APIs should be designed to make checks natural.

### 4.1 DOM

```js
let el = getElement("name");
if (el == null) return;

el.text = "Alice";
el.addClass("active");
```

Possible helper:

```js
let ok = setText("name", "Alice");  /* returns false if missing */
```

This kind of helper is optional; the base DOM API can remain small.

### 4.2 Request

The response object should include a stable error field:

| Field | Type | Meaning |
|---|---|---|
| `ok` | bool | true for successful 2xx responses readable by script |
| `status` | int | HTTP status, or 0 for local/network failures |
| `error` | string/null | `"timeout"`, `"network"`, `"cross-origin-denied"`, etc. |
| `body` | string | text body if available |
| `bodyRaw` | Array(uint8)/null | binary body if available |

Example:

```js
let req = Request("/api/save", "POST");
req.body = data;
req.send(func(r) {
  if (!r.ok) {
    setStatus("Save failed: " + r.error);
    return;
  }

  setStatus("Saved");
});
```

### 4.3 Storage

Make write success observable:

```js
let ok = storage.set("draft", text);
if (!ok) {
  setStatus("Storage full");
}
```

Current spec says storage full silently fails. That is simple for the client but bad for authors. Returning `false` keeps the implementation small and avoids exceptions.

---

## 5. Libraries

Libraries are useful and should stay. They provide code reuse without giving every document a huge standard library.

Recommended v1 model:

- Static `<library src="..." interface="Name">` is supported.
- Dynamic loading is supported through a callback API.
- Libraries may be same-origin or cross-origin.
- Libraries have isolated globals.
- Libraries cannot access the DOM, storage, network, or document globals directly.
- Libraries receive authority only through explicit arguments passed by the caller.
- Libraries declare exports with `exports`.
- There is no explicit `.unload()` in v1.

### 5.1 Static loading

```lht
<library src="/lib/format.ls" interface="Format">
<script src="/app/main.ls">
```

Top-level scripts below the library can use `Format`.

```js
let s = Format.money(1234);
getElement("price").text = s;
```

Static library loading is useful for pages that know their dependencies up front. It also keeps initialization deterministic.

Cross-origin static libraries are allowed because library code runs in an isolated scope:

```lht
<library
  src="https://cdn.example.net/chart-1.2.0.ls"
  interface="Chart"
  integrity="sha256-...">
```

The `integrity` attribute is recommended for cross-origin libraries so the author can pin the exact code being trusted. Even without DOM access, a library may still affect the document through values it returns or drawing operations it performs through explicitly passed capabilities.

### 5.2 Dynamic loading

Dynamic library loading should be asynchronous:

```js
loadLibrary("/lib/crypto.ls", func(Crypto) {
  if (Crypto == null) {
    setStatus("Crypto unavailable");
    return;
  }

  let h = Crypto.hash("hello");
  getElement("hash").text = h;
});
```

Why callback-based:

- loading may require network
- no promises in v1
- no blocking UI
- fits the existing event loop model

Suggested signature:

```js
loadLibrary(url, callback);
```

The callback receives the exported interface object, or `null` on failure.

Optional richer form:

```js
loadLibrary("/lib/crypto.ls", func(result) {
  if (!result.ok) {
    setStatus(result.error);
    return;
  }

  let Crypto = result.library;
});
```

The simple `interface-or-null` version is probably enough for v1 if errors are also logged by the client.

Cross-origin dynamic loading follows the same sandbox rule:

```js
loadLibrary("https://cdn.example.net/chart-1.2.0.ls", func(Chart) {
  if (Chart == null) return;

  let ctx = getElement("chart").context();
  Chart.draw(ctx, data);
});
```

This is safe because `ctx` is a drawing-only capability, not part of the DOM object API.

### 5.3 Library sandbox and capabilities

A library scope does not contain ambient document capabilities:

- no `document`
- no `getElement`
- no `storage` or `session`
- no `Request`
- no navigation APIs
- no caller globals

The caller may pass data:

```js
let label = Chart.formatLabel(value);
```

The caller may pass another library interface:

```js
Chart.init(Format);
```

The caller may pass a narrow host capability:

```js
let ctx = getElement("chart").context();
Chart.draw(ctx, series);
```

For this to preserve isolation, `ctx` must expose only drawing operations. It must not expose `ctx.canvas`, `ownerDocument`, `parent`, DOM traversal, event registration, or any way to recover the original document.

The DOM object API is not available in isolated library contexts. If a library needs to affect the DOM, it should return data or rendering commands, and the caller's script should apply them:

```js
let text = Chart.summary(series);
getElement("summary").text = text;
```

### 5.4 No explicit unload

Explicit unload is not worth the v1 complexity.

Problems with `.unload()`:

- interface objects can remain in variables
- callbacks may still reference exported functions
- other libraries may hold references
- calling into an unloaded library needs runtime checks everywhere
- memory lifetime becomes visible to author code

Recommended rule:

- A loaded library lives at least until document unload.
- The client may internally reclaim cached compiled code under memory pressure if no active document uses it.
- Author code cannot explicitly unload a library in v1.

This is simpler and still supports the useful part: loading and using shared code.

### 5.5 Dependency injection

Keep explicit dependency injection:

```js
loadLibrary("/lib/base.ls", func(Base) {
  if (Base == null) return;

  loadLibrary("/lib/crypto.ls", func(Crypto) {
    if (Crypto == null) return;

    Crypto.init(Base);
  });
});
```

For static libraries:

```lht
<library src="/lib/base.ls" interface="Base">
<library src="/lib/crypto.ls" interface="Crypto">
<script>
  Crypto.init(Base);
</script>
```

Libraries should not load other libraries directly in v1. This keeps dependency order visible and avoids module-resolution rules.

---

## 6. Object literals and records

Object literals are convenient, but they create questions:

- Are records heap allocated?
- Can they contain arrays?
- Can records reference other records?
- Are cycles possible?
- Do records participate in reference counting?
- Can records be compared?
- Can records be stored in `Array(any)`?

For v1, there are two reasonable options.

### Option A: no user-created objects

User code cannot write:

```js
let p = { x: 10, y: 20 };
```

Host APIs may still return host-defined records, such as response objects:

```js
req.send(func(r) {
  if (r.ok) use(r.body);
});
```

This gives authors structured API results without adding general heap records.

### Option B: flat records only

Allow:

```js
let p = { x: 10, y: 20 };
```

But restrict values to scalar types only:

- int
- bool
- string
- null
- element
- function

No nested records and no arrays inside records. This prevents cycles and keeps reference counting tractable.

Recommendation: choose Option A for v1-core; consider Option B for v1-interactive or v2.

---

## 7. Floats

Floats are useful enough to keep in v1. Chart scaling, geometry helpers, animation curves, easing functions, and numeric UI logic are all awkward if the language has only integers.

The important constraint is that floats should not become the default answer for layout and pixel math. LHT's layout model is integer-pixel oriented, and many common ratios are better expressed with integer arithmetic:

```js
let x = width * 3 div 4;      /* preferred for pixel coordinates */
let y = height * 128 div 256; /* matches the layout fraction model */
```

Instead of:

```js
let x = width * 0.75;
```

Recommendation:

- Keep `float` as a v1 scalar type.
- Do not require a specific representation such as IEEE single precision.
- Allow clients to implement floats as hardware FP, software FP, fixed-point 16.16, or another representation with comparable practical behavior.
- Do not guarantee exact cross-client rounding for float operations.
- Prefer integer arithmetic for layout, coordinates, counters, lengths, protocol values, and storage formats.
- Use floats for approximate numeric work where small rounding differences are acceptable.

This keeps scripts convenient without forcing every client to expose or emulate a precise floating-point model. A 286-class client can use fixed-point internally; a modern client can use native floating point.

---

## 8. Recursion

Recursion is elegant but not essential for document glue. It can exhaust a small fixed stack and complicates conformance.

Options:

- Allow recursion with an implementation-defined stack limit and runtime error on overflow.
- Forbid recursion in v1 and require loops.

Recommendation: allow function calls normally, but specify a maximum call depth or stack exhaustion behavior. Do not require clients to support deep recursion.

Example normative wording:

> A client must detect script stack exhaustion and abort the current script execution without crashing the client. The minimum supported call depth is implementation-defined.

---

## 9. Suggested v1 scripting profile

Recommended v1-core:

- no scripts

Recommended v1-interactive:

- bytecode interpreter
- source compilation optional
- `let`, functions, loops, conditionals
- ints, strings, bool, null
- typed arrays except perhaps `Array(any)`
- function references, no closures
- DOM access and mutation
- events
- timers
- `Request`
- storage
- static libraries
- async dynamic `loadLibrary`
- no `try/catch/throw`
- no explicit library unload
- no JIT in normative spec
- no cross-origin regular script loading
- cross-origin libraries allowed under the isolated library sandbox

This still supports useful pages:

- login forms
- settings panels
- dashboards
- small games
- calculators
- data tables
- AJAX-style updates
- reusable formatting/crypto/validation helpers

But it avoids the largest complexity traps.

---

## 10. Example: form submission without exceptions

```js
function sendLogin(e) {
  let name = getElement("name");
  let pass = getElement("pass");
  let status = getElement("status");

  if (name == null || pass == null || status == null) return;

  if (name.text == "" || pass.text == "") {
    status.text = "Enter name and password";
    return;
  }

  let req = Request("/api/login", "POST");
  req.contentType = "application/json";
  req.body = jsonEncode({ name: name.text, pass: pass.text });

  req.send(func(r) {
    if (!r.ok) {
      status.text = "Login failed: " + r.error;
      return;
    }

    storage.set("session", r.body);
    status.text = "Signed in";
  });
}
```

If object literals are removed from v1, the request body can be built with a helper:

```js
req.body = jsonPair2("name", name.text, "pass", pass.text);
```

or by simple string construction if JSON helpers are not present:

```js
req.body = "name=" + urlEncode(name.text) + "&pass=" + urlEncode(pass.text);
req.contentType = "application/x-www-form-urlencoded";
```

The important point: ordinary failure is handled directly, without exceptions.
