# Light HyperText Format (LHT) — Specification Draft, Part 2

**Version:** 0.1 (draft)
**Status:** Work in progress
**Continues from:** lht-spec-part1.md (sections 1-4)

---

## Table of Contents (this document)

5. [Resources and Images](#5-resources-and-images)
6. [Fonts](#6-fonts)

(Section 7 — Inline Content — is in lht-spec-part3.md. Sections 8+ to follow: Events, Scripts, Network, Storage, Content Negotiation.)

---

## 5. Resources and Images

LHT separates the concept of an *image* from the concept of a *resource*. A resource is a physical binary asset (a GIF file, a JPEG file, a font file). An image is a logical reference used in document content; it may map to a resource directly, to a region of a resource, or to a derived/transformed version. This indirection enables responsive selection (different physical assets per client capability), atlas-based packing, and inexpensive transformations (tint, flip, patch9) without duplicating data.

### 5.1 The three-level model

```
+----------------------+
| DOM nodes            |  (e.g., <img name="user-icon"/>)
+----------------------+
           |
           v references
+----------------------+
| Image definitions    |  (logical images, possibly conditional)
+----------------------+
           |
           v reference resources
+----------------------+
| Resources            |  (GIF/JPEG files, atlases)
+----------------------+
```

**Resources** are physical files: images (GIF, JPEG), fonts, scripts, dictionaries. They have a name, a media type, and binary content. They are loaded from URLs and cached by the client.

**Image definitions** are logical references. They name an image and describe how to derive it: which resource to use, what region to crop, what transformations to apply. They may have multiple variants selected by client capabilities.

**DOM nodes** reference images by name only — they do not know about resources or transformations.

This separation allows three independent kinds of evolution:

- A document can change its image references (DOM evolves) without touching image definitions.
- An image definition can switch to a different resource (e.g., new atlas) without changing DOM references.
- A resource can be re-encoded or re-packed without breaking image definitions, as long as referenced regions stay valid.

### 5.2 Resources

Resources are declared in `<style>` blocks using the `@resource` directive:

```css
@resource ui-atlas   gif  "/assets/atlas.gif";
@resource logo-large jpeg "/assets/logo.jpg";
@resource forum-dict lhd  "/dict/forum-v3.lhd";
```

#### 5.2.1 Resource types

The base specification defines the following resource types. Clients may support additional types via extensions.

| Type | Media type | Notes |
|---|---|---|
| `gif` | image/gif | GIF87a (preferred) or GIF89a |
| `jpeg` | image/jpeg | Baseline only; no progressive |
| `bitmap` | application/lhtml-bitmap | LHT-native indexed bitmap (compact, optional) |
| `font` | application/lhtml-font | Optional downloadable-font extension; not part of base LHT (Section 6.5) |
| `style` | text/lhtml-style | External stylesheet (.lss) |
| `script` | text/lhtml-script | Script source (.ls); bytecode variant: application/lhtml-script |
| `lhv` | application/lhtml-vector | LHT vector image — canvas draw commands (Section 5.9) |

Resource types not on this list are passed through but not interpreted by core engine.

#### 5.2.2 Conditional resources

A resource may have multiple URL variants, selected by client capabilities at load time. Only the matching variant is fetched.

```css
@resource hero-image {
  when minDepth=16: jpeg "/img/hero-truecolor.jpg";
  when minDepth=8:  jpeg "/img/hero-vga.jpg";
  when minDepth=4:  gif  "/img/hero-ega.gif";
}
```

The client evaluates clauses top to bottom and uses the first matching one. If no clauses match, the resource is unavailable; references to it produce a placeholder.

#### 5.2.3 Resource loading and the `required` marker

Resources are loaded on demand by default — fetched when first referenced during rendering. This is sufficient for resources that appear directly in the document.

For resources declared inside an *external* stylesheet, there is a one-level indirection: the stylesheet must be fetched and parsed before the resources it declares become known. To reduce this latency, a resource may be marked `required`:

```css
@resource ui-atlas gif "/assets/atlas.gif" required;
```

When the client encounters a `required` resource while processing a stylesheet, it begins fetching it immediately — without waiting for a DOM reference. `required` is a hint; clients under memory pressure may ignore it.

Use `required` for resources that are nearly always needed and whose fetch would otherwise be delayed by stylesheet indirection. Do not use it speculatively — unnecessary early fetches waste bandwidth on constrained clients.

### 5.3 Image definitions

Image definitions are declared in `<style>` blocks alongside the resources they reference. The simplest form names a resource directly:

```css
@imageDef hero src=hero-image;
```

This makes `hero` a logical image that resolves to the `hero-image` resource.

#### 5.3.1 Operations

An image definition may apply operations on top of a source resource. Operations describe rendering recipes; they are evaluated at render time without creating new bitmap data in memory.

```css
@imageDef user-icon   src=ui-atlas  crop="0,0,16,16";
@imageDef send-button src=ui-atlas  crop="16,0,32,16";
@imageDef left-arrow  src=ui-atlas  crop="48,0,16,16"  flipX;
@imageDef error-icon  src=ui-atlas  crop="64,0,16,16"  tint=#FF4040;
@imageDef panel-bg    src=ui-atlas  crop="80,0,32,32"  patch9="4,4,4,4";
```

Supported operations:

| Operation | Parameters | Effect |
|---|---|---|
| `crop` | `x, y, w, h` | Use only the specified rectangle from the source |
| `flipX` | (boolean flag) | Mirror horizontally |
| `flipY` | (boolean flag) | Mirror vertically |
| `tint` | color | Multiply pixel values by tint color (palette remap on indexed sources) |
| `patch9` | `left, right, top, bottom` | Treat as a patch9 with given fixed-margin sizes |

Operations may be combined on a single image definition. They are applied in a fixed order: `crop` first (selecting the source region), then geometric transforms (`flip-*`), then color transforms (`tint`), then `patch9` interpretation. This order ensures predictable composition.

#### 5.3.2 Why operations don't create copies

These operations modify how the image is rendered, not what's stored. The atlas resource resides in memory once, and many image definitions can reference different regions and transforms of it without duplication.

- `crop` is just a source rectangle — render code reads from `(src_x, src_y)` to `(src_x+w, src_y+h)`.
- `flipX` reverses iteration direction during blit (`STD` instead of `CLD` on x86; zero overhead).
- `flipY` negates the source line stride.
- `tint` on an indexed (palettized) source is a palette remap lookup — one byte per pixel, no recomputation. On high-color sources, it's a per-pixel multiply (fast on 486+, faster with MMX).
- `patch9` divides rendering into 9 regions with three different stretch behaviors (corners fixed, edges stretched on one axis, center stretched on both); this is a render-time loop, not stored data.

For 286-class clients with limited memory, this is critical: a UI atlas of 256×256 (64 KB at 8bpp) can host hundreds of logical images without per-image memory cost.

#### 5.3.3 Future extension: composition (`compose`)

Composition is not part of base LHT v1. If this capability is needed later, the preferred direction is script/canvas-generated images rather than a separate declarative `compose` mini-language.

The original declarative idea was a `compose` image definition that builds a new bitmap by overlaying multiple sources at specified positions:

```css
@imageDef avatar-with-status {
  compose:
    layer src=ui-atlas crop="100,0,32,32";
    layer src=ui-atlas crop="132,0,8,8"  at="24,24";
}
```

Unlike base v1 operations (`crop`, `flipX`, `flipY`, `tint`, `patch9`), composition requires creating a new bitmap in memory. The result would normally be cached per image definition, so the cost is paid once, but the feature still requires extra RAM, a nested declaration syntax, layer ordering rules, and fallback behavior.

A future script-accessible image API can cover this use case without expanding `@imageDef` syntax:

```js
let img = Image.create(32, 32);
let ctx = img.getContext();
ctx.drawImage("avatar-base", 0, 0);
ctx.drawImage("status-dot", 24, 24);
document.defineImage("avatar-live", img);
```

This reuses the canvas/image machinery and also supports procedural icons, badges, thumbnails, and other generated images.

Base v1 clients are not required to parse or render `compose`. Documents targeting base v1 should express image variants through `@resource`, `@imageDef`, `crop`, transforms, `patch9`, and conditional `when` clauses.

#### 5.3.4 Conditional image definitions

Like resources, image definitions can have variants for different client capabilities:

```css
@imageDef hero {
  when minDepth=16: src=hero-truecolor;
  when minDepth=8:  src=hero-vga;
  when minDepth=4:  src=hero-ega;
}
```

The first matching variant is used. Multiple operations can be applied within a `<variant>` clause, identical to a non-conditional `<imageDef>`.

This is the canonical place to express "use a higher-quality version when the display can show it" — at the imageDefinition layer, not at the DOM. The DOM simply references `hero` and gets the appropriate concrete image for the client.

#### 5.3.5 Built-in placeholder

When an image cannot be resolved (no matching variant, resource fetch failed, format unsupported), the engine substitutes a built-in placeholder graphic. The placeholder is a small "broken image" icon at the natural size of the image reference, or at a default size if natural size is unknown.

Authors may override the placeholder for a specific image:

```css
@imageDef avatar src=avatars/user-123 placeholder=default-avatar;
```

Where `default-avatar` is another image definition that resolves successfully.

### 5.4 Image references in DOM

In document content, images are referenced by name:

```
<img name="user-icon"/>
<img name="user-icon" width=24 height=24/>     <!-- with size override -->
<img name="hero" alt="Welcome banner"/>
```

`<img>` is a leaf element. Its size is determined as follows:

1. If `width` and `height` are explicitly given, those are used.
2. Otherwise, the image's natural size (resource pixel dimensions, modified by crop) is used.
3. If only one of width/height is given, the other is derived to preserve the natural aspect ratio.

The `alt` attribute provides text content for accessibility, screen readers, and fallback display when the image cannot be rendered.

### 5.5 Atlases

An atlas is a single resource (typically a GIF) containing many small images packed into one. By using `crop` operations, multiple image definitions reference different regions of the atlas without separate downloads or memory allocations.

Atlases are recommended for:

- UI icon sets (toolbar icons, status indicators).
- Sprite sheets for games and animations.
- Logo and branding marks.
- Decorative elements that recur throughout a document.

#### 5.5.1 Why atlases use a single resource format

The atlas itself is just a GIF (or JPEG) file. There is no special "atlas format." The `crop` operation does the work. This means:

- Standard tools create atlases (TexturePacker, ImageMagick scripts, custom tooling).
- The atlas can be viewed directly in any image viewer, simplifying debugging.
- Smaller per-document overhead than a custom atlas container format.

A common practice is to have one shared UI atlas per site (or per page section), referenced by many image definitions. Mark it `required` in the stylesheet so the client fetches it as soon as the stylesheet is processed; subsequent UI rendering is from memory, with no further fetches.

#### 5.5.2 Atlas palettes

When using a palettized atlas (GIF or LHT bitmap), all images cropped from it share the atlas's palette. This is desirable: switching palettes mid-render causes visible artifacts on indexed displays.

For a site with a large UI surface, the recommended approach is:

1. Design the UI's color palette as a fixed set of, e.g., 64-128 entries.
2. Build the atlas using only these colors.
3. The remaining palette slots are available for content images.

This approach, similar to how DOOM partitioned palette slots in the 1990s, lets dynamic content (photos, diagrams) coexist with UI without conflict.

### 5.6 Conditions

The `<when>` clause used by conditional resources, image definitions, and constants (Section 3.3.3) takes a fixed set of capability predicates:

| Predicate | Type | Meaning |
|---|---|---|
| `minDepth` | int | Display color depth in bits — at least N; valid values: 1, 4, 8, 15, 16, 24 |
| `minCpu` | enum | CPU class: `8086`, `286`, `386`, `486`, `586`, `686+` |
| `hasFpu` | bool | Floating-point unit available |
| `hasMmx` | bool | MMX or equivalent SIMD available |
| `minRamKb` | int | At least N KB of RAM |
| `minWidth` | int | Display width at least N pixels |
| `minHeight` | int | Display height at least N pixels |
| `media` | enum | Output medium: `screen`, `print`, `speech` |
| `canvas` | enum | Canvas support level: `none`, `basic`, `full` (Section 4.10.2) |

Multiple predicates within a single `<when>` clause are combined with logical AND — all must match. Disjunction (OR) is expressed by using multiple `<when>` clauses with the same outcome.

There are no comparison operators beyond the `min-*` predicates listed above. There are no negations. This restriction keeps the condition-evaluation logic simple and the predicates' intent obvious.

#### 5.6.1 Why a fixed predicate set

Allowing arbitrary expressions in conditions would require parsing and evaluating an expression language at the client. Instead, conditions are tabular: each `<when>` clause is a list of predicate constraints, all of which must hold. The client evaluates a small fixed-size predicate vector once at load and checks it against each `<when>`.

This makes conditions:
- Trivial to implement (a few branches per predicate).
- Trivial to optimize (predicate values can be precomputed).
- Easy to author (no expression syntax to learn).
- Easy to validate (no parsing errors possible).

### 5.7 Resource lifecycle and caching

Resources are cached by the client according to standard HTTP semantics (cache headers, etag, last-modified). The cache is keyed by URL plus the chosen `<when>` variant.

Cached resources persist across sessions (subject to client cache limits). Re-visits to the same site, or visits to other pages of the same site, can reuse cached atlases, fonts, and dictionaries.

For sites that ship a shared UI atlas across many pages, the first page load fetches the atlas once; subsequent pages reuse it from cache, with no further network cost for UI graphics. This is a key efficiency in LHT compared to systems where UI graphics are bundled with each page.

### 5.8 Inline image data (small images)

For images small enough that the overhead of a separate HTTP request outweighs their data, inline encoding is supported:

```css
@resource dot bitmap data="...base64...";
```

The `data` attribute contains base64-encoded resource bytes. This is an exception to the "resources are URLs" rule; it's intended for images of perhaps 100 bytes or less, where a separate request would dominate the cost.

For most images, including inline encoding is discouraged — atlases are a better solution for large numbers of small images.

### 5.9 Vector images

A vector image resource (`type="lhv"`) contains a sequence of canvas drawing commands (Section 4.10). It is rendered by the client on demand into an off-screen surface of the requested size, then composited like any raster image.

From the DOM's perspective, a vector image is indistinguishable from a raster one — it is referenced by name through the same image definition system:

```css
@resource logo-vec lhv "/img/logo.lhv";
@imageDef logo     src=logo-vec;
```

Then used anywhere images are accepted:

```
<img name="logo" width=120 height=40/>   ; in document content
ctx.drawImage("logo", x, y, 120, 40);         ; on a canvas
```

When `drawImage` specifies dimensions that differ from the image's natural size, a vector source is re-rendered at the requested size without quality loss. A raster source is scaled with the client's available filter.

#### 5.9.1 Fallback for clients without canvas

Clients that report `canvas=none` cannot render `lhv` resources. The conditional resource mechanism handles this transparently:

```css
@resource logo-vec {
  when canvas=full:    lhv "/img/logo.lhv";
  when canvas=basic:   lhv "/img/logo.lhv";
  when minDepth=8:     gif "/img/logo.gif";
  when minDepth=4:     gif "/img/logo-16c.gif";
}
```

`canvas=basic` clients can render `lhv` if it uses only primitives (no path API). Authors targeting `basic` clients should restrict vector image commands accordingly.

#### 5.9.2 LHV format

An `lhv` file is a sequence of canvas drawing commands in the LHT binary stream format. It has its own magic bytes (`LHV1`) and contains only drawing API calls — no document structure, no event handlers, no network access.

The natural size of a vector image is declared in the file header (`width`, `height` in pixels). This size is used when no explicit dimensions are given at the reference site.

The full binary encoding of LHV commands follows the same varint/token scheme as the main LHT format (Section 2). The canonical text form of an LHV file is a bare sequence of drawing calls:

```
; logo.lhv — natural size 120×40
width=120 height=40

fillRect 0 0 120 40 #336699
fillText "MyApp" 8 12 font=default-sans-18-bold color=#FFFFFF
strokeRect 0 0 120 40 1 #FFFFFF
```

---

## 6. Fonts

Fonts in base LHT are logical bitmap-font references. Documents request a logical font name; the client maps that name to one of its built-in or system bitmap fonts. Base LHT does not define downloadable fonts and does not require clients to load font resources from documents.

Downloadable LHT bitmap fonts may be defined by an optional extension. That extension is deliberately outside the base specification because late font loading complicates deterministic layout, first render timing, memory budgeting, and failure handling on constrained clients.

### 6.1 Logical font names

Documents reference fonts by logical name. The logical name describes the desired family, weight, style, and approximate size:

```
<text font="default-serif-12">Hello</text>
<text font="default-mono-10">code</text>
<text font="default-sans-18-bold">Heading</text>
```

The logical name is a contract, not an exact file selection: the client picks the closest available concrete font. This includes the system's bitmap font if it is a better match than the client's bundled LHT defaults.

#### 6.1.1 Logical name structure

A logical font name has the form:

```
[family]-[size][-style]
```

Where:

- `family` is one of `default-sans`, `default-serif`, `default-mono`, `default-heading`, or an implementation-defined system family exposed by the client.
- `size` is the approximate height in pixels (8, 10, 12, 14, 18, 24).
- `style` is optional; one of `bold`, `italic`, `bold-italic`.

Example names: `default-sans-12`, `default-serif-14-italic`, `default-mono-10-bold`.

#### 6.1.2 Built-in fonts

Conforming clients ship with the following built-in fonts at minimum:

| Family | Sizes | Styles |
|---|---|---|
| `default-sans` | 8, 10, 12, 14, 18 | regular, bold |
| `default-serif` | 10, 12, 14, 18 | regular, bold, italic |
| `default-mono` | 8, 10, 12 | regular, bold |
| `default-heading` | 18, 24, 32 | regular, bold |

Built-in fonts cover Latin (ASCII + Latin-1 supplement) and Cyrillic ranges. Additional ranges (Greek, additional Latin extended) are optional.

Minimal clients (Section 1.3, "Minimal" class) may ship with a reduced set, e.g., only `default-sans-12` regular. Such clients substitute available fonts for unavailable ones, with predictable degradation.

#### 6.1.3 Selection algorithm

When a document requests a font by logical name, the client selects a concrete font file by:

1. Looking for an exact match in available built-in fonts.
2. If unavailable, looking for the requested family at a size within ±25%, same style.
3. If unavailable, looking for the requested family at any size, same style.
4. If unavailable, falling back to a related family (`default-serif` <-> `default-sans` for body text, `default-mono` <-> `default-mono` only, `default-heading` <-> `default-sans-bold` larger size).
5. If all else fails, using the system's default font.

This procedure produces a defined fallback at every step. Authors should not assume pixel-exact font dimensions but can rely on the selected font being reasonably close to the request.

### 6.2 Soft typographic determinism

Text layout is *not* pixel-deterministic across different clients. Different clients may have different concrete fonts substituted for the same logical name; these fonts may have slightly different glyph metrics. This produces small layout variations: a paragraph might break at slightly different positions on different clients, individual words might occupy a few pixels more or less, line heights might vary by a pixel or two.

This is intentional. Strict pixel-determinism would require either:

- A single mandated font file per logical name, defeating fallback and system-font integration; or
- Forbidding clients from using improved fonts even when available (e.g., 2bpp anti-aliased on high-color displays).

Instead, LHT layout guarantees *structural* determinism (same elements, same nesting, same wrapping behavior at the paragraph level) but allows fine typographic variation. Authors must design layouts with reasonable flexibility — not relying on pixel-exact widths of text — and use `nowrap` (Section 4.4) to prevent breaks at critical points.

### 6.3 Built-in font requirements

Base clients provide bitmap fonts with fixed metrics known before layout begins. A client may implement these fonts as bundled LHT bitmaps, host OS bitmap fonts, ROM fonts, or any other local representation; the storage format is not visible to documents.

The base font model requires:

- At least 1 bit per pixel rendering.
- Proportional and fixed-width font support where the built-in family requires it.
- Stable per-glyph advance and line metrics for the duration of a document.
- Unicode codepoint lookup for all supported glyph ranges.

Clients may use higher-quality local rendering (for example 2bpp antialiasing on high-color displays) as long as the selected font's metrics remain stable during a layout pass.

#### 6.3.1 Missing glyphs

If a requested codepoint is not in the selected font, the client falls back through its local font fallback chain. If no available font has the glyph, the client renders a default "missing glyph" mark — typically an empty rectangle at the height of the current font.

### 6.4 Font fallback chains

A logical font name may map to a client-local chain of physical fonts, with later fonts providing glyphs missing from earlier ones. Documents do not define or load these chains in base LHT; the chain is part of the client's font configuration.

When rendering text, the engine tries each font in the chain for each glyph until it finds one that has the codepoint. This allows a client to combine a compact primary font with broader system coverage for Cyrillic, Greek, symbols, or other ranges.

### 6.5 Downloadable fonts extension

Downloadable fonts are not part of base LHT. An optional extension may define:

- A compact bitmap font file format such as `.lfnt`.
- A `font` resource type.
- `@fontDef` declarations in stylesheets.
- Capability negotiation, for example `LHT-Fonts: lfnt`.
- Load timing rules that prevent unexpected re-layout.

### 6.6 Bold and italic

Built-in fonts ship with separate bold and italic variants where available. For these, requesting `default-serif-12-bold` selects the bold-specific glyphs, which have been hand-designed for the size — visually superior to algorithmic emboldening.

When a requested local bold or italic variant is unavailable, the engine may apply algorithmic emphasis:

- **Algorithmic bold:** render each glyph with a 1-pixel horizontal smear (draw at offset 0 and offset +1, OR'd together).
- **Algorithmic italic:** apply a small horizontal shear to glyph rendering.

These are visibly worse than hand-designed variants. Authors should request logical bold/italic variants where available, but must tolerate client substitution.

### 6.7 Text-level attributes

The following attributes apply to text nodes (and inherit per Section 3.5):

| Attribute | Type | Effect |
|---|---|---|
| `font` | font-name | Logical font for this text |
| `color` | color | Foreground color |
| `bgColor` | color | Background color (per glyph cell, if specified) |
| `bold` | bool | Switches to bold variant of current font |
| `italic` | bool | Switches to italic variant |
| `underline` | bool | Draws a 1-pixel underline at baseline + descent |
| `strikethrough` | bool | Draws a 1-pixel line through the middle of x-height |
| `lineHeight` | length | Distance from one baseline to the next; default = font's intrinsic height |
| `textAlign` | enum | `left` (default), `right`, `center`, `justify` |
| `letterSpacing` | length | Additional pixels between glyphs (default 0) |
| `wordSpacing` | length | Additional pixels between words (in addition to natural space width) |

Underline and strikethrough are drawn as separate operations after glyph rendering; they are not part of the font.

### 6.8 Kerning and ligatures

Kerning (per-pair adjustment of inter-glyph spacing) is **not supported**. At the typical sizes of bitmap fonts on low-resolution displays, kerning is barely perceptible and considerably complicates the renderer. Each glyph's advance width is its bitmap width plus a small fixed gap (typically 1 pixel, baked into glyph widths).

Ligatures are **not supported** for the same reasons. The text "fi" is rendered as "f" followed by "i".

### 6.9 Vector fonts (future direction)

This specification defines bitmap fonts only. A future version may introduce a parametric vector font format optimized for low-resolution displays — with stroke-based glyph descriptions, built-in hinting through stroke semantics, and copy/mirror operations for compactness. This format is conceptually compatible with the same logical-name layer, but its specification is deferred to a future revision.

---

*End of Sections 5-6.*

*Open questions in this part:*

- *Whether a future downloadable-font extension should define `.lfnt`, and if so whether fonts block first layout or use predeclared metrics.*
- *LHT-native bitmap (`bitmap` resource type) — format not yet specified; may be omitted from base spec if GIF coverage is sufficient.*
- *Font metric sharing across clients — should soft determinism be tightened with a "metrics file" that overrides client font metrics with a canonical set? (Probably not, but mention as alternative.)*
- *Whether `<img>` is a leaf element or an inline atom (per the inline content model in Section 7, to be written).*
- *Color format in `tint` and elsewhere — RGB only, or RGBA? If A, how does it interact with palettized rendering? (Probably keep RGB only in v1, deferring transparency to GIF-native transparent index.)*
