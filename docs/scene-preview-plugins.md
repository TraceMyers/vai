# Scene preview plugins

Vai previews built-in glTF/GLB, FBX/OBJ, USD/USDA/USDC/USDZ scenes and DDS, OpenEXR, TIFF, and DNG textures through the same native-provider interface available to plugins. PNG, JPEG, BMP, TGA, PSD, GIF, Radiance HDR, PIC, PPM, and PGM use Vai's built-in raster decoder. A scene plugin receives a file path on a worker thread and returns an unindexed, world-space triangle list. A raster plugin returns RGBA8 pixels. Vai owns all OpenGL state and renders scenes as unlit, automatically framed geometry.

## Installation

Build a 64-bit Windows DLL and place it in:

```text
%APPDATA%\Vai\plugins\preview
```

Restart Vai. User plugins load before Vai's built-in provider, so a plugin may override a built-in extension. Keep any dependent DLLs next to your plugin DLL.

## ABI

Include [vai_scene_preview_api.h](../native_preview/vai_scene_preview_api.h) and export exactly this function:

```cpp
VAI_SCENE_PREVIEW_EXPORT const VaiScenePreviewProvider*
VAI_SCENE_PREVIEW_CALL Vai_Get_Scene_Preview_Provider(uint32_t host_abi_version);
```

Return `nullptr` unless `host_abi_version == VAI_SCENE_PREVIEW_ABI_VERSION`. Fill out `abi_version`, `struct_size`, a descriptive `provider_name`, and a semicolon-separated lowercase extension list such as `"vox;my_scene"`. That list is what lets the file explorer recognize a new format.

`can_preview()` should cheaply decide whether the path belongs to the provider. `load_scene()` may read and decode the file; it writes a short diagnostic to the supplied error buffer on failure. It must return an unindexed `VaiScenePreviewVertex` triangle list in world space, plus finite world-space bounds. Keep the memory valid until Vai calls `release_scene()`—the provider must free it there, not Vai.

To add an image format, implement `load_image()` and `release_image()` instead (or alongside the scene callbacks). Return tightly packed straight-alpha RGBA8 pixels in `VaiImagePreview`; set `row_stride` to at least `width * 4`. Vai copies the result before calling `release_image()`. An image-only provider may leave the scene callbacks null, and a scene-only provider may leave the image callbacks null.

Providers are called from Vai's background worker. Do not create windows, access OpenGL, or touch Vai-owned state. The built-in provider at [vai_builtin_scene_preview.cpp](../native_preview/vai_builtin_scene_preview.cpp) is a complete reference implementation.

## Scope of the initial renderer

The host currently shows static geometry with vertex/base colors in an unlit, depth-tested view. Textures, animation controls, lights, skeletal posing, camera selection, and format-specific metadata are intentionally outside this first ABI; a provider should bake any required static transforms and colors into its returned vertices. The ABI is versioned so richer scene data can be added without silently breaking existing plugins.
