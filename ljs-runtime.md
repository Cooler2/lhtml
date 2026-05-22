# LJS Runtime

This document tracks the standalone LJS runtime slice. The current
implementation parses the validated token stream into a statement/expression
AST and walks that tree; it is not a bytecode VM yet.

## First Runtime Goal

Run small standalone algorithms without DOM or browser integration.

The initial runtime supports:

- variables declared with `let`;
- assignment;
- numbers, strings, booleans, and null;
- arithmetic;
- comparisons;
- `if` / `else`;
- `while`;
- first-slice user functions with parameters and `return`;
- namespaced root host calls through registered host objects;
- first host object handles for narrow capability objects.

## Host Functions

Current CLI host bindings:

```text
Debug.log(value)
Browser.alert(value)
Canvas.context()
ctx.clear()
ctx.fillRect(x, y, w, h)
ctx.strokeRect(x, y, w, h)
Document.getElement(id)
el.color = value
el.background = value
el.border = value
el.borderWidth = value
```

The runtime does not build these objects in directly. It only executes the
`object.method(args...)` AST shape and resolves it through the active runtime
profile. The `cli-debug` profile registers `Debug.log` and `Browser.alert`;
the `isolated` profile registers no host objects.

Host bindings are not interpreted by name after lookup. Each binding carries a
handler kind plus handler-specific configuration. The implemented handler
kinds are:

- `output-record`, used by command-line tools to append deterministic records
  to a runtime output buffer;
- `canvas-context`, which returns a drawing-only host object handle when the
  `lcCanvasBasic` capability is enabled;
- `element-get`, which returns an element host object handle when the
  `lcDomVisual` capability is enabled.

Host method arity is checked by the selected handler. `Debug.log()` and
`Browser.alert()` still accept one argument; canvas context methods use their
own arity.

Example output:

```text
LOG: 1
LOG: 2
LOG: 3
ALERT: done
```

This lets tests verify execution without any DOM bridge.

The namespaced form leaves `Math.log(value)` free for logarithms and keeps host
objects as runtime-profile authority rather than language builtins.

Implemented capability profiles:

- `isolated`: no host capabilities and no host objects;
- `cli-debug`: debug-output and browser-alert capabilities, with
  `Debug.log()` and `Browser.alert()` bound to output-record handlers.
- test/browser profiles may enable `lcCanvasBasic`, registering
  `Canvas.context()` and returning a drawing-only context handle.
- test/browser profiles may enable `lcDomVisual`, registering
  `Document.getElement(id)` and allowing visual property writes on element
  handles. When the profile carries a `DomRoot`, these writes mutate the
  matching `TNode` attributes.

A host binding is registered only when its capability is enabled by the active
profile. This lets an embedding expose `Debug.log()` without also exposing
`Browser.alert()`.

CLI integration:

```text
lhtc runscript examples\script-basic\index.lht
lhtc render examples\script-visual-dom\index.lht tmp\script-visual-dom.bmp
```

`runscript` executes all `<script>` sections in document order and writes the
deterministic host-function output.

Document script execution uses the `cli-page` runtime profile in the reference
CLI. It starts from the CLI debug host set, grants `lcDomVisual`, and attaches
the parsed mini-DOM root as `DomRoot`.

`render` and `rendergdi` execute document scripts before rendering, so their
BMP output is a settled post-script snapshot. A browser may still paint an
initial frame before later post-body scripts run; that is an interactive
browser lifecycle concern rather than the CLI renderer contract.

Runtime output fixtures use `LF` line endings so the buffer is stable across
platforms.

## AST Evaluation

Validation and runtime evaluation share the same AST path. `ParseLjsProgram`
builds statement nodes for declarations, assignments, calls, functions,
returns, `if` / `else`, and `while`. Expression fields reuse the expression AST
parser.

Runtime executes statement nodes through the AST instead of rescanning token
ranges for statement boundaries. This keeps validation and execution aligned
while preserving the current binary SCRIPT token stream.

Current expression precedence:

```text
* /
+ -
< > <= >=
== !=
```

Parenthesized expressions override precedence.

User function calls are expression nodes, so values can be assigned or passed
through expressions such as `let y = inc(4);`.

Member calls are expression nodes too. Root host calls such as
`Canvas.context()` are resolved through profile bindings; calls on host object
handles such as `ctx.fillRect(1, 2, 30, 40)` dispatch through the handle kind.

Member assignment is currently a narrow statement form for visual DOM-style
properties on element handles. The left-hand side must be a local variable plus
a single property name; chained forms such as
`Document.getElement("warning").color = "#C00000"` are intentionally outside
this first slice.

```js
let el = Document.getElement("warning");
el.color = "#C00000";
el.background = "#FFFFCC";
el.border = "#336699";
el.borderWidth = 1;
```

This intentionally excludes `text` for now; changing text content has more
layout and text-run consequences than color and border mutation. The runtime
updates the real mini-DOM node attributes when a document root is attached, and
also records deterministic `DOM:` output lines for CLI regression tests.

Function arity is intentionally permissive:

- missing arguments bind their parameters to `null`;
- extra arguments are evaluated but are not bound to named parameters;
- there is no `arguments` object in the first function slice.

The `+` operator concatenates when either operand is a string. Other arithmetic
operators require numbers. Comparisons currently require numbers.

## Error Model

Current runtime errors include:

- unknown variable;
- duplicate variable declaration in the same scope;
- unknown function;
- unknown or unregistered host call;
- invalid operator for value type;
- loop/runtime instruction limit exceeded.

Division currently follows the host floating-point behavior.

## Runtime Limits

Runtime limits are part of the scripting security model and should be explicit
before scripts are connected to document events.

Current and likely limits:

- runtime step limit: `10000`;
- runtime stack slot limit: `1000` slots;
- runtime output record limit: `1000` records;
- runtime string length limit: `255` bytes/chars by default;
- runtime expression depth limit: `256` nested AST eval frames;
- runtime host object limit: `1000` handles;
- runtime token count limit: `4096` tokens;

The preferred recursion/memory guard is a stack-size limit, not a plain call
depth limit. A slot is a runtime accounting unit for parameter bindings, local
`let` variables, and a small per-call frame overhead. This catches both deep
recursion with tiny frames and shallower recursion with many locals.

Runtime limits are profile data in the reference runtime. The `cli-debug` and
`isolated` profiles currently share the same limits; they differ in enabled
capabilities and host bindings.

Host output accounting:

- every registered host call that appends to the runtime output buffer charges
  one output record;
- exceeding `OutputRecordLimit` raises
  `Script runtime output record limit exceeded`;
- this is intentionally separate from step counting, because a script can
  spend many steps without writing output or write output inside a loop.

String length accounting:

- every runtime string value is checked against `StringLengthLimit`;
- this applies to string literals and strings created by concatenation;
- runtime string values use ordinary strings in the reference runtime; the
  default limit remains a profile policy, not a storage-size side effect;
- exceeding the limit raises `Script runtime string length limit exceeded`.

Expression depth accounting:

- every recursive expression-node evaluation is checked against
  `ExpressionDepthLimit`;
- this catches deeply nested expression ASTs separately from call-stack slot
  accounting;
- exceeding the limit raises `Script runtime expression depth limit exceeded`.

Host object accounting:

- every host object handle created by a root host API counts against
  `HostObjectLimit`;
- handles are currently kept for the duration of the script run;
- exceeding the limit raises `Script runtime host object limit exceeded`.

Token count accounting:

- the runtime checks `TokenCountLimit` before building the AST;
- this rejects oversized SCRIPT streams before statement parsing or execution;
- exceeding the limit raises `Script runtime token count limit exceeded`.

Current stack-slot accounting:

- global execution starts with one frame-overhead slot;
- each function call adds one frame-overhead slot;
- each function parameter binding and `let` variable adds one slot;
- slots are released when a function scope is popped;
- `if` / `while` bodies do not allocate stack frames by themselves;
- registered host calls do not currently consume stack budget beyond evaluating their
  argument expression.

Call depth may still be useful as a diagnostic counter, but it should not be
the primary sandbox limit.

## Later DOM Bridge

DOM access should be added through explicit host APIs, not through implicit
global browser objects.

Potential later APIs:

```text
get(id)
setText(id, value)
setValue(id, value)
addClass(id, className)
removeClass(id, className)
```

These APIs are intentionally not part of the first runtime slice.
