# script-basic

Focused fixture for the first LJS token-stream slice:

- `<script>` as a document-level section;
- separate SCRIPT stream with `LJS_MINI` import;
- whitespace and comments discarded by tokenization;
- `let`, `while`, `if` / `else`, single-statement `if` / `while`, first-slice
  functions with `return`, local shadowing, arithmetic/comparison/equality
  operators, parenthesized expressions, and default CLI host bindings
  `Debug.log()` / `Browser.alert()`;
- canonical script text after binary decode;
- standalone runtime execution through `runtime.dump`.

`invalid-scripts.lht` is a readable companion document with invalid LJS snippets
stored inside LHT comments and visible summaries of the expected validation
errors.
