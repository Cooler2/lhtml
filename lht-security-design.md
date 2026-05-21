# LHT Security Model — Design Note

**Status:** proposal  
**Scope:** security rules for scripts, network, storage, resources, and navigation  
**Goal:** keep the model small enough for constrained clients while avoiding the worst historical web security mistakes

---

## 1. Design goals

LHT should not inherit the full complexity of browser security. It also cannot be "anything may fetch anything" once scripts and persistent storage exist. Even without cookies, unrestricted network access lets a document use the client as a proxy into local networks, probe private services, or exfiltrate data explicitly stored by the document.

The security model should therefore be:

- **Origin-based by default.** Documents, storage, scripts, and active network reads are scoped to an origin.
- **Explicit for cross-origin data.** A script may read cross-origin response bodies only when the target server opts in.
- **Simple to implement.** No full CORS preflight machinery in v1.
- **No ambient credentials.** No cookies, no automatic auth headers, no automatic client certificates.
- **Passive resources are different from script-readable data.** Showing an image is less powerful than reading its bytes.
- **Local network protection is built in.** Internet documents should not be able to probe private addresses.

---

## 2. Origins

An origin is:

```
scheme + host + port
```

Examples:

| URL | Origin |
|---|---|
| `lht://example.com/page.lht` | `lht://example.com:default` |
| `https://example.com:8443/page.lht` | `https://example.com:8443` |
| `file:///docs/page.lht` | implementation-defined local-file origin |

Different schemes are different origins. `lht://example.com` and `https://example.com` do not share storage or script authority unless a future embedding profile explicitly defines that relationship.

For `file:` documents, the safest default is a unique opaque origin per opened file or per directory, chosen by the client. A permissive "all local files share one origin" mode should be a user-controlled compatibility option, not the default.

---

## 3. Storage rules

Storage is strictly origin-isolated.

Rules:

- `storage` and `session` are keyed by origin.
- A script can read and write only its own origin's storage.
- Cross-origin requests do not grant storage access to the remote origin.
- Navigation to another origin switches the active storage namespace.
- There are no cookies and no automatic persistence attached to network requests.

Example:

```js
storage.set("token", "abc");

/* Later, on the same origin: */
let token = storage.get("token");  /* "abc" */

/* On any other origin: */
let token = storage.get("token");  /* null */
```

This keeps persistent state understandable: data belongs to the document's origin, not to arbitrary URLs that the document contacts.

---

## 4. Navigation

Navigation is less restricted than script-readable network access.

Rules:

- `<a href=...>` may navigate to any URL scheme supported by the client.
- Script-initiated navigation may navigate to any supported URL, subject to client UI policy.
- Navigation does not expose the destination document's contents to the source script.
- A minimal client may open `target=new` in the same window if it has no tab/window concept.

Rationale: following a link is a user-visible action. Reading another origin's response body is not.

---

## 5. Passive resources

Passive resources are resources used for rendering but not exposed as script-readable bytes:

- images
- stylesheets
- fonts if a future downloadable-font extension exists
- resource bundles, subject to bundle-specific rules

Base rule:

- A document may reference passive resources cross-origin.
- The client may render them.
- Script cannot read their raw contents unless the resource is also fetched through `Request`, and `Request` passes the active network rules below.

Example:

```css
@resource logo gif "https://cdn.example.net/logo.gif";
@imageDef logo src=logo;
```

This may render cross-origin. But:

```js
let req = Request("https://cdn.example.net/logo.gif", "GET");
req.send(func(r) {
  /* r.bodyRaw is available only if active cross-origin read is allowed. */
});
```

The visible result and the script-readable data channel are deliberately separate.

---

## 6. Active network requests

Active network requests are made through `Request`. These are script-readable and therefore need stricter rules.

Recommended v1 policy:

| Request | Default |
|---|---|
| same-origin `GET` | allowed |
| same-origin `POST`, `PUT`, `DELETE` | allowed |
| cross-origin `GET` | allowed only if target opts in |
| cross-origin `POST`, `PUT`, `DELETE` | forbidden in v1 |
| cross-origin custom headers | forbidden in v1 |
| automatic credentials | never sent |

The restriction to cross-origin `GET` avoids preflight. It also makes the policy easy for a small client: perform the request, inspect response headers, then decide whether the body is visible to script.

### 6.1 Cross-origin opt-in

A cross-origin response body is exposed only if the response includes:

```http
LHT-Allow-Origin: *
```

or:

```http
LHT-Allow-Origin: lht://example.com
```

The value must match the requesting document's origin, or be `*`.

Optional future headers:

```http
LHT-Allow-Methods: GET, POST
LHT-Allow-Headers: Content-Type, X-Token
```

These should not be needed in base v1 if cross-origin active requests are limited to simple `GET` without custom headers.

### 6.2 Response object for blocked reads

If the network succeeds but the response is not readable due to policy, the callback still receives a response object:

```js
req.send(func(r) {
  if (!r.ok) {
    showError(r.error);
    return;
  }

  useData(r.body);
});
```

Suggested fields:

| Field | Value for blocked cross-origin read |
|---|---|
| `status` | actual HTTP status if known |
| `ok` | `false` |
| `error` | `"cross-origin-denied"` |
| `body` | `""` or `null` |
| `bodyRaw` | `null` |

The client should not silently return the body and trust authors to behave.

---

## 7. Redirects

Redirects must be rechecked.

Rules:

- A same-origin request redirected to same-origin remains allowed.
- A same-origin request redirected to cross-origin becomes cross-origin and requires `LHT-Allow-Origin`.
- A cross-origin request redirected to another cross-origin also requires opt-in from the final response.
- The final URL's origin is what matters for body visibility.

Example:

```
Request("/api/data", "GET")
  -> 302 https://api.example.net/data
  -> 200 without LHT-Allow-Origin
```

Result: request completes, but body is not exposed to script.

---

## 8. Local network protection

A document loaded from a public origin must not be able to probe private networks through the client.

Private targets include:

- loopback: `127.0.0.0/8`, `::1`
- private IPv4 ranges: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`
- link-local ranges: `169.254.0.0/16`, `fe80::/10`
- local hostnames resolved to private addresses

Recommended rule:

- If the document origin is public, `Request` to private/local targets is blocked.
- If the document origin itself is private/local, requests to the same private/local origin are allowed.
- Broader private-network access may be a user permission or client configuration, not a document capability.

Blocked result:

```js
req.send(func(r) {
  if (r.error == "private-network-denied") {
    showError("local network access denied");
  }
});
```

This single rule prevents a remote LHT page from scanning a router admin panel or intranet service.

---

## 9. Script and library loading

Regular scripts and libraries have different authority.

A regular `<script>` runs in the document's global scope. It can access the DOM, storage, timers, network APIs, and other document capabilities. For that reason, cross-origin regular scripts should not be part of base v1.

A `<library>` runs in an isolated library scope. It has no ambient access to the document, storage, DOM, network, or caller globals. It can only use its own local code, its private globals, and values explicitly passed to its exported functions. Under that rule, a cross-origin library is much closer to a pure module than to a regular script.

Recommended v1 rules:

- Regular `<script src=...>` loads only same-origin scripts.
- Cross-origin regular script execution is forbidden in v1.
- `<library src=...>` may load same-origin or cross-origin libraries.
- Dynamic `loadLibrary(...)` may load same-origin or cross-origin libraries.
- Cross-origin libraries must run under the same library sandbox as same-origin libraries.
- Cross-origin libraries must not receive ambient document capabilities.
- Integrity hashes are recommended for cross-origin libraries and may become required by a stricter deployment profile.

Example:

```lht
<library
  src="https://cdn.example.net/chart-1.2.0.ls"
  interface="Chart"
  integrity="sha256-...">
```

The `integrity` attribute protects the author from silent code replacement by the CDN or an intermediary. If present, the client verifies the fetched bytes before compiling or executing the library. If verification fails, the library is unavailable.

### 9.1 Library sandbox

A library scope does not contain:

- `document`
- `getElement`
- `storage` or `session`
- `Request`
- navigation APIs
- caller globals
- DOM constructors or element traversal APIs

The library may export functions:

```js
function formatMoney(n) { ... }
function drawChart(ctx, data) { ... }

exports { formatMoney, drawChart };
```

The caller decides what to pass:

```js
let ctx = getElement("chart").context();
Chart.drawChart(ctx, series);
```

This is safe because `ctx` is a narrow drawing capability, not part of the DOM object API.

### 9.2 Host objects and capabilities

Values passed into a library should be one of:

- plain scalar data: int, bool, string, null
- arrays or records that do not expose host authority
- other library interface objects
- explicit narrow capability objects

The DOM object API is not available in an isolated library context. A value passed to a library must not expose DOM traversal, document lookup, event registration, or mutation APIs unless a future DOM-capability extension defines a constrained wrapper. In base v1, real DOM element objects are not library-visible values.

For canvas use cases, pass a drawing-only context capability:

```js
Chart.draw(ctx, data);
```

The drawing context may expose:

```js
ctx.fillRect(...);
ctx.strokeLine(...);
ctx.fillText(...);
ctx.drawImage(...);
```

It is not a DOM object and does not expose:

```js
ctx.canvas;
ctx.ownerDocument;
ctx.parent;
ctx.getElement(...);
ctx.on(...);
```

If a document wants to grant a library controlled access to network or storage, it should pass a narrow function that enforces the document's policy:

```js
Chart.loadTheme(func(url, cb) {
  if (startsWith(url, "/chart-themes/")) {
    fetchText(url, cb);
  } else {
    cb(null);
  }
});
```

This follows a capability model: libraries can do only what they are explicitly handed.

Runtime script profiles should follow the same rule. A profile is an authority
boundary: `isolated` exposes no host objects, while a debugging or browser
profile may enable narrow capabilities such as debug output or browser alerts.
Host object names are not language builtins; they are bindings selected by the
active profile.

---

## 10. Recommended normative wording

Base LHT should say:

1. A document has an origin derived from its URL.
2. Storage is isolated by origin.
3. Scripts may issue same-origin HTTP requests.
4. Scripts may issue cross-origin `GET` requests only when the final response includes `LHT-Allow-Origin` matching the document origin or `*`.
5. Scripts may not issue cross-origin state-changing methods in v1.
6. Scripts may not set custom headers on cross-origin requests in v1.
7. No automatic credentials are sent with any script request.
8. Passive resources may be rendered cross-origin but are not readable by scripts through the rendering pipeline.
9. Regular script source must be same-origin in v1.
10. Libraries may be same-origin or cross-origin, but always run in an isolated library scope with no ambient document capabilities.
11. Host objects passed to libraries must be plain data, library interfaces, or explicit narrow capabilities; the DOM object API is not available in isolated library contexts.
12. Public-origin documents may not make active requests to private/local network targets.

This gives LHT a small, auditable security model without importing the full web platform.
