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

// Optional lit-scene extension for ABI v1 providers. The original triangle/color
// interface remains available so older providers continue to load.
typedef struct VaiLitScenePreviewVertex {
    float position[3];
    float normal[3];
    // xyz is the tangent direction; w is the bitangent handedness.
    float tangent[4];
    float color[4];
    float uv[2];
} VaiLitScenePreviewVertex;

enum {
    VAI_SCENE_MATERIAL_BASE_COLOR_TEXTURE = 1u << 0,
    VAI_SCENE_MATERIAL_NORMAL_TEXTURE = 1u << 1,
    VAI_SCENE_MATERIAL_WRAP_U_REPEAT = 1u << 2,
    VAI_SCENE_MATERIAL_WRAP_V_REPEAT = 1u << 3,
};

typedef struct VaiLitScenePreviewMaterial {
    VaiImagePreview base_color_texture;
    VaiImagePreview normal_texture;
    uint32_t flags;
    float normal_scale;
} VaiLitScenePreviewMaterial;

typedef struct VaiLitScenePreviewDrawRange {
    uint32_t first_vertex;
    uint32_t vertex_count;
    uint32_t material_index;
} VaiLitScenePreviewDrawRange;

typedef struct VaiLitScenePreviewMesh {
    const VaiLitScenePreviewVertex* vertices;
    uint32_t vertex_count;
    const VaiLitScenePreviewMaterial* materials;
    uint32_t material_count;
    const VaiLitScenePreviewDrawRange* draw_ranges;
    uint32_t draw_range_count;
    float bounds_min[3];
    float bounds_max[3];
} VaiLitScenePreviewMesh;

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
typedef int (VAI_SCENE_PREVIEW_CALL *VaiLitScenePreviewLoadFn)(
    const char* utf8_path,
    VaiLitScenePreviewMesh* out_mesh,
    char* error_message,
    uint32_t error_message_capacity);
typedef void (VAI_SCENE_PREVIEW_CALL *VaiLitScenePreviewReleaseFn)(VaiLitScenePreviewMesh* mesh);

typedef struct VaiScenePreviewProvider {
    uint32_t abi_version;
    uint32_t struct_size;
    const char* provider_name;
    // Legacy combined list. Keep this populated for hosts/providers that only
    // understand the original ABI-v1 struct.
    const char* extensions;
    VaiScenePreviewCanPreviewFn can_preview;
    VaiScenePreviewLoadFn load_scene;
    VaiScenePreviewReleaseFn release_scene;
    VaiImagePreviewLoadFn load_image;
    VaiImagePreviewReleaseFn release_image;
    // Optional ABI-v1 tail fields. Lists are lowercase, semicolon-separated,
    // and omit dots. Hosts must check struct_size before reading them.
    const char* scene_extensions;
    const char* image_extensions;
    // Optional ABI-v1 lit-scene tail. Hosts must check struct_size before
    // reading these fields and fall back to load_scene when absent.
    VaiLitScenePreviewLoadFn load_lit_scene;
    VaiLitScenePreviewReleaseFn release_lit_scene;
} VaiScenePreviewProvider;

typedef const VaiScenePreviewProvider* (VAI_SCENE_PREVIEW_CALL *VaiScenePreviewGetProviderFn)(uint32_t host_abi_version);

// The only required export for a provider DLL.
VAI_SCENE_PREVIEW_EXPORT const VaiScenePreviewProvider* VAI_SCENE_PREVIEW_CALL
Vai_Get_Scene_Preview_Provider(uint32_t host_abi_version);
