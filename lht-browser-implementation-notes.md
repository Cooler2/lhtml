# LHT Browser Implementation Notes

**Status:** idea log  
**Scope:** possible implementation strategies for an LHT browser/client  
**Note:** these are client implementation ideas, not LHT format requirements

---

## HTTP Pipelining For Cacheable Static Resources

Idea: use a second HTTP connection dedicated to cacheable static resources, with HTTP pipelining enabled where supported.

The primary connection can stay focused on the main document and latency-sensitive control flow. The secondary connection can issue pipelined requests for static assets such as:

- image resources
- atlases
- stylesheets
- script/library files
- dictionaries/bundles

This is especially relevant for simple HTTP/1.x servers and constrained clients where opening many parallel connections is undesirable.

### Images With `Range`

For images, combine the static-resource pipeline with `Range` requests.

Strategy:

1. Request the beginning of the image file with `Range`.
2. If the file is small, the server may return the entire file.
3. If only the beginning is returned, parse enough header data to learn dimensions, format, palette/header metadata, and possibly decide priority.
4. Fetch the remaining bytes through a separate connection or later request.

Conceptual request:

```http
GET /assets/photo.jpg HTTP/1.1
Host: example.com
Range: bytes=0-4095
```

Possible outcomes:

- `200 OK`: server ignores `Range` or file is returned whole; cache complete resource.
- `206 Partial Content`: client has the header/initial segment; schedule remaining range if needed.
- cache hit: no request needed.

For small icons and atlas metadata, the initial range may be enough or may quickly reveal that fetching the rest is cheap. For large content images, the client can defer or reprioritize the remainder based on viewport visibility.

### Why A Separate Connection

Using a separate connection for cacheable static resources avoids blocking the main document/control stream behind large asset bodies. It also lets the client tune behavior independently:

- main connection: document, navigation, critical metadata;
- static connection: pipelined cacheable resources;
- optional extra connection: large range continuations or high-priority visible images.

This could be a good fit for vintage or low-resource clients where full modern HTTP/2-style multiplexing is unavailable.

### Open Questions

- How large should the initial `Range` request be for GIF, JPEG, LHT bitmap, and `.lhb` resources?
- Should atlas resources be fetched whole immediately if marked `required`?
- How should the client prioritize visible images versus below-the-fold images?
- How should this interact with normal HTTP cache headers and partial cache entries?
- Should a client disable pipelining for servers known to mishandle it?

---

## Layout And Paint Separation

The browser should not paint by walking the DOM directly. The intended pipeline is:

```text
DOM + resolved attributes
  -> layout
  -> display list
  -> paint backend
```

The display list is the stable boundary between layout and render. A backend should
receive already-positioned commands and only execute them.

Minimal command set:

```text
FillRect(owner, originX, originY, x, y, w, h, color)
StrokeRect(owner, originX, originY, x, y, w, h, color)
TextRun(owner, originX, originY, x, baselineY, text, fontFace, fontSize, color)
```

Text commands use `baselineY`, not top-y. This lets different backends map the same
layout data naturally:

- GDI can use `TextOut` with a baseline-aware coordinate path.
- A bitmap-font backend can compute `glyphTop = baselineY - ascent`.
- A developer browser can draw baseline overlays without recomputing layout.

This also enables efficient repaint:

- layout runs only when DOM, styles, viewport, fonts, or resources change;
- normal paint can replay the display list;
- block repaint can filter commands by DOM owner and paint them at the stored origin;
- dirty rects can be handled by filtering display commands;
- layout/debug dumps can inspect display commands directly.

The current reference renderer has the first `LhtDisplayList` layer in place.
Layout builds `FillRect`, `StrokeRect`, and `TextRun` commands, then both BMP and
GDI renderers consume the same list. `TLhtCanvas.DrawTextRun` is the backend
boundary: the base path draws glyphs, while the GDI path uses one `TextOut` call
per run. Display commands are owned by DOM nodes and keep local coordinates inside
that owner's block, plus the current absolute origin for full-page replay.
`TLhtDisplayList.PaintOwner` can replay only commands for a single DOM node.
