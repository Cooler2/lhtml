# Light HyperText Format (LHT) — Specification Draft, Part 4

**Version:** 0.1 (draft)
**Status:** Work in progress
**Continues from:** lht-spec-part3.md (sections 7–9)

---

## Table of Contents (this document)

10. [Network & Storage](#10-network--storage)
11. [Content Negotiation](#11-content-negotiation)

**Appendices**
- [A — Token Assignments](#appendix-a--token-assignments)
- [B — Canonical Text Form](#appendix-b--canonical-text-form)
- [C — Bundle Binary Format](#appendix-c--bundle-binary-format-lhb)
- [D — Downloadable Font Extension](#appendix-d--downloadable-font-extension)
- [E — Sample Documents](#appendix-e--sample-documents)

---

## 10. Network & Storage

### 10.1 Overview

LHT scripts can issue HTTP requests and persist data across page loads. Both capabilities are exposed through a small, explicit API designed for the resource constraints of the target platform: no streaming, no promises, callback-based async.

---

### 10.2 HTTP Requests

All HTTP requests are made through the **Request** object. Requests are non-blocking: `.send()` registers the request and returns immediately; the callback is invoked from the event loop when the response arrives (or on error/timeout).

```js
let req = Request("/api/items", "GET");
req.send(func(r) {
  if (r.ok) {
    getElement("list").text = r.body;
  }
});
```

#### 10.2.1 Request object

```js
let req = Request(url, method);
req.body        = data;          /* request body: string or Array(uint8) */
req.contentType = "text/plain";  /* overrides auto-detection */
req.timeout     = 5000;          /* ms; 0 = no timeout */
req.setHeader("X-Token", "abc");
req.onProgress  = func(loaded, total) { /* … */ };
req.send(callback);
/* later, if needed: */
req.abort();
```

| Member | Description |
|---|---|
| `Request(url, method)` | Constructor; method: `"GET"`, `"POST"`, `"PUT"`, `"DELETE"` |
| `.body` | Request body: string or `Array(uint8)` (read/write) |
| `.contentType` | Request `Content-Type` (read/write); auto-detected if not set |
| `.timeout` | Timeout in milliseconds (read/write); 0 = no timeout |
| `.setHeader(name, value)` | Add a request header |
| `.onProgress` | Progress callback: `func(loaded, total)` |
| `.send(callback)` | Start the request; callback receives a response object |
| `.abort()` | Cancel an in-flight request; callback is not invoked |

**Body `Content-Type` auto-detection** (when `.contentType` is not set):

| `.body` type | Inferred Content-Type |
|---|---|
| string, looks like JSON | `application/json` |
| string, other | `text/plain` |
| `Array(uint8)` | `application/octet-stream` |

#### 10.2.2 Response object

The callback receives a **response object** with the following read-only fields:

| Field | Type | Description |
|---|---|---|
| `status` | int | HTTP status code |
| `ok` | bool | True if status is 2xx |
| `body` | string | Response body as text |
| `bodyRaw` | Array(uint8) | Response body as raw bytes |
| `contentType` | string | `Content-Type` header value |

The runtime selects `body` vs `bodyRaw` based on the response `Content-Type`: text types (`text/*`, `application/json`, `text/lhtml`, `text/lhtml-script`) populate `body`; binary types populate `bodyRaw`. Both fields always exist; the non-primary one is empty/null.

---

### 10.3 Storage

Scripts can persist data across page loads using two namespaces:

| Namespace | Lifetime | Scope |
|---|---|---|
| `storage` | Persistent (survives restart) | Origin |
| `session` | Current session only | Origin |

Both namespaces are isolated by **origin** (scheme + host + port). A script at `lht://example.com` cannot read or write data stored by `lht://other.com`.

#### 10.3.1 API

Both `storage` and `session` expose the same interface:

```js
storage.set(key, value)          /* write a string value */
storage.set(key, value, expires) /* write with expiry (seconds from now) */
storage.get(key)                 /* read; returns null if absent or expired */
storage.remove(key)              /* delete a key */
storage.keys()                   /* returns Array of all current keys */
storage.size()                   /* returns number of stored keys */
storage.clear()                  /* delete all keys in this namespace */
```

Keys and values are strings. To store structured data, serialize to/from JSON manually:

```js
let data = { score: 42, level: 3 };
storage.set("save", jsonEncode(data));

let loaded = jsonDecode(storage.get("save"));
```

`jsonEncode` and `jsonDecode` are built-in functions (see §9 standard library).

#### 10.3.2 Expiry

An optional `expires` parameter specifies a lifetime in **seconds from now**. The runtime silently discards expired entries on read:

```js
storage.set("token", tok, 86400);  /* expires in 24 hours */
```

Expired keys do not appear in `keys()` or count toward `size()`.

#### 10.3.3 Capacity limits

Storage capacity is implementation-defined. A conforming client must support at least:

| Namespace | Minimum capacity |
|---|---|
| `storage` | 16 KB per origin |
| `session` | 64 KB per origin |

When storage is full, `set` silently fails. Scripts that require reliable storage should check capacity before writing large values.

> **Implementation note:** On a real 286 system with a floppy-only configuration, persistent storage may be unavailable or very limited. The client may expose storage as a read-only no-op in such environments; scripts should not depend on persistence being available.

#### 10.3.4 Security model

- Storage is **origin-isolated**: no cross-origin access.
- Network access is **unrestricted**: a script may fetch any URL. The server is responsible for CORS-like access controls if needed.
- There is no ambient credential system (no cookies, no automatic auth headers). Scripts that need auth tokens must store and attach them explicitly.

---

### 10.4 Partial document requests (`LHT-Section`)

A client may request only the `<head>` portion of a document by including the `LHT-Section` request header:

```
GET /page.lht HTTP/1.1
Host: example.com
LHT-Section: head
```

The server streams the document token sequence up to and including the closing `</head>` token, then ends the response body. The response carries a `LHT-Partial: head` header to signal incompleteness:

```
HTTP/1.1 200 OK
Content-Type: application/lhtml
LHT-Partial: head
```

The response body is **not** a complete document — it is a raw head fragment. Clients must not attempt to render it as a page.

**Use cases:**

- **Link preview**: fetch `<title>`, description `<meta>`, and cover image URL without loading the body.
- **Search indexing**: a crawler indexes metadata cheaply, without transferring body content.
- **Tab title**: display the document title as soon as the head arrives, before body loading begins.

**Server implementation:**

- *Smart server:* streams the binary token sequence and stops after `END_HEAD`. No buffering required.
- *Static file server:* if the binary file prologue stores the body offset (Section 2.2), the server can satisfy the request with an HTTP `Range: bytes=0-<body_offset>` on the file, without parsing the token stream.

---

## 11. Content Negotiation

### 11.1 Overview

LHT supports content negotiation between client and server to select the most efficient representation of a document. The system is designed for three deployment scenarios:

| Server type | Description |
|---|---|
| **Dumb server** | Serves static files only; no negotiation |
| **Smart server** | Inspects request headers and serves optimal format |
| **Bundle server** | Pre-packages resources into a single `.lhb` bundle |

Negotiation is entirely header-driven. A client that cannot perform negotiation (e.g., a minimal client) receives a default representation that must be a valid, self-contained LHT document.

---

### 11.2 Client capability headers

When requesting an LHT document, a client announces its capabilities via HTTP headers:

| Header | Values | Description |
|---|---|---|
| `LHT-Version` | `1` | Highest LHT version supported |
| `LHT-Encoding` | `raw`, `huffman` | Accepted binary encodings |
| `LHT-Depth` | `1`, `4`, `8`, `15`, `16`, `24` | Display color depth in bits |
| `LHT-Canvas` | `none`, `basic`, `full` | Canvas support level |
| `LHT-Fonts` | `system` | Base font rendering capability; extensions may define additional values such as `lfnt` |
| `LHT-Scripts` | `none`, `bytecode`, `source` | Script execution capability |

Example request headers from a capable client:

```
GET /page.lht HTTP/1.1
Host: example.com
LHT-Version: 1
LHT-Encoding: raw, huffman
LHT-Depth: 8
LHT-Canvas: basic
LHT-Fonts: system
LHT-Scripts: bytecode
```

---

### 11.3 Server response

The server selects a representation based on the client's announced capabilities and responds with:

```
Content-Type: application/lhtml
LHT-Encoding: huffman
```

`LHT-Encoding` in the response indicates the encoding actually used.

Compression is based on the standard built-in token dictionary defined in Appendix A. External scripts, stylesheets, and images are cached by the client as regular resources (via normal HTTP caching); no separate dictionary negotiation mechanism is needed.

---

### 11.4 Dumb server fallback

A dumb server ignores all `LHT-*` request headers and serves a single static file. The file must be:

- A valid LHT binary stream, uncompressed (`raw` encoding), or
- A canonical text-form `.lht` file (the client parses and compiles it locally).

A client must be able to consume either format without negotiation. Negotiation is an optimization, not a requirement.

---

### 11.5 Bundle format (`.lhb`)

A bundle packages multiple resources (document + images + scripts + stylesheets) into a single file for offline use or efficient delivery over slow links.

Bundle structure (logical):

```
[bundle header]
  version, flags, resource count
[resource table]
  per resource: name, type, offset, length, encoding
[resource data]
  concatenated encoded resource payloads
```

A bundle is requested like a document; the client extracts the primary document and registers all bundled resources into its local resource cache. Subsequent resource references within the document are served from the cache without additional network requests.

> Bundle binary format details are in Appendix C.

---

## Appendices

### Appendix A — Token Assignments

*To be written.*

Complete table of varint token codes for the LHT binary stream: element tags, attribute identifiers, style property identifiers, built-in class names, and reserved ranges. Covers both the core token set and extension ranges for future versions.

---

### Appendix B — Canonical Text Form

*To be written.*

Formal grammar (EBNF) for the `.lht` source syntax. Covers document structure, `<head>` elements, `<style>` block syntax (constants, class definitions, state variants, shorthand values), `<body>` element syntax (attributes, inline content, text modifiers, text runs), `<script>` and `<style src=...>` references. Describes how the tokenizer maps text-form constructs to binary tokens.

---

### Appendix C — Bundle Binary Format (`.lhb`)

*To be written.*

Byte-level description of the `.lhb` container: magic number, header fields, resource table entry layout, encoding flags, alignment rules, and the algorithm for extracting and caching resources on load.

---

### Appendix D — Downloadable Font Extension

*To be written.*

Optional extension specification for downloadable bitmap fonts. If defined, it should cover the `.lfnt` file header, glyph table, per-glyph metrics, bitmap data layout, capability negotiation, cache semantics, and load timing rules that preserve predictable layout. This appendix is not part of base LHT conformance.

---

### Appendix E — Sample Documents

*To be written.*

Annotated examples in canonical text form:

- E.1 — Minimal document (hello world)
- E.2 — Document with styles, layout, and inline content
- E.3 — Document with images and a vector fallback
- E.4 — Document with scripts and event handlers
- E.5 — Document using fetch and storage

---
