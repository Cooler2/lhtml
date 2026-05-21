# LJS Token Stream

LJS script content is encoded as a separate SCRIPT stream. The stream stores a
pre-tokenized representation of source code: more structured than raw text, but
not yet bytecode.

## Design Intent

- The client does not perform lexical analysis.
- Whitespace and comments are not encoded.
- Tokens preserve enough structure to interpret directly or compile later.
- Standard language words use dictionary tokens.
- User-defined names and literal values remain inline payloads.

## Stream Shape

Conceptual form:

```text
SCRIPT_BEGIN
  IMPORT LJS_MINI
  ...
SCRIPT_END
```

The exact document-level command that enters SCRIPT belongs to the LHT binary
integration docs. The tokens inside the stream belong to LJS.

Current mini implementation uses `CMD_SCRIPT_BEGIN` followed by an `LJS_MINI`
import and ends the script stream with `END`.

Block bodies use the generic stream markers:

- source `{` is encoded as `START`;
- source `}` is encoded as `END`;
- the script stream itself also ends with `END`, distinguished by block depth
  zero while decoding.

This keeps block structure out of the LJS dictionary while preserving canonical
source reconstruction.

## First Mini Dictionary

Keywords:

```text
let
if
else
while
function
return
true
false
null
```

Operators:

```text
=
+
-
*
/
==
!=
<
>
<=
>=
```

Punctuation:

```text
(
)
;
,
.
```

The source tokenizer still recognizes `{` and `}` so validation/runtime can
work with source-like tokens. Binary encoding compiles those two punctuation
tokens into generic `START` / `END` markers instead of LJS dictionary tokens.

Host calls use namespaced source shape:

```text
Debug.log(value);
Browser.alert(value);
```

The object name and method name are inline identifiers, and `.` is an LJS
punctuation token. The token stream records the call shape only; the runtime
embedding decides which host objects and methods are registered.

Inline token kinds:

```text
identifier
string
number
```

The first implementation encodes inline identifier, string, and number payloads
as string inline values after their literal-kind token.

## Example

Source:

```js
let x = 1;
while (x < 4) {
  Debug.log(x);
  x = x + 1;
}
Browser.alert("done");
```

Conceptual token stream:

```text
kw:let
identifier:x
op:=
number:1
punct:;
kw:while
punct:(
identifier:x
op:<
number:4
punct:)
START
identifier:Debug
punct:.
identifier:log
punct:(
identifier:x
punct:)
punct:;
identifier:x
op:=
identifier:x
op:+
number:1
punct:;
END
identifier:Browser
punct:.
identifier:alert
punct:(
string:"done"
punct:)
punct:;
```

## Canonical Decode

Decoding does not preserve original formatting or comments. It reconstructs
canonical script text from tokens.

Canonical formatting can be simple at first:

- one statement per line;
- block braces on their own structural lines or in a stable compact style;
- normalized spaces around binary operators;
- no comments.

The canonical text is a debugging and round-trip artifact. The binary token
stream is the source of truth.

## Structural Stream

The current mini implementation reuses generic stream `START` / `END` markers
for script block bodies when
their meaning is unambiguous from context, instead of adding many specialized
`xxx:start` / `xxx:end` tokens.

Example source:

```js
function x(a) {
  return a;
}
```

Possible structural stream:

```text
kw:function
identifier:x
identifier:a
START
kw:return
identifier:a
END
```

In this form:

- after `kw:function`, identifiers before `START` are the function name and
  parameters;
- `START` opens the function body;
- `END` closes the function body;
- no dedicated `params:start`, `params:end`, `block:start`, or `block:end`
tokens are needed unless later examples show real ambiguity.

Similarly, control-flow bodies can use the same generic structure:

```text
kw:while
identifier:x
op:<
number:4
START
identifier:Debug
punct:.
identifier:log
punct:(
identifier:x
punct:)
punct:;
END
```

The first implemented structural slice is more conservative: `while` / `if`
conditions still keep their source parentheses, and only source block braces are
compiled into `START` / `END`.

Parentheses should remain available for expression syntax, grouping, and calls.
They should not be required merely to mark `if`, `while`, or function bodies in
the binary stream.

This is a compactness/readability trade-off. Specialized start/end tokens can
make interpretation more direct, but they also enlarge the vocabulary and
clutter the stream. Prefer generic `START` / `END` first when context gives a
single clear interpretation.

## Open Questions

- Whether identifiers should later use local DEFINE/PIN records when repeated.
- Whether `true`, `false`, and `null` should be keyword tokens or value tokens.
- Whether script literals should reuse shared VALUE encodings where practical.
- Where generic `START` / `END` remains unambiguous, and where a future
  construct genuinely needs a specialized delimiter.
