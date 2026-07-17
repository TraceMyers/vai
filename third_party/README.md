# Vendored preview libraries

Vai builds its out-of-box scene preview provider from these pinned sources:

- `cgltf` — glTF and GLB parser, MIT, revision `85cd62382dfea638278962690cf515023f33ed00`.
- `ufbx` — FBX and OBJ parser, MIT or public domain, `v0.23.0` (`fcc5d6ba444cfd3eb80677dba5e37e493941abe5`).
- `tinyusdz` — USD, USDA, USDC, and USDZ parser/converter, Apache-2.0, release revision `4b522a6c632a49edf44ade8813c85ba80c74e24b`.

Their source license files remain alongside each library.  They are linked only into the preview-provider DLL; Vai's editor core talks to that DLL through `native_preview/vai_scene_preview_api.h`.
