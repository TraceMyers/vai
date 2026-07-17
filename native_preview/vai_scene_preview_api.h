#pragma once

// Stable C ABI between Vai and scene preview providers.  Providers must not
// use Vai's renderer or allocate memory that the host will free directly.

#include <stdint.h>

#define VAI_SCENE_PREVIEW_ABI_VERSION 1u

#if defined(_WIN32)
#define VAI_SCENE_PREVIEW_CALL __cdecl
#define VAI_SCENE_PREVIEW_EXPORT extern "C" __declspec(dllexport)
#else
#define VAI_SCENE_PREVIEW_CALL
#define VAI_SCENE_PREVIEW_EXPORT extern "C"
#endif

typedef struct VaiScenePreviewVertex {
    float position[3];
    float color[4];
} VaiScenePreviewVertex;

// Geometry is supplied as an unindexed triangle list in world space.  This
// keeps the host renderer simple and makes providers independent of OpenGL.
typedef struct VaiScenePreviewMesh {
    const VaiScenePreviewVertex* vertices;
    uint32_t vertex_count;
    float bounds_min[3];
    float bounds_max[3];
} VaiScenePreviewMesh;

// Raster previews are always tightly packed, straight-alpha RGBA8 pixels.
typedef struct VaiImagePreview {
    const uint8_t* pixels;
    uint32_t width;
    uint32_t height;
    uint32_t row_stride;
} VaiImagePreview;

typedef int (VAI_SCENE_PREVIEW_CALL *VaiScenePreviewCanPreviewFn)(const char* utf8_path);
typedef int (VAI_SCENE_PREVIEW_CALL *VaiScenePreviewLoadFn)(
    const char* utf8_path,
    VaiScenePreviewMesh* out_mesh,
    char* error_message,
    uint32_t error_message_capacity);
typedef void (VAI_SCENE_PREVIEW_CALL *VaiScenePreviewReleaseFn)(VaiScenePreviewMesh* mesh);
typedef int (VAI_SCENE_PREVIEW_CALL *VaiImagePreviewLoadFn)(
    const char* utf8_path,
    VaiImagePreview* out_image,
    char* error_message,
    uint32_t error_message_capacity);
typedef void (VAI_SCENE_PREVIEW_CALL *VaiImagePreviewReleaseFn)(VaiImagePreview* image);

typedef struct VaiScenePreviewProvider {
    uint32_t abi_version;
    uint32_t struct_size;
    const char* provider_name;
    // Lowercase extension list, separated with semicolons and without dots.
    const char* extensions;
    VaiScenePreviewCanPreviewFn can_preview;
    VaiScenePreviewLoadFn load_scene;
    VaiScenePreviewReleaseFn release_scene;
    VaiImagePreviewLoadFn load_image;
    VaiImagePreviewReleaseFn release_image;
} VaiScenePreviewProvider;

typedef const VaiScenePreviewProvider* (VAI_SCENE_PREVIEW_CALL *VaiScenePreviewGetProviderFn)(uint32_t host_abi_version);

// The only required export for a provider DLL.
VAI_SCENE_PREVIEW_EXPORT const VaiScenePreviewProvider* VAI_SCENE_PREVIEW_CALL
Vai_Get_Scene_Preview_Provider(uint32_t host_abi_version);
