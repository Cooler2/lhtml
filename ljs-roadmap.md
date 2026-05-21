# LJS Roadmap

This document tracks the script-language work as a separate stream from the
LHT document, DOM, style, layout, and rendering work.

The integration surface with LHT should stay small:

- `<script>` is a document section;
- script content is encoded as a separate SCRIPT stream;
- document-level docs describe where scripts are allowed and how the stream is
  entered;
- LJS docs describe the script language, token stream, validation, and runtime.

## Goals

- Avoid lexical analysis on the client by storing pre-tokenized script source.
- Preserve source semantics without committing to a VM or bytecode too early.
- Keep the first slice independent from DOM and browser APIs.
- Make later interpretation or bytecode compilation straightforward.

## Slice 1: Token Stream

Status: implemented in the reference mini toolchain.

Scope:

- parse `<script>` text with a minimal LJS tokenizer;
- discard whitespace and comments;
- emit a dedicated SCRIPT stream;
- import an `LJS_MINI` dictionary inside that stream;
- encode keywords, operators, and punctuation as tokens;
- encode user identifiers and literals as inline values;
- dump script tokens in a readable form;
- decode to canonical script text.

Current fixture:

- `examples/script-basic`.

Out of scope:

- execution;
- DOM access;
- events;
- functions;
- arrays and objects;
- bytecode.

This scope describes Slice 1 at the time it was implemented. Later slices add
execution, functions, and broader runtime behavior.

## Slice 2: Validation

Status: implemented for the current first-slice grammar.

Scope:

- reject unknown characters;
- reject unterminated strings and comments;
- validate balanced `()`, `{}`, and statement separators;
- keep error messages source-positioned enough for fixtures and tooling.

Implemented scope:

- lexical failures: unknown characters, unterminated strings, unterminated block
  comments;
- statement shape for `let`, assignment, `while`, `if` / `else`, and
  namespaced host calls;
- single-statement `if`, `else`, and `while` bodies are accepted without
  braces;
- precedence-aware expression validation through the shared expression AST
  parser;
- validation of decoded binary SCRIPT token streams before canonical text is
  reconstructed.

Still planned:

- source-positioned errors for token-level structural failures;
- richer semantic validation as runtime grows.

This is still token-stream validation, not full semantic analysis.

Current negative fixtures live in `lhtc checkvalidation`.

## Slice 3: Tiny Interpreter

Status: implemented as a first standalone CLI/runtime slice.

Scope:

- variables with `let`;
- assignment;
- integer/number arithmetic;
- comparisons;
- `if` / `else`;
- `while`;
- host calls through registered object-method bindings;
- first host object handles for narrow capability objects.

The first interpreter must not require DOM integration. In CLI tools,
`cli-debug` host bindings for `Debug.log()` and `Browser.alert()` can write to
a deterministic output buffer.

Implemented scope:

- `LhtScriptRuntime.pas` originally executed the validated token stream
  directly; Slice 6 now routes validation and runtime through the statement AST;
- `lhtc runscript <file.lht>` executes all document `<script>` sections in
  source order;
- `examples/script-basic/runtime.dump` is checked by `lhtc checkall`;
- direct runtime checks cover arithmetic precedence, `if` / `else`, string
  concatenation, unknown variables, and duplicate `let` declarations;
- runtime expression evaluation consumes the same expression AST parser as
  validation;
- `Debug` and `Browser` are registered by the `cli-debug` runtime profile, not
  runtime builtins;
- host bindings now dispatch through handler kinds instead of name-specific
  runtime branches;
- member calls are expression nodes, so `Canvas.context()` can return a host
  object handle and `ctx.fillRect(...)` can dispatch through that handle;
- `lcCanvasBasic` enables a first headless canvas drawing sink with `clear`,
  `fillRect`, and `strokeRect`;
- `lcDomVisual` enables `Document.getElement(id)` and visual property writes
  for `color`, `background`, `border`, and `borderWidth`;
- when a runtime profile carries a `DomRoot`, visual property writes mutate
  real mini-DOM `TNode` attributes;
- visual property writes reuse mini-attribute value validation before mutating
  the node.
- `lhtc render` and `lhtc rendergdi` execute document scripts before painting,
  producing a settled post-script snapshot for CLI use.

Known limits:

- this slice was originally written before function call scopes; Slice 5 adds
  local function scopes on top;
- the original token-range statement scanner was removed by Slice 6;
- no general DOM bridge beyond the current visual property handle.

## Slice 4: Structural Script Blocks

Status: implemented for first-slice block bodies.

Scope:

- keep source `{}` in the parser/runtime token model;
- encode script block braces as generic stream `START` / `END` in the binary
  SCRIPT stream;
- decode SCRIPT `START` / `END` back to `{}` tokens before validation and
  canonical text reconstruction;
- dump script blocks as `LJS START` / `LJS END`.

Implemented scope:

- `while` and `if` / `else` bodies now use `TOK_START` / `TOK_END` in the
  binary SCRIPT stream;
- the final script-stream terminator remains `TOK_END` at block depth zero;
- no new LJS dictionary entries were added for block delimiters;
- `examples/script-basic` fixtures cover the structural form.

Still preferred direction:

- keep `()` for expression grouping and calls;
- represent future `function` bodies with the same generic `START` / `END`;
- avoid adding specialized `block:start`, `params:start`, `expr:start`, and
  similar tokens unless examples show they reduce real ambiguity or runtime
  complexity enough to justify the extra vocabulary.

Example target shape:

```text
kw:function identifier:x identifier:a START kw:return identifier:a END
```

Design rationale:

- use `START` / `END` for bodies and other structural regions that can be
  skipped as a whole by a stream parser;
- keep expression grouping, call argument lists, and function parameter lists as
  ordinary punctuation because they carry local expression/list syntax rather
  than a statement-body region;
- this keeps `START` / `END` meaningful as generic structural block markers and
  lets canonical decoding map them back to `{` / `}` without extra
  discriminators.

## Slice 5: First Functions

Status: implemented as a compact runtime/validation slice.

Scope:

- parse and encode `function name(param1, param2) { ... }`;
- parse and validate `return expression;` inside function bodies;
- allow user function calls as expression nodes;
- execute functions with local call scopes and access to outer/global variables;
- return `null` when a function body finishes without `return`;
- bind missing arguments as `null`;
- evaluate extra arguments but leave them unavailable inside the function.

Implemented scope:

- function keywords are LJS dictionary tokens;
- source block braces still compile to binary SCRIPT `START` / `END`;
- validation rejects `return` outside function bodies;
- `examples/script-basic` covers a two-argument function call;
- direct runtime checks cover call results, local scope behavior, missing
  arguments, and extra arguments.

Known limits:

- no function declarations as values;
- no closures;
- no `arguments` object yet;
- runtime stack slot accounting is now handled by Slice 7;
- namespaced host calls are now required for host APIs.

Accepted follow-up direction:

- use a runtime stack slot limit instead of a plain call-depth limit; see
  Runtime Limits and Safety below for the concrete sandbox slice.

Call depth can remain a diagnostic counter, but stack slots are the primary
resource guard.

## Technical Debt Before Runtime Limits

Status: mostly handled for the first AST runtime slice.

The current implementation has several intentional shortcuts that should be
handled before scripts become a browser-facing runtime surface. See
`ljs-notes.md` for the fuller working notes.

Handled in the first AST slice:

- build a single full AST for statements and expressions, then interpret AST
  nodes instead of rescanning token ranges in the runtime;
- remove the duplicated grammar knowledge between validation and runtime token
  scanning;
- fix the current `if` / `else` runtime path so the condition is evaluated only
  once;

Remaining priority items:

- eventually replace string-prefixed token names such as `kw:`, `op:`,
  `punct:`, and literal markers with typed token enums where it still matters
  after the AST refactor;
- improve source-positioned errors for token-level structural failures.

Deferred deliberately:

- `SetLength(..., N + 1)` growth style;
- exception-based `return`;
- linear variable/function lookup before AST and lexical-addressing work.

Host API naming:

- `Debug.log(value)` and `Browser.alert(value)` are the preferred host-call
  shape;
- this leaves `Math.log(value)` available for logarithms;
- concrete host objects are registered by the active runtime profile rather
  than hard-coded into the interpreter;
- the profile also carries the reference runtime limits;
- host bindings are gated by profile capabilities, so a profile can expose one
  binding without exposing every known host object.
- host method arity belongs to the handler, not the parser; this keeps
  one-argument `Debug.log(value)` compatible with multi-argument canvas calls.
- the first property-assignment support is intentionally visual-only; `text`
  mutation is deferred until text-run and reflow behavior is pinned down.
- first-slice member assignment requires `localVariable.property = expr`;
  chained assignment targets are deferred until the expression grammar needs
  them.

## Slice 6: Script AST and Node Interpreter

Status: implemented as the first statement-AST runtime slice.

Scope:

- parse the validated token stream into a full script AST: declarations,
  statements, bodies, and expressions;
- make validation and runtime consume the same AST shape rather than maintaining
  parallel statement-boundary logic;
- execute functions, `if` / `else`, and `while` by walking child nodes, not by
  repeated `FindBodyEnd`, `FindMatching`, or expression-range reparsing;
- preserve the current binary token stream format while changing the internal
  runtime representation;
- keep lexical addressing as a possible follow-up once names and scopes are
  represented by AST nodes.

Implemented scope:

- `LhtScript.pas` exposes `ParseLjsProgram`, a statement AST whose expression
  fields reuse the existing expression AST parser;
- `ValidateLjsTokens` validates by building the program AST;
- `LhtScriptRuntime.pas` collects function declarations from AST nodes and
  executes statements through `ExecNode` / `ExecList`;
- the old runtime statement-boundary scanner was removed from the runtime path;
- current script fixtures and direct runtime checks still pass through
  `lhtc checkall`.

Out of scope for this slice:

- bytecode;
- DOM/event integration;
- typed-token enum migration unless it naturally falls out of the AST work;
- stack slot accounting.

## Slice 7: Runtime Limits and Safety

Status: first runtime stack-slot slice implemented.

Scope:

- enforce the existing runtime step limit as part of the documented sandbox
  contract;
- add runtime stack slot accounting with target `maxStackSlots = 1000`;
- charge stack slots for parameters, local variables, and per-call frame
  overhead;
- release stack slots when a function returns;
- keep `if` / `while` from adding stack frames by themselves;
- decide whether host calls consume any stack budget once richer registered
  host APIs exist.

Implemented scope:

- `LhtScriptRuntime.pas` keeps the existing runtime step limit at `10000`;
- `maxStackSlots = 1000` is enforced by the runtime;
- step, stack-slot, and output-record limits are stored in
  `TLjsRuntimeProfile`;
- `OutputRecordLimit = 1000` is enforced for host output records;
- `StringLengthLimit = 255` is enforced for string literals and concatenation
  results;
- string values are stored as ordinary strings; `StringLengthLimit` is the
  runtime policy limit rather than a `ShortString` storage ceiling;
- `ExpressionDepthLimit = 256` guards deeply nested expression AST evaluation;
- `TokenCountLimit = 4096` is enforced before AST construction;
- `CliDebugLjsRuntimeProfile` includes the CLI host bindings, while
  `IsolatedLjsRuntimeProfile` exposes no host objects;
- `CliPageLjsRuntimeProfile` adds document visual capability and a `DomRoot`
  for document-script execution in `runscript`, `render`, and `rendergdi`;
- host bindings carry a handler kind; implemented handlers append output
  records for CLI tests, create a drawing-only canvas context handle, or create
  an element handle for visual property writes;
- profile capabilities gate which host bindings are registered;
- every scope charges one frame-overhead slot;
- every `let` variable and function parameter binding charges one slot;
- function scope slots are released when the function returns or unwinds;
- `if` / `while` bodies do not allocate new stack frames;
- direct runtime checks include a recursive stack-limit failure case.

Still planned:

- decide whether host calls consume any stack budget once richer host APIs
  exist.
- add an explicit `HostObjectLimit` before raising `StepLimit` or introducing
  long-lived host handles;
- dispatch host-object methods by `TLjsHostObjectKind` before adding the first
  element method;
- decide whether nested `function` declarations should be specified as global
  hoisting or rejected in nested statement positions.

Out of scope for this slice:

- DOM/event integration;
- async or timers;
- exact heap accounting for future pooled strings;
- exposing `arguments`.

## Later Work

- consolidate `ljs-host-api-design.md` decisions back into `lht-spec-part3.md`
  and `lht-spec-part4.md` after resolving the listed spec conflicts;
- bytecode or compact IR;
- richer value types;
- script resource references;
- event handlers;
- DOM bridge through explicit host APIs;
- broader runtime limits and security policy;
- source maps or debug metadata if needed;
- grammar freeze policy: define when LJS syntax becomes compatibility-stable
  versus still freely changeable between early slices.

Specification anchor:

- align the script-language roadmap with the script section of the LHT
  specification when that section is updated; roadmap items here describe the
  reference implementation path, while the specification should define the
  stable language/profile contract.

## Documentation Boundary

Keep internal script-language work here and in the other `ljs-*` documents.

LHT documents should only mention script integration points:

- where `<script>` can appear;
- how SCRIPT streams are represented in the binary format;
- how event attributes reference script code later;
- which feature/profile enables scripts.
