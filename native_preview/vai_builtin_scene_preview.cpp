#define CGLTF_IMPLEMENTATION
#include "../third_party/cgltf/cgltf.h"

#include "../third_party/ufbx/ufbx.h"
#include "../third_party/tinyusdz/src/tinyusdz.hh"
#include "../third_party/tinyusdz/src/image-loader.hh"
#include "../third_party/tinyusdz/src/external/tinyexr.h"
#define STB_IMAGE_STATIC
#define STB_IMAGE_IMPLEMENTATION
#include "../third_party/tinyusdz/src/external/stb_image.h"
#include "../third_party/tinyusdz/src/tydra/render-data.hh"
#include "vai_scene_preview_api.h"

#include <algorithm>
#include <cctype>
#include <climits>
#include <cfloat>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr uint32_t kMaxPreviewVertices = 3u * 1024u * 1024u;
constexpr uint32_t kMaxPreviewMaterials = 4096u;
constexpr size_t kMaxPreviewTextureBytes = 512ull * 1024ull * 1024ull;

void SetError(char* destination, uint32_t capacity, const char* message) {
    if (!destination || capacity == 0) return;
    if (!message) message = "Unknown scene preview error.";
    std::strncpy(destination, message, capacity - 1);
    destination[capacity - 1] = '\0';
}

void SetError(char* destination, uint32_t capacity, const std::string& message) {
    SetError(destination, capacity, message.c_str());
}

std::string ExtensionOf(const char* path) {
    if (!path) return {};
    const char* dot = std::strrchr(path, '.');
    if (!dot || dot[1] == '\0') return {};
    std::string extension(dot + 1);
    std::transform(extension.begin(), extension.end(), extension.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return extension;
}

bool IsBuiltinExtension(const std::string& extension) {
    return extension == "gltf" || extension == "glb" || extension == "fbx" || extension == "obj"
        || extension == "usd" || extension == "usda" || extension == "usdc" || extension == "usdz"
        || extension == "dds" || extension == "exr" || extension == "tif" || extension == "tiff" || extension == "dng";
}

struct PreviewTexture {
    std::vector<uint8_t> pixels;
    uint32_t width = 0;
    uint32_t height = 0;
};

struct PreviewMaterial {
    PreviewTexture base_color_texture;
    PreviewTexture normal_texture;
    uint32_t flags = 0;
    float normal_scale = 1.0f;
};

struct PreviewVertex {
    VaiLitScenePreviewVertex lit = {};
    float legacy_color[4] = {};
    uint32_t material_index = 0;
};

float Dot3(const float a[3], const float b[3]) {
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
}

void Cross3(const float a[3], const float b[3], float out[3]) {
    out[0] = a[1]*b[2] - a[2]*b[1];
    out[1] = a[2]*b[0] - a[0]*b[2];
    out[2] = a[0]*b[1] - a[1]*b[0];
}

bool Normalize3(float value[3]) {
    const float length_squared = Dot3(value, value);
    if (!std::isfinite(length_squared) || length_squared <= 1.0e-12f) return false;
    const float inverse_length = 1.0f / std::sqrt(length_squared);
    value[0] *= inverse_length;
    value[1] *= inverse_length;
    value[2] *= inverse_length;
    return true;
}

struct PreviewBuild {
    std::vector<PreviewVertex> vertices;
    std::vector<PreviewMaterial> materials = { PreviewMaterial{} };
    size_t texture_bytes = 0;
    float bounds_min[3] = { FLT_MAX, FLT_MAX, FLT_MAX };
    float bounds_max[3] = { -FLT_MAX, -FLT_MAX, -FLT_MAX };

    bool Append(float x, float y, float z, const float color[4]) {
        const float position[3] = { x, y, z };
        const float normal[3] = {};
        const float tangent[4] = {};
        const float uv[2] = {};
        return AppendLit(position, normal, tangent, color, color, uv, 0);
    }

    bool AppendLit(
        const float position[3],
        const float normal[3],
        const float tangent[4],
        const float color[4],
        const float legacy_color[4],
        const float uv[2],
        uint32_t material_index
    ) {
        if (vertices.size() >= kMaxPreviewVertices) return false;
        PreviewVertex vertex = {};
        std::memcpy(vertex.lit.position, position, sizeof(vertex.lit.position));
        std::memcpy(vertex.lit.normal, normal, sizeof(vertex.lit.normal));
        std::memcpy(vertex.lit.tangent, tangent, sizeof(vertex.lit.tangent));
        std::memcpy(vertex.lit.color, color, sizeof(vertex.lit.color));
        std::memcpy(vertex.lit.uv, uv, sizeof(vertex.lit.uv));
        std::memcpy(vertex.legacy_color, legacy_color, sizeof(vertex.legacy_color));
        vertex.material_index = material_index < materials.size() ? material_index : 0;
        vertices.push_back(vertex);
        bounds_min[0] = std::min(bounds_min[0], position[0]);
        bounds_min[1] = std::min(bounds_min[1], position[1]);
        bounds_min[2] = std::min(bounds_min[2], position[2]);
        bounds_max[0] = std::max(bounds_max[0], position[0]);
        bounds_max[1] = std::max(bounds_max[1], position[1]);
        bounds_max[2] = std::max(bounds_max[2], position[2]);
        return true;
    }

    uint32_t AddMaterial(PreviewMaterial material) {
        const size_t material_texture_bytes = material.base_color_texture.pixels.size()
            + material.normal_texture.pixels.size();
        if (materials.size() >= kMaxPreviewMaterials
        || material_texture_bytes > kMaxPreviewTextureBytes - std::min(texture_bytes, kMaxPreviewTextureBytes)) {
            return 0;
        }
        texture_bytes += material_texture_bytes;
        materials.push_back(std::move(material));
        return static_cast<uint32_t>(materials.size() - 1);
    }

    void CompleteMissingFrames() {
        for (size_t triangle = 0; triangle + 2 < vertices.size(); triangle += 3) {
            PreviewVertex* corners[3] = { &vertices[triangle], &vertices[triangle + 1], &vertices[triangle + 2] };
            const float edge_a[3] = {
                corners[1]->lit.position[0] - corners[0]->lit.position[0],
                corners[1]->lit.position[1] - corners[0]->lit.position[1],
                corners[1]->lit.position[2] - corners[0]->lit.position[2],
            };
            const float edge_b[3] = {
                corners[2]->lit.position[0] - corners[0]->lit.position[0],
                corners[2]->lit.position[1] - corners[0]->lit.position[1],
                corners[2]->lit.position[2] - corners[0]->lit.position[2],
            };
            float face_normal[3];
            Cross3(edge_a, edge_b, face_normal);
            if (!Normalize3(face_normal)) {
                face_normal[0] = 0.0f; face_normal[1] = 1.0f; face_normal[2] = 0.0f;
            }
            for (PreviewVertex* corner : corners) {
                if (!Normalize3(corner->lit.normal)) {
                    std::memcpy(corner->lit.normal, face_normal, sizeof(face_normal));
                }
            }

            const float du_a = corners[1]->lit.uv[0] - corners[0]->lit.uv[0];
            const float dv_a = corners[1]->lit.uv[1] - corners[0]->lit.uv[1];
            const float du_b = corners[2]->lit.uv[0] - corners[0]->lit.uv[0];
            const float dv_b = corners[2]->lit.uv[1] - corners[0]->lit.uv[1];
            const float determinant = du_a*dv_b - du_b*dv_a;
            float face_tangent[3] = {};
            float face_bitangent[3] = {};
            bool has_uv_frame = std::isfinite(determinant) && std::fabs(determinant) > 1.0e-10f;
            if (has_uv_frame) {
                const float inverse = 1.0f / determinant;
                for (int component = 0; component < 3; ++component) {
                    face_tangent[component] = (edge_a[component]*dv_b - edge_b[component]*dv_a) * inverse;
                    face_bitangent[component] = (edge_b[component]*du_a - edge_a[component]*du_b) * inverse;
                }
                has_uv_frame = Normalize3(face_tangent) && Normalize3(face_bitangent);
            }

            for (PreviewVertex* corner : corners) {
                float tangent[3] = { corner->lit.tangent[0], corner->lit.tangent[1], corner->lit.tangent[2] };
                if (!Normalize3(tangent)) {
                    if (has_uv_frame) {
                        std::memcpy(tangent, face_tangent, sizeof(tangent));
                    } else {
                        const float reference[3] = {
                            std::fabs(corner->lit.normal[1]) < 0.95f ? 0.0f : 1.0f,
                            std::fabs(corner->lit.normal[1]) < 0.95f ? 1.0f : 0.0f,
                            0.0f,
                        };
                        Cross3(reference, corner->lit.normal, tangent);
                        Normalize3(tangent);
                    }
                    std::memcpy(corner->lit.tangent, tangent, sizeof(tangent));
                }
                if (corner->lit.tangent[3] == 0.0f) {
                    float cross[3];
                    Cross3(corner->lit.normal, tangent, cross);
                    corner->lit.tangent[3] = has_uv_frame && Dot3(cross, face_bitangent) < 0.0f ? -1.0f : 1.0f;
                }
            }
        }
    }

    bool Finalize(VaiScenePreviewMesh* out_mesh, char* error, uint32_t error_capacity) {
        if (vertices.empty()) {
            SetError(error, error_capacity, "The scene contains no supported triangle geometry.");
            return false;
        }
        const size_t byte_count = vertices.size() * sizeof(VaiScenePreviewVertex);
        auto* allocated_vertices = static_cast<VaiScenePreviewVertex*>(std::malloc(byte_count));
        if (!allocated_vertices) {
            SetError(error, error_capacity, "Out of memory while creating the scene preview.");
            return false;
        }
        for (size_t index = 0; index < vertices.size(); ++index) {
            std::memcpy(allocated_vertices[index].position, vertices[index].lit.position, sizeof(allocated_vertices[index].position));
            std::memcpy(allocated_vertices[index].color, vertices[index].legacy_color, sizeof(allocated_vertices[index].color));
        }
        out_mesh->vertices = allocated_vertices;
        out_mesh->vertex_count = static_cast<uint32_t>(vertices.size());
        std::memcpy(out_mesh->bounds_min, bounds_min, sizeof(bounds_min));
        std::memcpy(out_mesh->bounds_max, bounds_max, sizeof(bounds_max));
        return true;
    }

    bool FinalizeLit(VaiLitScenePreviewMesh* out_mesh, char* error, uint32_t error_capacity) {
        if (vertices.empty()) {
            SetError(error, error_capacity, "The scene contains no supported triangle geometry.");
            return false;
        }
        CompleteMissingFrames();

        auto* allocated_vertices = static_cast<VaiLitScenePreviewVertex*>(
            std::malloc(vertices.size() * sizeof(VaiLitScenePreviewVertex)));
        auto* allocated_materials = static_cast<VaiLitScenePreviewMaterial*>(
            std::calloc(materials.size(), sizeof(VaiLitScenePreviewMaterial)));
        std::vector<VaiLitScenePreviewDrawRange> ranges;
        for (size_t first = 0; first < vertices.size();) {
            size_t end = first + 1;
            while (end < vertices.size() && vertices[end].material_index == vertices[first].material_index) ++end;
            ranges.push_back({
                static_cast<uint32_t>(first),
                static_cast<uint32_t>(end - first),
                vertices[first].material_index,
            });
            first = end;
        }
        auto* allocated_ranges = static_cast<VaiLitScenePreviewDrawRange*>(
            std::malloc(ranges.size() * sizeof(VaiLitScenePreviewDrawRange)));

        const auto cleanup = [&]() {
            if (allocated_materials) {
                for (size_t index = 0; index < materials.size(); ++index) {
                    std::free(const_cast<uint8_t*>(allocated_materials[index].base_color_texture.pixels));
                    std::free(const_cast<uint8_t*>(allocated_materials[index].normal_texture.pixels));
                }
            }
            std::free(allocated_vertices);
            std::free(allocated_materials);
            std::free(allocated_ranges);
        };
        if (!allocated_vertices || !allocated_materials || !allocated_ranges) {
            cleanup();
            SetError(error, error_capacity, "Out of memory while creating the lit scene preview.");
            return false;
        }

        for (size_t index = 0; index < vertices.size(); ++index) {
            allocated_vertices[index] = vertices[index].lit;
        }
        std::memcpy(allocated_ranges, ranges.data(), ranges.size() * sizeof(VaiLitScenePreviewDrawRange));
        for (size_t index = 0; index < materials.size(); ++index) {
            const PreviewMaterial& source = materials[index];
            VaiLitScenePreviewMaterial& destination = allocated_materials[index];
            destination.flags = source.flags;
            destination.normal_scale = source.normal_scale;
            const auto copy_texture = [&](const PreviewTexture& texture, VaiImagePreview* image) -> bool {
                if (texture.pixels.empty()) return true;
                auto* pixels = static_cast<uint8_t*>(std::malloc(texture.pixels.size()));
                if (!pixels) return false;
                std::memcpy(pixels, texture.pixels.data(), texture.pixels.size());
                image->pixels = pixels;
                image->width = texture.width;
                image->height = texture.height;
                image->row_stride = texture.width * 4;
                return true;
            };
            if (!copy_texture(source.base_color_texture, &destination.base_color_texture)
            || !copy_texture(source.normal_texture, &destination.normal_texture)) {
                cleanup();
                SetError(error, error_capacity, "Out of memory while copying scene preview textures.");
                return false;
            }
        }

        out_mesh->vertices = allocated_vertices;
        out_mesh->vertex_count = static_cast<uint32_t>(vertices.size());
        out_mesh->materials = allocated_materials;
        out_mesh->material_count = static_cast<uint32_t>(materials.size());
        out_mesh->draw_ranges = allocated_ranges;
        out_mesh->draw_range_count = static_cast<uint32_t>(ranges.size());
        std::memcpy(out_mesh->bounds_min, bounds_min, sizeof(bounds_min));
        std::memcpy(out_mesh->bounds_max, bounds_max, sizeof(bounds_max));
        return true;
    }
};

bool FBXTextureDimensionsAreSafe(int width, int height);

bool DecodeTextureMemory(const uint8_t* data, size_t size, PreviewTexture* texture) {
    if (!data || size == 0 || size > static_cast<size_t>(INT_MAX)) return false;
    int width = 0;
    int height = 0;
    int source_channels = 0;
    if (!stbi_info_from_memory(data, static_cast<int>(size), &width, &height, &source_channels)
    || !FBXTextureDimensionsAreSafe(width, height)) {
        return false;
    }
    stbi_uc* pixels = stbi_load_from_memory(
        data, static_cast<int>(size), &width, &height, &source_channels, 4);
    if (!pixels) return false;
    const size_t byte_count = static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
    texture->pixels.assign(pixels, pixels + byte_count);
    texture->width = static_cast<uint32_t>(width);
    texture->height = static_cast<uint32_t>(height);
    stbi_image_free(pixels);
    return true;
}

int Base64Value(unsigned char value) {
    if (value >= 'A' && value <= 'Z') return value - 'A';
    if (value >= 'a' && value <= 'z') return value - 'a' + 26;
    if (value >= '0' && value <= '9') return value - '0' + 52;
    if (value == '+') return 62;
    if (value == '/') return 63;
    return -1;
}

bool DecodeBase64(const char* encoded, std::vector<uint8_t>* decoded) {
    decoded->clear();
    int accumulator = 0;
    int bits = -8;
    for (const unsigned char* cursor = reinterpret_cast<const unsigned char*>(encoded); *cursor; ++cursor) {
        if (*cursor == '=') break;
        const int value = Base64Value(*cursor);
        if (value < 0) {
            if (std::isspace(*cursor)) continue;
            return false;
        }
        accumulator = (accumulator << 6) | value;
        bits += 6;
        if (bits >= 0) {
            decoded->push_back(static_cast<uint8_t>((accumulator >> bits) & 0xff));
            bits -= 8;
        }
    }
    return !decoded->empty();
}

std::string DirectoryOf(const char* path) {
    const std::string value = path ? path : "";
    const size_t separator = value.find_last_of("/\\");
    return separator == std::string::npos ? std::string() : value.substr(0, separator + 1);
}

bool LoadGLTFTexture(const char* scene_path, const cgltf_texture* texture, PreviewTexture* output) {
    if (!texture) return false;
    const cgltf_image* image = texture->image;
    if (!image && texture->has_webp) image = texture->webp_image;
    if (!image || texture->has_basisu) return false;

    if (image->buffer_view && image->buffer_view->buffer && image->buffer_view->buffer->data) {
        const uint8_t* data = static_cast<const uint8_t*>(image->buffer_view->buffer->data)
            + image->buffer_view->offset;
        return DecodeTextureMemory(data, image->buffer_view->size, output);
    }
    if (!image->uri) return false;
    if (std::strncmp(image->uri, "data:", 5) == 0) {
        const char* comma = std::strchr(image->uri, ',');
        if (!comma || comma - image->uri < 7
        || std::strncmp(comma - 7, ";base64", 7) != 0) {
            return false;
        }
        std::vector<uint8_t> decoded;
        return DecodeBase64(comma + 1, &decoded)
            && DecodeTextureMemory(decoded.data(), decoded.size(), output);
    }

    std::vector<char> decoded_uri(std::strlen(image->uri) + 1);
    std::memcpy(decoded_uri.data(), image->uri, decoded_uri.size());
    cgltf_decode_uri(decoded_uri.data());
    const std::string filename = DirectoryOf(scene_path) + decoded_uri.data();
    int width = 0;
    int height = 0;
    int source_channels = 0;
    if (!stbi_info(filename.c_str(), &width, &height, &source_channels)
    || !FBXTextureDimensionsAreSafe(width, height)) {
        return false;
    }
    stbi_uc* pixels = stbi_load(filename.c_str(), &width, &height, &source_channels, 4);
    if (!pixels) return false;
    const size_t byte_count = static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
    output->pixels.assign(pixels, pixels + byte_count);
    output->width = static_cast<uint32_t>(width);
    output->height = static_cast<uint32_t>(height);
    stbi_image_free(pixels);
    return true;
}

struct GLTFPreviewMaterial {
    const cgltf_material* material = nullptr;
    const cgltf_texture_view* base_texture_view = nullptr;
    const cgltf_texture_view* normal_texture_view = nullptr;
    uint32_t build_material_index = 0;
    float base_color[4] = { 0.78f, 0.80f, 0.84f, 1.0f };
};

GLTFPreviewMaterial* GLTFPreviewMaterialFor(
    PreviewBuild& build,
    std::vector<GLTFPreviewMaterial>& preview_materials,
    const char* scene_path,
    const cgltf_material* material
) {
    for (GLTFPreviewMaterial& preview : preview_materials) {
        if (preview.material == material) return &preview;
    }
    preview_materials.emplace_back();
    GLTFPreviewMaterial& preview = preview_materials.back();
    preview.material = material;
    if (!material) return &preview;

    if (material->has_pbr_metallic_roughness) {
        std::memcpy(preview.base_color, material->pbr_metallic_roughness.base_color_factor, sizeof(preview.base_color));
        preview.base_texture_view = &material->pbr_metallic_roughness.base_color_texture;
    } else if (material->has_pbr_specular_glossiness) {
        std::memcpy(preview.base_color, material->pbr_specular_glossiness.diffuse_factor, sizeof(preview.base_color));
        preview.base_texture_view = &material->pbr_specular_glossiness.diffuse_texture;
    }
    preview.normal_texture_view = &material->normal_texture;

    PreviewMaterial build_material;
    if (preview.base_texture_view->texture
    && LoadGLTFTexture(scene_path, preview.base_texture_view->texture, &build_material.base_color_texture)) {
        build_material.flags |= VAI_SCENE_MATERIAL_BASE_COLOR_TEXTURE;
    }
    if (preview.normal_texture_view->texture
    && LoadGLTFTexture(scene_path, preview.normal_texture_view->texture, &build_material.normal_texture)) {
        build_material.flags |= VAI_SCENE_MATERIAL_NORMAL_TEXTURE;
        build_material.normal_scale = preview.normal_texture_view->scale;
        if (!std::isfinite(build_material.normal_scale)) build_material.normal_scale = 1.0f;
        build_material.normal_scale = std::max(0.0f, std::min(build_material.normal_scale, 8.0f));
    }
    const cgltf_texture* wrap_texture = preview.base_texture_view->texture
        ? preview.base_texture_view->texture : preview.normal_texture_view->texture;
    if (wrap_texture && wrap_texture->sampler) {
        if (wrap_texture->sampler->wrap_s != cgltf_wrap_mode_clamp_to_edge) {
            build_material.flags |= VAI_SCENE_MATERIAL_WRAP_U_REPEAT;
        }
        if (wrap_texture->sampler->wrap_t != cgltf_wrap_mode_clamp_to_edge) {
            build_material.flags |= VAI_SCENE_MATERIAL_WRAP_V_REPEAT;
        }
    } else {
        build_material.flags |= VAI_SCENE_MATERIAL_WRAP_U_REPEAT | VAI_SCENE_MATERIAL_WRAP_V_REPEAT;
    }
    preview.build_material_index = build.AddMaterial(std::move(build_material));
    return &preview;
}

void TransformGLTFDirection(const float transform[16], const float source[3], float output[3]) {
    output[0] = transform[0]*source[0] + transform[4]*source[1] + transform[8]*source[2];
    output[1] = transform[1]*source[0] + transform[5]*source[1] + transform[9]*source[2];
    output[2] = transform[2]*source[0] + transform[6]*source[1] + transform[10]*source[2];
    Normalize3(output);
}

void TransformGLTFUV(const cgltf_texture_view* view, float uv[2]) {
    if (!view || !view->has_transform) return;
    const float scaled_u = uv[0] * view->transform.scale[0];
    const float scaled_v = uv[1] * view->transform.scale[1];
    const float cosine = std::cos(view->transform.rotation);
    const float sine = std::sin(view->transform.rotation);
    uv[0] = view->transform.offset[0] + cosine*scaled_u - sine*scaled_v;
    uv[1] = view->transform.offset[1] + sine*scaled_u + cosine*scaled_v;
}

bool AppendGLTFPrimitive(
    PreviewBuild& build,
    std::vector<GLTFPreviewMaterial>& preview_materials,
    const char* scene_path,
    const cgltf_node* node,
    const cgltf_primitive& primitive
) {
    if (primitive.type != cgltf_primitive_type_triangles) return true;

    const cgltf_accessor* positions = nullptr;
    const cgltf_accessor* normals = nullptr;
    const cgltf_accessor* tangents = nullptr;
    const cgltf_accessor* colors = nullptr;
    const cgltf_accessor* texcoords = nullptr;
    GLTFPreviewMaterial* preview_material = GLTFPreviewMaterialFor(
        build, preview_materials, scene_path, primitive.material);
    int texcoord_set = 0;
    const cgltf_texture_view* uv_view = preview_material->base_texture_view;
    if (!uv_view || !uv_view->texture) uv_view = preview_material->normal_texture_view;
    if (uv_view) {
        texcoord_set = uv_view->has_transform && uv_view->transform.has_texcoord
            ? uv_view->transform.texcoord : uv_view->texcoord;
    }
    for (cgltf_size attribute_index = 0; attribute_index < primitive.attributes_count; ++attribute_index) {
        const cgltf_attribute& attribute = primitive.attributes[attribute_index];
        if (attribute.type == cgltf_attribute_type_position) positions = attribute.data;
        if (attribute.type == cgltf_attribute_type_normal) normals = attribute.data;
        if (attribute.type == cgltf_attribute_type_tangent) tangents = attribute.data;
        if (attribute.type == cgltf_attribute_type_color && attribute.index == 0) colors = attribute.data;
        if (attribute.type == cgltf_attribute_type_texcoord && attribute.index == texcoord_set) texcoords = attribute.data;
    }
    if (!positions || positions->count == 0) return true;

    float transform[16];
    cgltf_node_transform_world(node, transform);

    const cgltf_size index_count = primitive.indices ? primitive.indices->count : positions->count;
    const cgltf_size triangle_count = index_count / 3;
    for (cgltf_size triangle = 0; triangle < triangle_count; ++triangle) {
        for (cgltf_size corner = 0; corner < 3; ++corner) {
            const cgltf_size element = triangle * 3 + corner;
            const cgltf_size vertex_index = primitive.indices ? cgltf_accessor_read_index(primitive.indices, element) : element;
            if (vertex_index >= positions->count) continue;

            float position[3] = {};
            if (!cgltf_accessor_read_float(positions, vertex_index, position, 3)) continue;
            float color[4] = {
                preview_material->base_color[0],
                preview_material->base_color[1],
                preview_material->base_color[2],
                preview_material->base_color[3],
            };
            if (colors && vertex_index < colors->count) {
                const cgltf_size component_count = std::min<cgltf_size>(4, cgltf_num_components(colors->type));
                float vertex_color[4] = { 1, 1, 1, 1 };
                if (cgltf_accessor_read_float(colors, vertex_index, vertex_color, component_count)) {
                    for (int component = 0; component < 4; ++component) color[component] *= vertex_color[component];
                }
            }

            const float output_position[3] = {
                transform[0] * position[0] + transform[4] * position[1] + transform[8]  * position[2] + transform[12],
                transform[1] * position[0] + transform[5] * position[1] + transform[9]  * position[2] + transform[13],
                transform[2] * position[0] + transform[6] * position[1] + transform[10] * position[2] + transform[14],
            };
            float normal[3] = {};
            if (normals && vertex_index < normals->count) {
                float source[3] = {};
                if (cgltf_accessor_read_float(normals, vertex_index, source, 3)) {
                    TransformGLTFDirection(transform, source, normal);
                }
            }
            float tangent[4] = {};
            if (tangents && vertex_index < tangents->count) {
                float source[4] = {};
                if (cgltf_accessor_read_float(tangents, vertex_index, source, 4)) {
                    TransformGLTFDirection(transform, source, tangent);
                    tangent[3] = source[3];
                }
            }
            float uv[2] = {};
            if (texcoords && vertex_index < texcoords->count) {
                cgltf_accessor_read_float(texcoords, vertex_index, uv, 2);
                TransformGLTFUV(uv_view, uv);
            }
            if (!build.AppendLit(
                output_position, normal, tangent, color, color, uv,
                preview_material->build_material_index)) {
                return false;
            }
        }
    }
    return true;
}

bool LoadGLTF(const char* path, PreviewBuild& build, char* error, uint32_t error_capacity) {
    cgltf_options options = {};
    cgltf_data* data = nullptr;
    cgltf_result result = cgltf_parse_file(&options, path, &data);
    if (result != cgltf_result_success) {
        SetError(error, error_capacity, "Unable to parse the glTF asset.");
        return false;
    }
    const auto free_data = [&]() { cgltf_free(data); };

    result = cgltf_load_buffers(&options, data, path);
    if (result != cgltf_result_success) {
        free_data();
        SetError(error, error_capacity, "Unable to load a glTF buffer referenced by this asset.");
        return false;
    }

    std::vector<GLTFPreviewMaterial> preview_materials;
    for (cgltf_size node_index = 0; node_index < data->nodes_count; ++node_index) {
        const cgltf_node& node = data->nodes[node_index];
        if (!node.mesh) continue;
        for (cgltf_size primitive_index = 0; primitive_index < node.mesh->primitives_count; ++primitive_index) {
            if (!AppendGLTFPrimitive(build, preview_materials, path, &node, node.mesh->primitives[primitive_index])) {
                free_data();
                SetError(error, error_capacity, "The glTF preview exceeds Vai's geometry safety limit.");
                return false;
            }
        }
    }
    free_data();
    return true;
}

struct FBXPreviewMaterial {
    const ufbx_material* material = nullptr;
    const ufbx_texture* texture = nullptr;
    const ufbx_texture* normal_texture = nullptr;
    stbi_uc* pixels = nullptr;
    stbi_uc* normal_pixels = nullptr;
    int width = 0;
    int height = 0;
    int normal_width = 0;
    int normal_height = 0;
    float base_color[3] = { 0.78f, 0.80f, 0.84f };
    float average_texture_color[3] = { 1.0f, 1.0f, 1.0f };
    uint32_t build_material_index = 0;
};

const ufbx_material* FBXMaterialForFace(const ufbx_node* node, const ufbx_mesh* mesh, size_t face_index) {
    if (mesh->face_material.count == 0 || face_index >= mesh->face_material.count) return nullptr;
    const uint32_t material_index = mesh->face_material.data[face_index];
    const ufbx_material_list& materials = node->materials.count ? node->materials : mesh->materials;
    if (material_index >= materials.count) return nullptr;
    return materials.data[material_index];
}

const ufbx_texture* FBXFileTexture(const ufbx_material_map* map) {
    if (!map || !map->texture) return nullptr;
    if (map->texture->type == UFBX_TEXTURE_FILE) return map->texture;
    for (size_t index = 0; index < map->texture->file_textures.count; ++index) {
        const ufbx_texture* texture = map->texture->file_textures.data[index];
        if (texture && texture->type == UFBX_TEXTURE_FILE) return texture;
    }
    return nullptr;
}

bool FBXTextureDimensionsAreSafe(int width, int height) {
    constexpr int kMaxTextureDimension = 16384;
    constexpr uint64_t kMaxTextureBytes = 256ull * 1024ull * 1024ull;
    return width > 0 && height > 0
        && width <= kMaxTextureDimension && height <= kMaxTextureDimension
        && static_cast<uint64_t>(width) * static_cast<uint64_t>(height) * 4ull <= kMaxTextureBytes;
}

stbi_uc* LoadFBXTexture(const ufbx_texture* texture, int* width, int* height) {
    if (!texture) return nullptr;
    const ufbx_blob* content = nullptr;
    if (texture->content.data && texture->content.size > 0) {
        content = &texture->content;
    } else if (texture->video && texture->video->content.data && texture->video->content.size > 0) {
        content = &texture->video->content;
    }

    int source_channels = 0;
    if (content) {
        if (content->size > static_cast<size_t>(INT_MAX)
        || !stbi_info_from_memory(static_cast<const stbi_uc*>(content->data), static_cast<int>(content->size), width, height, &source_channels)
        || !FBXTextureDimensionsAreSafe(*width, *height)) {
            return nullptr;
        }
        return stbi_load_from_memory(
            static_cast<const stbi_uc*>(content->data),
            static_cast<int>(content->size),
            width,
            height,
            &source_channels,
            4);
    }

    if (!texture->filename.data || texture->filename.length == 0) return nullptr;
    const std::string filename(texture->filename.data, texture->filename.length);
    if (!stbi_info(filename.c_str(), width, height, &source_channels)
    || !FBXTextureDimensionsAreSafe(*width, *height)) {
        return nullptr;
    }
    return stbi_load(filename.c_str(), width, height, &source_channels, 4);
}

FBXPreviewMaterial* FBXPreviewMaterialFor(
    PreviewBuild& build,
    std::vector<FBXPreviewMaterial>& preview_materials,
    const ufbx_material* material
) {
    for (FBXPreviewMaterial& preview : preview_materials) {
        if (preview.material == material) return &preview;
    }

    preview_materials.emplace_back();
    FBXPreviewMaterial& preview = preview_materials.back();
    preview.material = material;
    if (!material) return &preview;

    const ufbx_material_map* color_map = nullptr;
    const ufbx_material_map* factor_map = nullptr;
    if (material->pbr.base_color.has_value || material->pbr.base_color.texture) {
        color_map = &material->pbr.base_color;
        factor_map = &material->pbr.base_factor;
    } else if (material->fbx.diffuse_color.has_value || material->fbx.diffuse_color.texture) {
        color_map = &material->fbx.diffuse_color;
        factor_map = &material->fbx.diffuse_factor;
    }

    if (color_map && color_map->has_value) {
        preview.base_color[0] = static_cast<float>(color_map->value_vec3.x);
        preview.base_color[1] = static_cast<float>(color_map->value_vec3.y);
        preview.base_color[2] = static_cast<float>(color_map->value_vec3.z);
    } else if (color_map && color_map->texture) {
        preview.base_color[0] = preview.base_color[1] = preview.base_color[2] = 1.0f;
    }
    if (factor_map && factor_map->has_value) {
        const float factor = static_cast<float>(factor_map->value_real);
        preview.base_color[0] *= factor;
        preview.base_color[1] *= factor;
        preview.base_color[2] *= factor;
    }

    preview.texture = FBXFileTexture(&material->pbr.base_color);
    if (!preview.texture) preview.texture = FBXFileTexture(&material->fbx.diffuse_color);
    preview.pixels = LoadFBXTexture(preview.texture, &preview.width, &preview.height);
    if (preview.pixels) {
        const uint64_t pixel_count = static_cast<uint64_t>(preview.width) * static_cast<uint64_t>(preview.height);
        const uint64_t sample_stride = std::max<uint64_t>(pixel_count / 4096ull, 1ull);
        uint64_t samples = 0;
        double totals[3] = {};
        for (uint64_t pixel = 0; pixel < pixel_count; pixel += sample_stride) {
            totals[0] += preview.pixels[pixel * 4 + 0];
            totals[1] += preview.pixels[pixel * 4 + 1];
            totals[2] += preview.pixels[pixel * 4 + 2];
            ++samples;
        }
        preview.average_texture_color[0] = static_cast<float>(totals[0] / (255.0 * static_cast<double>(samples)));
        preview.average_texture_color[1] = static_cast<float>(totals[1] / (255.0 * static_cast<double>(samples)));
        preview.average_texture_color[2] = static_cast<float>(totals[2] / (255.0 * static_cast<double>(samples)));
    }

    preview.normal_texture = FBXFileTexture(&material->pbr.normal_map);
    if (!preview.normal_texture) preview.normal_texture = FBXFileTexture(&material->fbx.normal_map);
    if (!preview.normal_texture) preview.normal_texture = FBXFileTexture(&material->fbx.bump);
    preview.normal_pixels = LoadFBXTexture(preview.normal_texture, &preview.normal_width, &preview.normal_height);

    PreviewMaterial build_material;
    build_material.normal_scale = material->fbx.bump_factor.has_value
        ? static_cast<float>(material->fbx.bump_factor.value_real) : 1.0f;
    if (!std::isfinite(build_material.normal_scale)) build_material.normal_scale = 1.0f;
    build_material.normal_scale = std::max(0.0f, std::min(build_material.normal_scale, 8.0f));
    const ufbx_texture* wrap_texture = preview.texture ? preview.texture : preview.normal_texture;
    if (wrap_texture) {
        if (wrap_texture->wrap_u == UFBX_WRAP_REPEAT) build_material.flags |= VAI_SCENE_MATERIAL_WRAP_U_REPEAT;
        if (wrap_texture->wrap_v == UFBX_WRAP_REPEAT) build_material.flags |= VAI_SCENE_MATERIAL_WRAP_V_REPEAT;
    }
    if (preview.pixels) {
        const size_t byte_count = static_cast<size_t>(preview.width) * static_cast<size_t>(preview.height) * 4;
        build_material.base_color_texture.pixels.assign(preview.pixels, preview.pixels + byte_count);
        build_material.base_color_texture.width = static_cast<uint32_t>(preview.width);
        build_material.base_color_texture.height = static_cast<uint32_t>(preview.height);
        build_material.flags |= VAI_SCENE_MATERIAL_BASE_COLOR_TEXTURE;
    }
    if (preview.normal_pixels) {
        const size_t byte_count = static_cast<size_t>(preview.normal_width) * static_cast<size_t>(preview.normal_height) * 4;
        build_material.normal_texture.pixels.assign(preview.normal_pixels, preview.normal_pixels + byte_count);
        build_material.normal_texture.width = static_cast<uint32_t>(preview.normal_width);
        build_material.normal_texture.height = static_cast<uint32_t>(preview.normal_height);
        build_material.flags |= VAI_SCENE_MATERIAL_NORMAL_TEXTURE;
    }
    preview.build_material_index = build.AddMaterial(std::move(build_material));
    return &preview;
}

double FBXWrapTextureCoordinate(double value, ufbx_wrap_mode wrap) {
    if (wrap == UFBX_WRAP_CLAMP) return std::max(0.0, std::min(value, 1.0));
    return value - std::floor(value);
}

void FBXVertexColor(
    const FBXPreviewMaterial* preview,
    const ufbx_mesh* mesh,
    uint32_t vertex_index,
    float color[4]
) {
    color[0] = preview->base_color[0];
    color[1] = preview->base_color[1];
    color[2] = preview->base_color[2];
    color[3] = 1.0f;

    if (preview->pixels) {
        float sampled[3] = {
            preview->average_texture_color[0],
            preview->average_texture_color[1],
            preview->average_texture_color[2],
        };
        if (mesh->vertex_uv.exists && vertex_index < mesh->vertex_uv.indices.count) {
            ufbx_vec2 uv = ufbx_get_vertex_vec2(&mesh->vertex_uv, vertex_index);
            if (preview->texture->has_uv_transform) {
                const ufbx_vec3 transformed = ufbx_transform_position(
                    &preview->texture->uv_to_texture,
                    ufbx_vec3{ uv.x, uv.y, 0.0 });
                uv.x = transformed.x;
                uv.y = transformed.y;
            }
            const double u = FBXWrapTextureCoordinate(uv.x, preview->texture->wrap_u);
            const double v = FBXWrapTextureCoordinate(uv.y, preview->texture->wrap_v);
            const int x = std::min(static_cast<int>(u * preview->width), preview->width - 1);
            const int y = std::min(static_cast<int>((1.0 - v) * preview->height), preview->height - 1);
            const stbi_uc* texel = preview->pixels + (static_cast<size_t>(y) * preview->width + x) * 4;
            sampled[0] = static_cast<float>(texel[0]) / 255.0f;
            sampled[1] = static_cast<float>(texel[1]) / 255.0f;
            sampled[2] = static_cast<float>(texel[2]) / 255.0f;
        }
        color[0] *= sampled[0];
        color[1] *= sampled[1];
        color[2] *= sampled[2];
    }

    if (mesh->vertex_color.exists && vertex_index < mesh->vertex_color.indices.count) {
        const ufbx_vec4 vertex_color = ufbx_get_vertex_vec4(&mesh->vertex_color, vertex_index);
        color[0] *= static_cast<float>(vertex_color.x);
        color[1] *= static_cast<float>(vertex_color.y);
        color[2] *= static_cast<float>(vertex_color.z);
    }
}

void FBXLitVertexAttributes(
    const FBXPreviewMaterial* preview,
    const ufbx_node* node,
    const ufbx_mesh* mesh,
    uint32_t vertex_index,
    float normal[3],
    float tangent[4],
    float color[4],
    float legacy_color[4],
    float uv_out[2]
) {
    color[0] = preview->base_color[0];
    color[1] = preview->base_color[1];
    color[2] = preview->base_color[2];
    color[3] = 1.0f;
    if (mesh->vertex_color.exists && vertex_index < mesh->vertex_color.indices.count) {
        const ufbx_vec4 vertex_color = ufbx_get_vertex_vec4(&mesh->vertex_color, vertex_index);
        color[0] *= static_cast<float>(vertex_color.x);
        color[1] *= static_cast<float>(vertex_color.y);
        color[2] *= static_cast<float>(vertex_color.z);
        color[3] *= static_cast<float>(vertex_color.w);
    }
    FBXVertexColor(preview, mesh, vertex_index, legacy_color);

    const ufbx_texture* uv_texture = preview->texture ? preview->texture : preview->normal_texture;
    if (mesh->vertex_uv.exists && vertex_index < mesh->vertex_uv.indices.count) {
        ufbx_vec2 uv = ufbx_get_vertex_vec2(&mesh->vertex_uv, vertex_index);
        if (uv_texture && uv_texture->has_uv_transform) {
            const ufbx_vec3 transformed = ufbx_transform_position(
                &uv_texture->uv_to_texture,
                ufbx_vec3{ uv.x, uv.y, 0.0 });
            uv.x = transformed.x;
            uv.y = transformed.y;
        }
        uv_out[0] = static_cast<float>(uv.x);
        uv_out[1] = static_cast<float>(uv.y);
    }

    if (mesh->skinned_normal.exists && vertex_index < mesh->skinned_normal.indices.count) {
        ufbx_vec3 value = ufbx_get_vertex_vec3(&mesh->skinned_normal, vertex_index);
        if (mesh->skinned_is_local) value = ufbx_transform_direction(&node->geometry_to_world, value);
        normal[0] = static_cast<float>(value.x);
        normal[1] = static_cast<float>(value.y);
        normal[2] = static_cast<float>(value.z);
        Normalize3(normal);
    }
    if (mesh->vertex_tangent.exists && vertex_index < mesh->vertex_tangent.indices.count) {
        ufbx_vec3 value = ufbx_get_vertex_vec3(&mesh->vertex_tangent, vertex_index);
        if (mesh->skinned_is_local) value = ufbx_transform_direction(&node->geometry_to_world, value);
        tangent[0] = static_cast<float>(value.x);
        tangent[1] = static_cast<float>(value.y);
        tangent[2] = static_cast<float>(value.z);
        Normalize3(tangent);
    }
    if (mesh->vertex_bitangent.exists && vertex_index < mesh->vertex_bitangent.indices.count
    && Dot3(normal, normal) > 0.0f && Dot3(tangent, tangent) > 0.0f) {
        ufbx_vec3 value = ufbx_get_vertex_vec3(&mesh->vertex_bitangent, vertex_index);
        if (mesh->skinned_is_local) value = ufbx_transform_direction(&node->geometry_to_world, value);
        float bitangent[3] = {
            static_cast<float>(value.x),
            static_cast<float>(value.y),
            static_cast<float>(value.z),
        };
        Normalize3(bitangent);
        float cross[3];
        Cross3(normal, tangent, cross);
        tangent[3] = Dot3(cross, bitangent) < 0.0f ? -1.0f : 1.0f;
    }
}

bool LoadFBX(const char* path, PreviewBuild& build, char* error, uint32_t error_capacity) {
    ufbx_load_opts options = {};
    options.ignore_missing_external_files = true;
    options.generate_missing_normals = true;
    options.use_blender_pbr_material = true;
    if (ExtensionOf(path) == "obj") {
        // OBJ materials live in a separate .mtl file. Missing material libraries
        // should not prevent geometry-only previews from loading.
        options.load_external_files = true;
    }
    ufbx_error load_error = {};
    ufbx_scene* scene = ufbx_load_file(path, &options, &load_error);
    if (!scene) {
        char ufbx_error[512] = {};
        ufbx_format_error(ufbx_error, sizeof(ufbx_error), &load_error);
        SetError(error, error_capacity, ufbx_error);
        return false;
    }

    std::vector<uint32_t> triangle_indices;
    std::vector<FBXPreviewMaterial> preview_materials;
    for (size_t node_index = 0; node_index < scene->nodes.count; ++node_index) {
        const ufbx_node* node = scene->nodes.data[node_index];
        if (!node || !node->mesh || !node->visible) continue;
        const ufbx_mesh* mesh = node->mesh;
        triangle_indices.resize(mesh->max_face_triangles * 3);
        for (size_t face_index = 0; face_index < mesh->num_faces; ++face_index) {
            const size_t triangle_count = ufbx_triangulate_face(triangle_indices.data(), triangle_indices.size(), mesh, mesh->faces.data[face_index]);
            const ufbx_material* material = FBXMaterialForFace(node, mesh, face_index);
            const FBXPreviewMaterial* preview_material = FBXPreviewMaterialFor(build, preview_materials, material);
            for (size_t triangle = 0; triangle < triangle_count; ++triangle) {
                for (size_t corner = 0; corner < 3; ++corner) {
                    const uint32_t index = triangle_indices[triangle * 3 + corner];
                    if (index >= mesh->skinned_position.indices.count) continue;
                    ufbx_vec3 position = ufbx_get_vertex_vec3(&mesh->skinned_position, index);
                    if (mesh->skinned_is_local) position = ufbx_transform_position(&node->geometry_to_world, position);
                    const float output_position[3] = {
                        static_cast<float>(position.x),
                        static_cast<float>(position.y),
                        static_cast<float>(position.z),
                    };
                    float normal[3] = {};
                    float tangent[4] = {};
                    float color[4] = {};
                    float legacy_color[4] = {};
                    float uv[2] = {};
                    FBXLitVertexAttributes(
                        preview_material, node, mesh, index,
                        normal, tangent, color, legacy_color, uv);
                    if (!build.AppendLit(
                        output_position, normal, tangent, color, legacy_color, uv,
                        preview_material->build_material_index)) {
                        for (FBXPreviewMaterial& preview : preview_materials) {
                            stbi_image_free(preview.pixels);
                            stbi_image_free(preview.normal_pixels);
                        }
                        ufbx_free_scene(scene);
                        SetError(error, error_capacity, "The FBX preview exceeds Vai's geometry safety limit.");
                        return false;
                    }
                }
            }
        }
    }
    for (FBXPreviewMaterial& preview : preview_materials) {
        stbi_image_free(preview.pixels);
        stbi_image_free(preview.normal_pixels);
    }
    ufbx_free_scene(scene);
    return true;
}

bool ReadUSDAttribute(
    const tinyusdz::tydra::VertexAttribute& attribute,
    size_t point_index,
    size_t face_vertex_index,
    size_t expected_components,
    float* output
) {
    using Format = tinyusdz::tydra::VertexAttributeFormat;
    if (attribute.empty()) return false;
    const size_t available_components = attribute.format == Format::Vec2 ? 2
        : attribute.format == Format::Vec3 ? 3
        : attribute.format == Format::Vec4 ? 4 : 0;
    if (available_components < expected_components) return false;

    size_t index = attribute.is_constant() ? 0 : point_index;
    if (!attribute.is_constant() && attribute.vertex_count() != 0
    && point_index >= attribute.vertex_count() && face_vertex_index < attribute.vertex_count()) {
        index = face_vertex_index;
    }
    if (!attribute.indices.empty()) {
        if (index >= attribute.indices.size()) return false;
        index = attribute.indices[index];
    }
    const size_t stride = attribute.stride_bytes();
    if (index >= attribute.vertex_count() || stride < available_components*sizeof(float)
    || index*stride + available_components*sizeof(float) > attribute.data.size()) {
        return false;
    }
    std::memcpy(output, attribute.data.data() + index*stride, expected_components*sizeof(float));
    return true;
}

void TransformUSDDirection(
    const tinyusdz::value::matrix4d& matrix,
    const float source[3],
    float output[3]
) {
    output[0] = static_cast<float>(source[0]*matrix.m[0][0] + source[1]*matrix.m[1][0] + source[2]*matrix.m[2][0]);
    output[1] = static_cast<float>(source[0]*matrix.m[0][1] + source[1]*matrix.m[1][1] + source[2]*matrix.m[2][1]);
    output[2] = static_cast<float>(source[0]*matrix.m[0][2] + source[1]*matrix.m[1][2] + source[2]*matrix.m[2][2]);
    Normalize3(output);
}

bool CopyUSDTexture(
    const tinyusdz::tydra::RenderScene& scene,
    int32_t texture_id,
    PreviewTexture* output,
    uint32_t* material_flags
) {
    if (texture_id < 0 || static_cast<size_t>(texture_id) >= scene.textures.size()) return false;
    const tinyusdz::tydra::UVTexture& texture = scene.textures[static_cast<size_t>(texture_id)];
    if (texture.texture_image_id < 0 || static_cast<size_t>(texture.texture_image_id) >= scene.images.size()) return false;
    const tinyusdz::tydra::TextureImage& image = scene.images[static_cast<size_t>(texture.texture_image_id)];
    if (image.buffer_id < 0 || static_cast<size_t>(image.buffer_id) >= scene.buffers.size()) return false;
    const tinyusdz::tydra::BufferData& buffer = scene.buffers[static_cast<size_t>(image.buffer_id)];

    bool copied = false;
    if (image.decoded && image.texelComponentType == tinyusdz::tydra::ComponentType::UInt8
    && image.width > 0 && image.height > 0 && image.channels > 0 && image.channels <= 4
    && FBXTextureDimensionsAreSafe(image.width, image.height)) {
        const size_t pixel_count = static_cast<size_t>(image.width) * static_cast<size_t>(image.height);
        if (buffer.data.size() >= pixel_count * static_cast<size_t>(image.channels)) {
            output->pixels.resize(pixel_count * 4);
            for (size_t pixel = 0; pixel < pixel_count; ++pixel) {
                const uint8_t* source = buffer.data.data() + pixel * image.channels;
                uint8_t* destination = output->pixels.data() + pixel * 4;
                destination[0] = source[0];
                destination[1] = image.channels > 1 ? source[1] : source[0];
                destination[2] = image.channels > 2 ? source[2] : source[0];
                destination[3] = image.channels > 3 ? source[3] : 255;
            }
            output->width = static_cast<uint32_t>(image.width);
            output->height = static_cast<uint32_t>(image.height);
            copied = true;
        }
    } else if (!image.decoded) {
        copied = DecodeTextureMemory(buffer.data.data(), buffer.data.size(), output);
    }
    if (copied) {
        using Wrap = tinyusdz::tydra::UVTexture::WrapMode;
        if (texture.wrapS == Wrap::REPEAT || texture.wrapS == Wrap::MIRROR) {
            *material_flags |= VAI_SCENE_MATERIAL_WRAP_U_REPEAT;
        }
        if (texture.wrapT == Wrap::REPEAT || texture.wrapT == Wrap::MIRROR) {
            *material_flags |= VAI_SCENE_MATERIAL_WRAP_V_REPEAT;
        }
    }
    return copied;
}

void TransformUSDUV(const tinyusdz::tydra::UVTexture* texture, float uv[2]) {
    if (!texture || !texture->has_transform2d) return;
    const float scaled_u = uv[0] * texture->tx_scale[0];
    const float scaled_v = uv[1] * texture->tx_scale[1];
    const float cosine = std::cos(texture->tx_rotation);
    const float sine = std::sin(texture->tx_rotation);
    uv[0] = texture->tx_translation[0] + cosine*scaled_u - sine*scaled_v;
    uv[1] = texture->tx_translation[1] + sine*scaled_u + cosine*scaled_v;
}

std::vector<uint32_t> BuildUSDMaterials(PreviewBuild& build, const tinyusdz::tydra::RenderScene& scene) {
    std::vector<uint32_t> material_indices(scene.materials.size(), 0);
    for (size_t index = 0; index < scene.materials.size(); ++index) {
        const tinyusdz::tydra::RenderMaterial& source = scene.materials[index];
        PreviewMaterial material;
        if (CopyUSDTexture(scene, source.surfaceShader.diffuseColor.texture_id, &material.base_color_texture, &material.flags)) {
            material.flags |= VAI_SCENE_MATERIAL_BASE_COLOR_TEXTURE;
        }
        if (CopyUSDTexture(scene, source.surfaceShader.normal.texture_id, &material.normal_texture, &material.flags)) {
            material.flags |= VAI_SCENE_MATERIAL_NORMAL_TEXTURE;
        }
        material_indices[index] = build.AddMaterial(std::move(material));
    }
    return material_indices;
}

void AppendUSDNode(
    const tinyusdz::tydra::Node& node,
    const tinyusdz::tydra::RenderScene& scene,
    const std::vector<uint32_t>& material_indices,
    PreviewBuild& build,
    bool* exceeded_limit
) {
    if (node.nodeType == tinyusdz::tydra::NodeType::Mesh && node.id >= 0 && static_cast<size_t>(node.id) < scene.meshes.size()) {
        const tinyusdz::tydra::RenderMesh& mesh = scene.meshes[static_cast<size_t>(node.id)];
        float color[4] = { mesh.displayColor[0], mesh.displayColor[1], mesh.displayColor[2], mesh.displayOpacity };
        uint32_t build_material_index = 0;
        const tinyusdz::tydra::UVTexture* uv_texture = nullptr;
        if (mesh.material_id >= 0 && static_cast<size_t>(mesh.material_id) < scene.materials.size()) {
            const auto& material = scene.materials[static_cast<size_t>(mesh.material_id)];
            color[0] = material.surfaceShader.diffuseColor.value[0];
            color[1] = material.surfaceShader.diffuseColor.value[1];
            color[2] = material.surfaceShader.diffuseColor.value[2];
            color[3] *= material.surfaceShader.opacity.value;
            build_material_index = material_indices[static_cast<size_t>(mesh.material_id)];
            int32_t uv_texture_id = material.surfaceShader.diffuseColor.texture_id;
            if (uv_texture_id < 0) uv_texture_id = material.surfaceShader.normal.texture_id;
            if (uv_texture_id >= 0 && static_cast<size_t>(uv_texture_id) < scene.textures.size()) {
                uv_texture = &scene.textures[static_cast<size_t>(uv_texture_id)];
            }
        }
        const std::vector<uint32_t>& indices = mesh.faceVertexIndices();
        const std::vector<uint32_t>& face_counts = mesh.faceVertexCounts();
        const tinyusdz::tydra::VertexAttribute* texcoords = nullptr;
        const auto texcoords_iterator = mesh.texcoords.find(0);
        if (texcoords_iterator != mesh.texcoords.end()) texcoords = &texcoords_iterator->second;
        size_t face_offset = 0;
        for (uint32_t face_count : face_counts) {
            if (face_offset + face_count > indices.size()) break;
            for (uint32_t triangle_index = 1; triangle_index + 1 < face_count; ++triangle_index) {
                const uint32_t corners[3] = { indices[face_offset], indices[face_offset + triangle_index], indices[face_offset + triangle_index + 1] };
                const size_t face_vertices[3] = { face_offset, face_offset + triangle_index, face_offset + triangle_index + 1 };
                for (size_t corner_index = 0; corner_index < 3; ++corner_index) {
                    const uint32_t corner = corners[corner_index];
                    if (corner >= mesh.points.size()) continue;
                    const auto& position = mesh.points[corner];
                    // TinyUSDZ matrices are row-major and USD multiplies points on the left.
                    const auto& matrix = node.global_matrix;
                    const float output_position[3] = {
                        static_cast<float>(position[0] * matrix.m[0][0] + position[1] * matrix.m[1][0] + position[2] * matrix.m[2][0] + matrix.m[3][0]),
                        static_cast<float>(position[0] * matrix.m[0][1] + position[1] * matrix.m[1][1] + position[2] * matrix.m[2][1] + matrix.m[3][1]),
                        static_cast<float>(position[0] * matrix.m[0][2] + position[1] * matrix.m[1][2] + position[2] * matrix.m[2][2] + matrix.m[3][2]),
                    };
                    float normal[3] = {};
                    float source_direction[3] = {};
                    if (ReadUSDAttribute(mesh.normals, corner, face_vertices[corner_index], 3, source_direction)) {
                        TransformUSDDirection(matrix, source_direction, normal);
                    }
                    float tangent[4] = {};
                    if (ReadUSDAttribute(mesh.tangents, corner, face_vertices[corner_index], 3, source_direction)) {
                        TransformUSDDirection(matrix, source_direction, tangent);
                    }
                    float bitangent[3] = {};
                    if (ReadUSDAttribute(mesh.binormals, corner, face_vertices[corner_index], 3, source_direction)) {
                        TransformUSDDirection(matrix, source_direction, bitangent);
                        float cross[3];
                        Cross3(normal, tangent, cross);
                        tangent[3] = Dot3(cross, bitangent) < 0.0f ? -1.0f : 1.0f;
                    }
                    float uv[2] = {};
                    if (texcoords) {
                        ReadUSDAttribute(*texcoords, corner, face_vertices[corner_index], 2, uv);
                        TransformUSDUV(uv_texture, uv);
                    }
                    float vertex_color[4] = { color[0], color[1], color[2], color[3] };
                    float sampled_color[3] = {};
                    if (ReadUSDAttribute(mesh.vertex_colors, corner, face_vertices[corner_index], 3, sampled_color)) {
                        vertex_color[0] *= sampled_color[0];
                        vertex_color[1] *= sampled_color[1];
                        vertex_color[2] *= sampled_color[2];
                    }
                    if (!build.AppendLit(output_position, normal, tangent, vertex_color, vertex_color, uv, build_material_index)) {
                        *exceeded_limit = true;
                        return;
                    }
                }
            }
            face_offset += face_count;
        }
    }
    for (const auto& child : node.children) {
        if (*exceeded_limit) return;
        AppendUSDNode(child, scene, material_indices, build, exceeded_limit);
    }
}

bool LoadUSD(const char* path, PreviewBuild& build, char* error, uint32_t error_capacity) {
    tinyusdz::USDLoadOptions options;
    options.load_assets = false;
    options.max_memory_limit_in_mb = 512;
    options.max_allowed_asset_size_in_mb = 64;

    tinyusdz::Stage stage;
    std::string warning;
    std::string load_error;
    if (!tinyusdz::LoadUSDFromFile(path, &stage, &warning, &load_error, options)) {
        SetError(error, error_capacity, load_error.empty() ? "Unable to parse the USD asset." : load_error);
        return false;
    }

    tinyusdz::tydra::RenderScene render_scene;
    tinyusdz::tydra::RenderSceneConverter converter;
    tinyusdz::tydra::RenderSceneConverterEnv environment(stage);
    environment.mesh_config.triangulate = true;
    environment.scene_config.load_texture_assets = true;
    environment.material_config.preserve_texel_bitdepth = true;
    environment.material_config.linearize_color_space = false;
    environment.usd_filename = path;
    environment.set_search_paths({ DirectoryOf(path) });
    if (!converter.ConvertToRenderScene(environment, &render_scene)) {
        SetError(error, error_capacity, converter.GetError());
        return false;
    }

    bool exceeded_limit = false;
    const std::vector<uint32_t> material_indices = BuildUSDMaterials(build, render_scene);
    for (const auto& node : render_scene.nodes) {
        AppendUSDNode(node, render_scene, material_indices, build, &exceeded_limit);
        if (exceeded_limit) {
            SetError(error, error_capacity, "The USD preview exceeds Vai's geometry safety limit.");
            return false;
        }
    }
    return true;
}

uint32_t ReadU32(const std::vector<uint8_t>& data, size_t offset) {
    if (offset + 4 > data.size()) return 0;
    return static_cast<uint32_t>(data[offset]) | (static_cast<uint32_t>(data[offset + 1]) << 8)
        | (static_cast<uint32_t>(data[offset + 2]) << 16) | (static_cast<uint32_t>(data[offset + 3]) << 24);
}

uint8_t ExpandMaskedColor(uint32_t value, uint32_t mask, uint8_t fallback) {
    if (mask == 0) return fallback;
    uint32_t shift = 0;
    while (((mask >> shift) & 1u) == 0u) ++shift;
    const uint32_t maximum = mask >> shift;
    return static_cast<uint8_t>((((value & mask) >> shift) * 255u + maximum / 2u) / maximum);
}

void Decode565(uint16_t value, uint8_t* rgba) {
    rgba[0] = static_cast<uint8_t>(((value >> 11) & 31) * 255 / 31);
    rgba[1] = static_cast<uint8_t>(((value >> 5) & 63) * 255 / 63);
    rgba[2] = static_cast<uint8_t>((value & 31) * 255 / 31);
    rgba[3] = 255;
}

void DecodeBC1Colors(const uint8_t* block, uint8_t colors[4][4], bool force_four_color) {
    const uint16_t c0 = static_cast<uint16_t>(block[0] | (block[1] << 8));
    const uint16_t c1 = static_cast<uint16_t>(block[2] | (block[3] << 8));
    Decode565(c0, colors[0]);
    Decode565(c1, colors[1]);
    if (c0 > c1 || force_four_color) {
        for (int channel = 0; channel < 3; ++channel) {
            colors[2][channel] = static_cast<uint8_t>((2 * colors[0][channel] + colors[1][channel]) / 3);
            colors[3][channel] = static_cast<uint8_t>((colors[0][channel] + 2 * colors[1][channel]) / 3);
        }
        colors[2][3] = colors[3][3] = 255;
    } else {
        for (int channel = 0; channel < 3; ++channel) colors[2][channel] = static_cast<uint8_t>((colors[0][channel] + colors[1][channel]) / 2);
        colors[2][3] = 255;
        std::memset(colors[3], 0, 4);
    }
}

void WriteBCColorBlock(const uint8_t* block, uint8_t* pixels, uint32_t width, uint32_t height, uint32_t bx, uint32_t by, bool force_four_color) {
    uint8_t colors[4][4];
    DecodeBC1Colors(block, colors, force_four_color);
    const uint32_t bits = static_cast<uint32_t>(block[4]) | (static_cast<uint32_t>(block[5]) << 8)
        | (static_cast<uint32_t>(block[6]) << 16) | (static_cast<uint32_t>(block[7]) << 24);
    for (uint32_t y = 0; y < 4; ++y) {
        for (uint32_t x = 0; x < 4; ++x) {
            const uint32_t pixel_x = bx * 4 + x;
            const uint32_t pixel_y = by * 4 + y;
            if (pixel_x >= width || pixel_y >= height) continue;
            const uint32_t index = (bits >> (2 * (y * 4 + x))) & 3u;
            std::memcpy(pixels + (pixel_y * width + pixel_x) * 4, colors[index], 4);
        }
    }
}

bool LoadDDS(const char* path, VaiImagePreview* out_image, char* error, uint32_t error_capacity) {
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream) {
        SetError(error, error_capacity, "Unable to open the DDS texture.");
        return false;
    }
    const std::streamsize file_size = stream.tellg();
    if (file_size < 128) {
        SetError(error, error_capacity, "The DDS texture header is truncated.");
        return false;
    }
    stream.seekg(0);
    std::vector<uint8_t> data(static_cast<size_t>(file_size));
    if (!stream.read(reinterpret_cast<char*>(data.data()), file_size)) {
        SetError(error, error_capacity, "Unable to read the DDS texture.");
        return false;
    }
    if (std::memcmp(data.data(), "DDS ", 4) != 0 || ReadU32(data, 4) != 124) {
        SetError(error, error_capacity, "The file is not a valid DDS texture.");
        return false;
    }

    const uint32_t height = ReadU32(data, 12);
    const uint32_t width = ReadU32(data, 16);
    if (width == 0 || height == 0 || width > 16384 || height > 16384 || static_cast<uint64_t>(width) * height * 4 > 256ull * 1024ull * 1024ull) {
        SetError(error, error_capacity, "The DDS texture dimensions exceed Vai's preview limit.");
        return false;
    }
    auto* pixels = static_cast<uint8_t*>(std::malloc(static_cast<size_t>(width) * height * 4));
    if (!pixels) {
        SetError(error, error_capacity, "Out of memory while decoding the DDS texture.");
        return false;
    }
    std::memset(pixels, 0, static_cast<size_t>(width) * height * 4);

    const uint32_t pixel_flags = ReadU32(data, 80);
    uint32_t fourcc = ReadU32(data, 84);
    uint32_t rgb_bits = ReadU32(data, 88);
    uint32_t r_mask = ReadU32(data, 92);
    uint32_t g_mask = ReadU32(data, 96);
    uint32_t b_mask = ReadU32(data, 100);
    uint32_t a_mask = ReadU32(data, 104);
    size_t source_offset = 128;
    enum class Compression { None, BC1, BC2, BC3 } compression = Compression::None;

    const uint32_t dxt1 = 0x31545844; // DXT1
    const uint32_t dxt3 = 0x33545844; // DXT3
    const uint32_t dxt5 = 0x35545844; // DXT5
    const uint32_t dx10 = 0x30315844; // DX10
    if (fourcc == dx10) {
        if (data.size() < source_offset + 20) {
            std::free(pixels);
            SetError(error, error_capacity, "The DDS DX10 header is truncated.");
            return false;
        }
        const uint32_t dxgi_format = ReadU32(data, source_offset);
        source_offset += 20;
        if (dxgi_format == 71 || dxgi_format == 72) compression = Compression::BC1;
        else if (dxgi_format == 74 || dxgi_format == 75) compression = Compression::BC2;
        else if (dxgi_format == 77 || dxgi_format == 78) compression = Compression::BC3;
        else if (dxgi_format == 28) { rgb_bits = 32; r_mask = 0x000000ff; g_mask = 0x0000ff00; b_mask = 0x00ff0000; a_mask = 0xff000000; }
        else if (dxgi_format == 87 || dxgi_format == 91) { rgb_bits = 32; r_mask = 0x00ff0000; g_mask = 0x0000ff00; b_mask = 0x000000ff; a_mask = 0xff000000; }
        else {
            std::free(pixels);
            SetError(error, error_capacity, "This DDS DXGI texture format is not previewable yet.");
            return false;
        }
    } else if (fourcc == dxt1) compression = Compression::BC1;
    else if (fourcc == dxt3) compression = Compression::BC2;
    else if (fourcc == dxt5) compression = Compression::BC3;

    if (compression != Compression::None) {
        const uint32_t blocks_x = (width + 3) / 4;
        const uint32_t blocks_y = (height + 3) / 4;
        const size_t block_bytes = compression == Compression::BC1 ? 8 : 16;
        if (source_offset + static_cast<size_t>(blocks_x) * blocks_y * block_bytes > data.size()) {
            std::free(pixels);
            SetError(error, error_capacity, "The DDS texture data is truncated.");
            return false;
        }
        for (uint32_t by = 0; by < blocks_y; ++by) for (uint32_t bx = 0; bx < blocks_x; ++bx) {
            const uint8_t* block = data.data() + source_offset + (static_cast<size_t>(by) * blocks_x + bx) * block_bytes;
            if (compression == Compression::BC1) {
                WriteBCColorBlock(block, pixels, width, height, bx, by, false);
            } else if (compression == Compression::BC2) {
                WriteBCColorBlock(block + 8, pixels, width, height, bx, by, true);
                for (uint32_t y = 0; y < 4; ++y) for (uint32_t x = 0; x < 4; ++x) {
                    const uint32_t px = bx * 4 + x, py = by * 4 + y;
                    if (px >= width || py >= height) continue;
                    const uint8_t alpha = static_cast<uint8_t>((block[y] >> (x * 4)) & 15u);
                    pixels[(py * width + px) * 4 + 3] = static_cast<uint8_t>(alpha * 17);
                }
            } else {
                WriteBCColorBlock(block + 8, pixels, width, height, bx, by, true);
                uint8_t alpha_values[8] = {block[0], block[1]};
                if (alpha_values[0] > alpha_values[1]) {
                    for (int i = 1; i <= 6; ++i) alpha_values[i + 1] = static_cast<uint8_t>(((7 - i) * alpha_values[0] + i * alpha_values[1]) / 7);
                } else {
                    for (int i = 1; i <= 4; ++i) alpha_values[i + 1] = static_cast<uint8_t>(((5 - i) * alpha_values[0] + i * alpha_values[1]) / 5);
                    alpha_values[6] = 0; alpha_values[7] = 255;
                }
                uint64_t alpha_bits = 0;
                for (int i = 0; i < 6; ++i) alpha_bits |= static_cast<uint64_t>(block[2 + i]) << (8 * i);
                for (uint32_t y = 0; y < 4; ++y) for (uint32_t x = 0; x < 4; ++x) {
                    const uint32_t px = bx * 4 + x, py = by * 4 + y;
                    if (px >= width || py >= height) continue;
                    const uint32_t index = static_cast<uint32_t>((alpha_bits >> (3 * (y * 4 + x))) & 7u);
                    pixels[(py * width + px) * 4 + 3] = alpha_values[index];
                }
            }
        }
    } else if ((pixel_flags & 0x40u) != 0 && (rgb_bits == 24 || rgb_bits == 32)) {
        const uint32_t bytes_per_pixel = rgb_bits / 8;
        const uint32_t packed_row_bytes = width * bytes_per_pixel;
        const uint32_t source_pitch = std::max(ReadU32(data, 20), packed_row_bytes);
        if (source_offset + static_cast<size_t>(source_pitch) * height > data.size()) {
            std::free(pixels);
            SetError(error, error_capacity, "The DDS texture data is truncated.");
            return false;
        }
        for (uint32_t y = 0; y < height; ++y) for (uint32_t x = 0; x < width; ++x) {
            uint32_t source_pixel = 0;
            const uint8_t* source = data.data() + source_offset + static_cast<size_t>(y) * source_pitch + x * bytes_per_pixel;
            for (uint32_t byte = 0; byte < bytes_per_pixel; ++byte) source_pixel |= static_cast<uint32_t>(source[byte]) << (byte * 8);
            uint8_t* destination = pixels + (static_cast<size_t>(y) * width + x) * 4;
            destination[0] = ExpandMaskedColor(source_pixel, r_mask, 0);
            destination[1] = ExpandMaskedColor(source_pixel, g_mask, 0);
            destination[2] = ExpandMaskedColor(source_pixel, b_mask, 0);
            destination[3] = ExpandMaskedColor(source_pixel, a_mask, 255);
        }
    } else {
        std::free(pixels);
        SetError(error, error_capacity, "This DDS texture encoding is not previewable yet.");
        return false;
    }

    out_image->pixels = pixels;
    out_image->width = width;
    out_image->height = height;
    out_image->row_stride = width * 4;
    return true;
}

float ReadHalf(const uint8_t* data) {
    const uint16_t bits = static_cast<uint16_t>(data[0] | (data[1] << 8));
    const float sign = (bits & 0x8000) ? -1.0f : 1.0f;
    const uint32_t exponent = (bits >> 10) & 31u;
    const uint32_t mantissa = bits & 1023u;
    if (exponent == 0) return sign * std::ldexp(static_cast<float>(mantissa), -24);
    if (exponent == 31) return mantissa ? NAN : sign * INFINITY;
    return sign * std::ldexp(1.0f + static_cast<float>(mantissa) / 1024.0f, static_cast<int>(exponent) - 15);
}

uint8_t FloatToPreviewByte(float value) {
    if (!std::isfinite(value) || value <= 0.0f) return 0;
    // EXR is normally linear HDR. Preserve 0..1 values and gently tone-map
    // brighter pixels instead of clipping the whole preview to white.
    if (value > 1.0f) value = value / (1.0f + value);
    value = std::pow(std::min(value, 1.0f), 1.0f / 2.2f);
    return static_cast<uint8_t>(std::lround(value * 255.0f));
}

uint8_t TinyUSDZSampleToByte(const tinyusdz::Image& image, size_t sample_index) {
    const size_t bytes_per_sample = static_cast<size_t>(image.bpp / 8);
    const uint8_t* sample = image.data.data() + sample_index * bytes_per_sample;
    if (image.format == tinyusdz::Image::PixelFormat::Float) {
        if (image.bpp == 16) return FloatToPreviewByte(ReadHalf(sample));
        if (image.bpp == 32) {
            float value = 0.0f;
            std::memcpy(&value, sample, sizeof(value));
            return FloatToPreviewByte(value);
        }
        return 0;
    }
    if (image.format == tinyusdz::Image::PixelFormat::UInt) {
        if (image.bpp == 8) return sample[0];
        if (image.bpp == 16) return static_cast<uint8_t>((static_cast<uint32_t>(sample[0] | (sample[1] << 8)) + 128u) / 257u);
        if (image.bpp == 32) {
            const uint32_t value = ReadU32(image.data, sample_index * bytes_per_sample);
            return static_cast<uint8_t>((static_cast<uint64_t>(value) * 255u + 0x7fffffffu) / 0xffffffffu);
        }
        return 0;
    }
    // Signed DNG/TIFF values are uncommon in texture workflows; show their
    // non-negative range instead of interpreting their bytes as unsigned.
    if (image.bpp == 8) return sample[0] < 128 ? 0 : static_cast<uint8_t>((sample[0] - 128) * 2);
    if (image.bpp == 16) {
        const int16_t value = static_cast<int16_t>(sample[0] | (sample[1] << 8));
        return value <= 0 ? 0 : static_cast<uint8_t>(std::min(255, value / 128));
    }
    return 0;
}

bool LoadHighPrecisionImage(const char* path, VaiImagePreview* out_image, char* error, uint32_t error_capacity) {
    auto loaded = tinyusdz::image::LoadImageFromFile(path, 256);
    if (!loaded) {
        SetError(error, error_capacity, loaded.error());
        return false;
    }
    const tinyusdz::Image& image = loaded.value().image;
    if (image.width <= 0 || image.height <= 0 || image.channels <= 0 || image.channels > 4
        || (image.bpp != 8 && image.bpp != 16 && image.bpp != 32)) {
        SetError(error, error_capacity, "The image has an unsupported pixel layout.");
        return false;
    }
    const uint64_t pixel_count = static_cast<uint64_t>(image.width) * static_cast<uint64_t>(image.height);
    const uint64_t source_bytes = pixel_count * static_cast<uint64_t>(image.channels) * static_cast<uint64_t>(image.bpp / 8);
    if (pixel_count > 64ull * 1024ull * 1024ull || source_bytes > image.data.size()) {
        SetError(error, error_capacity, "The image dimensions exceed Vai's preview limit.");
        return false;
    }
    auto* pixels = static_cast<uint8_t*>(std::malloc(static_cast<size_t>(pixel_count) * 4));
    if (!pixels) {
        SetError(error, error_capacity, "Out of memory while decoding the image.");
        return false;
    }
    for (uint64_t pixel = 0; pixel < pixel_count; ++pixel) {
        const size_t source = static_cast<size_t>(pixel) * image.channels;
        uint8_t* destination = pixels + pixel * 4;
        for (int channel = 0; channel < 4; ++channel) {
            int source_channel = channel;
            if (image.channels == 1 && channel < 3) source_channel = 0;
            if (image.channels == 2 && channel < 3) source_channel = 0;
            if (source_channel >= image.channels) {
                destination[channel] = channel == 3 ? 255 : 0;
            } else {
                destination[channel] = TinyUSDZSampleToByte(image, source + source_channel);
            }
        }
    }
    out_image->pixels = pixels;
    out_image->width = static_cast<uint32_t>(image.width);
    out_image->height = static_cast<uint32_t>(image.height);
    out_image->row_stride = static_cast<uint32_t>(image.width) * 4;
    return true;
}

bool LoadEXRImage(const char* path, VaiImagePreview* out_image, char* error, uint32_t error_capacity) {
    float* source = nullptr;
    int width = 0;
    int height = 0;
    const char* exr_error = nullptr;
    const int result = LoadEXR(&source, &width, &height, path, &exr_error);
    if (result != TINYEXR_SUCCESS || !source || width <= 0 || height <= 0
        || static_cast<uint64_t>(width) * static_cast<uint64_t>(height) > 64ull * 1024ull * 1024ull) {
        SetError(error, error_capacity, exr_error ? exr_error : "Unable to decode the OpenEXR texture.");
        if (exr_error) FreeEXRErrorMessage(exr_error);
        if (source) std::free(source);
        return false;
    }
    auto* pixels = static_cast<uint8_t*>(std::malloc(static_cast<size_t>(width) * height * 4));
    if (!pixels) {
        std::free(source);
        if (exr_error) FreeEXRErrorMessage(exr_error);
        SetError(error, error_capacity, "Out of memory while decoding the OpenEXR texture.");
        return false;
    }
    const size_t pixel_count = static_cast<size_t>(width) * height;
    for (size_t pixel = 0; pixel < pixel_count; ++pixel) {
        for (int channel = 0; channel < 4; ++channel) {
            pixels[pixel * 4 + channel] = FloatToPreviewByte(source[pixel * 4 + channel]);
        }
    }
    std::free(source);
    if (exr_error) FreeEXRErrorMessage(exr_error);
    out_image->pixels = pixels;
    out_image->width = static_cast<uint32_t>(width);
    out_image->height = static_cast<uint32_t>(height);
    out_image->row_stride = static_cast<uint32_t>(width) * 4;
    return true;
}

int VAI_SCENE_PREVIEW_CALL CanPreview(const char* utf8_path) {
    return IsBuiltinExtension(ExtensionOf(utf8_path)) ? 1 : 0;
}

bool BuildScene(const char* utf8_path, PreviewBuild& build, char* error, uint32_t error_capacity) {
    const std::string extension = ExtensionOf(utf8_path);
    if (extension == "gltf" || extension == "glb") {
        return LoadGLTF(utf8_path, build, error, error_capacity);
    }
    if (extension == "fbx" || extension == "obj") {
        return LoadFBX(utf8_path, build, error, error_capacity);
    }
    if (extension == "usd" || extension == "usda" || extension == "usdc" || extension == "usdz") {
        return LoadUSD(utf8_path, build, error, error_capacity);
    }
    SetError(error, error_capacity, "This provider does not support the selected file type.");
    return false;
}

int VAI_SCENE_PREVIEW_CALL LoadScene(const char* utf8_path, VaiScenePreviewMesh* out_mesh, char* error, uint32_t error_capacity) {
    if (!utf8_path || !out_mesh) {
        SetError(error, error_capacity, "The scene preview provider received invalid arguments.");
        return 0;
    }
    *out_mesh = {};
    PreviewBuild build;
    return BuildScene(utf8_path, build, error, error_capacity)
        && build.Finalize(out_mesh, error, error_capacity) ? 1 : 0;
}

int VAI_SCENE_PREVIEW_CALL LoadLitScene(const char* utf8_path, VaiLitScenePreviewMesh* out_mesh, char* error, uint32_t error_capacity) {
    if (!utf8_path || !out_mesh) {
        SetError(error, error_capacity, "The lit scene preview provider received invalid arguments.");
        return 0;
    }
    *out_mesh = {};
    PreviewBuild build;
    return BuildScene(utf8_path, build, error, error_capacity)
        && build.FinalizeLit(out_mesh, error, error_capacity) ? 1 : 0;
}

int VAI_SCENE_PREVIEW_CALL LoadImage(const char* utf8_path, VaiImagePreview* out_image, char* error, uint32_t error_capacity) {
    if (!utf8_path || !out_image) {
        SetError(error, error_capacity, "This provider does not support the selected texture type.");
        return 0;
    }
    *out_image = {};
    const std::string extension = ExtensionOf(utf8_path);
    if (extension == "dds") return LoadDDS(utf8_path, out_image, error, error_capacity) ? 1 : 0;
    if (extension == "exr") return LoadEXRImage(utf8_path, out_image, error, error_capacity) ? 1 : 0;
    if (extension == "tif" || extension == "tiff" || extension == "dng") {
        return LoadHighPrecisionImage(utf8_path, out_image, error, error_capacity) ? 1 : 0;
    }
    SetError(error, error_capacity, "This provider does not support the selected texture type.");
    return 0;
}

void VAI_SCENE_PREVIEW_CALL ReleaseScene(VaiScenePreviewMesh* mesh) {
    if (!mesh) return;
    std::free(const_cast<VaiScenePreviewVertex*>(mesh->vertices));
    *mesh = {};
}

void VAI_SCENE_PREVIEW_CALL ReleaseLitScene(VaiLitScenePreviewMesh* mesh) {
    if (!mesh) return;
    if (mesh->materials) {
        for (uint32_t index = 0; index < mesh->material_count; ++index) {
            std::free(const_cast<uint8_t*>(mesh->materials[index].base_color_texture.pixels));
            std::free(const_cast<uint8_t*>(mesh->materials[index].normal_texture.pixels));
        }
    }
    std::free(const_cast<VaiLitScenePreviewVertex*>(mesh->vertices));
    std::free(const_cast<VaiLitScenePreviewMaterial*>(mesh->materials));
    std::free(const_cast<VaiLitScenePreviewDrawRange*>(mesh->draw_ranges));
    *mesh = {};
}

void VAI_SCENE_PREVIEW_CALL ReleaseImage(VaiImagePreview* image) {
    if (!image) return;
    std::free(const_cast<uint8_t*>(image->pixels));
    *image = {};
}

const VaiScenePreviewProvider kProvider = {
    VAI_SCENE_PREVIEW_ABI_VERSION,
    sizeof(VaiScenePreviewProvider),
    "Vai built-in scene formats",
    "gltf;glb;fbx;obj;usd;usda;usdc;usdz;dds;exr;tif;tiff;dng",
    CanPreview,
    LoadScene,
    ReleaseScene,
    LoadImage,
    ReleaseImage,
    "gltf;glb;fbx;obj;usd;usda;usdc;usdz",
    "dds;exr;tif;tiff;dng",
    LoadLitScene,
    ReleaseLitScene,
};

} // namespace

VAI_SCENE_PREVIEW_EXPORT const VaiScenePreviewProvider* VAI_SCENE_PREVIEW_CALL
Vai_Get_Scene_Preview_Provider(uint32_t host_abi_version) {
    return host_abi_version == VAI_SCENE_PREVIEW_ABI_VERSION ? &kProvider : nullptr;
}
