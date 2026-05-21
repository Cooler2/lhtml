# LJS Mini Syntax

This document defines the first small source syntax accepted by the LJS
tokenizer. It is intentionally smaller than JavaScript.

## First Slice

Supported statements:

```js
let name = expression;
name = expression;
if (expression) {
  statement;
} else {
  statement;
}
if (expression) statement;
if (expression) statement; else statement;
while (expression) {
  statement;
}
while (expression) statement;
function name(param1, param2) {
  statement;
  return expression;
}
Debug.log(expression);
Browser.alert(expression);
let ctx = Canvas.context();
ctx.clear();
ctx.fillRect(x, y, w, h);
ctx.strokeRect(x, y, w, h);
let el = Document.getElement("warning");
el.color = "#C00000";
el.background = "#FFFFCC";
el.border = "#336699";
el.borderWidth = 1;
```

Supported expressions:

```js
number
string
identifier
true
false
null
(expression)
identifier(expression)
expression.identifier(expression)
expression + expression
expression - expression
expression * expression
expression / expression
expression == expression
expression != expression
expression < expression
expression > expression
expression <= expression
expression >= expression
```

Validation uses the same precedence-aware expression parser as the standalone
runtime.

Supported host-call syntax:

```js
Debug.log(value);
Browser.alert(value);
Canvas.context();
ctx.clear();
ctx.fillRect(x, y, w, h);
ctx.strokeRect(x, y, w, h);
Document.getElement(id);
el.color = value;
el.background = value;
el.border = value;
el.borderWidth = value;
```

In the first CLI slice, debug names are `cli-debug` host bindings. Canvas is
available only when the active profile enables `lcCanvasBasic`; visual element
property writes are available only when the active profile enables
`lcDomVisual`. These names are not language builtins: the active runtime
profile registers the root host object and method names it wants to expose,
and host object handles dispatch their own methods and property writes. Host
method arity is checked by the selected handler.

The namespaced shape keeps `Math.log()` available for logarithms and prepares
the grammar for later host object calls.

Current profiles:

- `isolated`: no host object calls are available;
- `cli-debug`: `Debug.log(value)` and `Browser.alert(value)` are available as
  output-record handlers.
- profiles that enable `lcCanvasBasic`: `Canvas.context()` returns a
  drawing-only host object handle with `clear`, `fillRect`, and `strokeRect`.
- profiles that enable `lcDomVisual`: `Document.getElement(id)` returns an
  element handle whose first writable properties are `color`, `background`,
  `border`, and `borderWidth`.

The first visual property slice deliberately excludes `text`; text mutation is
deferred until text-run and reflow behavior is explicit.

Function call arity is permissive:

- if fewer arguments are passed, missing parameters are `null`;
- if more arguments are passed, extra arguments are evaluated but unavailable
  inside the function;
- a future `arguments` value may expose the full argument list later.

Runtime limits:

- recursive/user function execution is guarded by stack slots, not raw call
  depth;
- `maxStackSlots = 1000` in the current reference runtime;
- `maxOutputRecords = 1000` in the current reference runtime;
- `maxStringLength = 255` in the current reference runtime;
- `maxTokens = 4096` in the current reference runtime;
- stack slots account for parameters, local variables, and a small per-call
  frame overhead;
- step, stack-slot, output-record, string-length, and token-count limits are
  runtime profile settings.

## Whitespace And Comments

Whitespace is only a separator in source text. It is not encoded.

Comments are discarded by the tokenizer and are not decoded back.

Comment forms in the first slice:

```js
// line comment
/* block comment */
```

## Literals

Numbers:

- decimal integer or decimal number;
- exact numeric range can be implementation-defined in the first slice.
- the first implementation stores number literals as canonical source strings.

Strings:

- quoted with `"`;
- basic escapes: `\n`, `\r`, `\t`, `\\`, `\"`, `\'`;
- unterminated strings are validation errors.
- runtime string values are limited by the active profile; the current
  reference limit is `255`.

Identifiers:

- user-defined names;
- cannot collide with reserved keywords;
- can be encoded inline first, with local dictionary optimization later.

## Deliberately Excluded

- `for`;
- arrays;
- objects;
- general property access;
- DOM access;
- event handlers;
- modules/imports;
- async/network APIs.

These exclusions keep the first slice suitable for tokenizer, binary stream,
validation, and tiny interpreter work.
