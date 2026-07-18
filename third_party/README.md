# Vendored preview libraries

Vai builds its out-of-box scene preview provider from these pinned sources:

- `cgltf` — glTF and GLB parser, MIT, revision `85cd62382dfea638278962690cf515023f33ed00`.
- `ufbx` — FBX and OBJ parser, MIT or public domain, `v0.23.0` (`fcc5d6ba444cfd3eb80677dba5e37e493941abe5`).
- `tinyusdz` — USD, USDA, USDC, and USDZ parser/converter, Apache-2.0, release revision `4b522a6c632a49edf44ade8813c85ba80c74e24b`.

Their source license files remain alongside each library.  They are linked only into the preview-provider DLL; Vai's editor core talks to that DLL through `native_preview/vai_scene_preview_api.h`.

# Vendored language / highlighting libraries

Vai uses tree-sitter for syntax highlighting (only):

- `tree-sitter` — incremental parsing runtime, MIT, revision `b40f342067a89cd6331bf4c27407588320f3c263` (v0.22.6). Trimmed to `lib/` (runtime + `LICENSE`). Built as a static library by `native_language/CMakeLists.txt` and statically linked into the editor. Jai bindings live in `src/tree_sitter.jai`.
- `tree-sitter-jai` — authored Jai grammar. `grammar.js` is the source of truth; `src/parser.c` is the committed generated parser (regenerate with `npx tree-sitter-cli@0.22.6 generate` from that directory when `grammar.js` changes — the tree-sitter CLI is only needed at grammar-authoring time). `queries/highlights.scm` documents the capture set. Compiled into `jai-grammar.lib` and linked into the editor for the M1 highlighting spike; it moves behind a per-language provider DLL in M2.

Go-to-definition, find-references, and rename do NOT use tree-sitter; they come from a Jai-compiler-backed semantic provider (see the implementation plan).
