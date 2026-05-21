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
- namespaced host calls through registered host objects.

## Host Functions

Current CLI host bindings:

```text
Debug.log(value)
Browser.alert(value)
```

The runtime does not build these objects in directly. It only executes the
`Object.method(value)` AST shape and resolves it through the active runtime
profile. The default CLI profile registers `Debug.log` and `Browser.alert`;
the isolated profile registers no host objects.

For command-line tools, the default host calls append deterministic records to
a runtime output buffer.

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

CLI integration:

```text
lhtc runscript examples\script-basic\index.lht
```

The command executes all `<script>` sections in document order and writes the
deterministic host-function output.

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
- runtime string length limit: `255` bytes/chars in the current reference
  implementation;
- runtime token count limit: `4096` tokens;

The preferred recursion/memory guard is a stack-size limit, not a plain call
depth limit. A slot is a runtime accounting unit for parameter bindings, local
`let` variables, and a small per-call frame overhead. This catches both deep
recursion with tiny frames and shallower recursion with many locals.

Runtime limits are profile data in the reference runtime. The default CLI
profile and isolated profile currently share the same limits; they differ in
host bindings.

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
- the current default is `255`, matching the temporary `ShortString` payload in
  `TLjsValue`;
- exceeding the limit raises `Script runtime string length limit exceeded`.

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
