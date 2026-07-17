#define CGLTF_IMPLEMENTATION
#include "../third_party/cgltf/cgltf.h"

#include "../third_party/ufbx/ufbx.h"
#include "../third_party/tinyusdz/src/tinyusdz.hh"
#include "../third_party/tinyusdz/src/image-loader.hh"
#include "../third_party/tinyusdz/src/external/tinyexr.h"
#include "../third_party/tinyusdz/src/tydra/render-data.hh"
#include "vai_scene_preview_api.h"

#include <algorithm>
#include <cctype>
#include <cfloat>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

namespace {

constexpr uint32_t kMaxPreviewVertices = 3u * 1024u * 1024u;

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

struct PreviewBuild {
    std::vector<VaiScenePreviewVertex> vertices;
    float bounds_min[3] = { FLT_MAX, FLT_MAX, FLT_MAX };
    float bounds_max[3] = { -FLT_MAX, -FLT_MAX, -FLT_MAX };

    bool Append(float x, float y, float z, const float color[4]) {
        if (vertices.size() >= kMaxPreviewVertices) return false;
        VaiScenePreviewVertex vertex = {{ x, y, z }, { color[0], color[1], color[2], color[3] }};
        vertices.push_back(vertex);
        bounds_min[0] = std::min(bounds_min[0], x);
        bounds_min[1] = std::min(bounds_min[1], y);
        bounds_min[2] = std::min(bounds_min[2], z);
        bounds_max[0] = std::max(bounds_max[0], x);
        bounds_max[1] = std::max(bounds_max[1], y);
        bounds_max[2] = std::max(bounds_max[2], z);
        return true;
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
        std::memcpy(allocated_vertices, vertices.data(), byte_count);
        out_mesh->vertices = allocated_vertices;
        out_mesh->vertex_count = static_cast<uint32_t>(vertices.size());
        std::memcpy(out_mesh->bounds_min, bounds_min, sizeof(bounds_min));
        std::memcpy(out_mesh->bounds_max, bounds_max, sizeof(bounds_max));
        return true;
    }
};

bool AppendGLTFPrimitive(PreviewBuild& build, const cgltf_node* node, const cgltf_primitive& primitive) {
    if (primitive.type != cgltf_primitive_type_triangles) return true;

    const cgltf_accessor* positions = nullptr;
    const cgltf_accessor* colors = nullptr;
    for (cgltf_size attribute_index = 0; attribute_index < primitive.attributes_count; ++attribute_index) {
        const cgltf_attribute& attribute = primitive.attributes[attribute_index];
        if (attribute.type == cgltf_attribute_type_position) positions = attribute.data;
        if (attribute.type == cgltf_attribute_type_color && attribute.index == 0) colors = attribute.data;
    }
    if (!positions || positions->count == 0) return true;

    float transform[16];
    cgltf_node_transform_world(node, transform);
    float material_color[4] = { 0.78f, 0.80f, 0.84f, 1.0f };
    if (primitive.material) {
        std::memcpy(material_color, primitive.material->pbr_metallic_roughness.base_color_factor, sizeof(material_color));
    }

    const cgltf_size index_count = primitive.indices ? primitive.indices->count : positions->count;
    const cgltf_size triangle_count = index_count / 3;
    for (cgltf_size triangle = 0; triangle < triangle_count; ++triangle) {
        for (cgltf_size corner = 0; corner < 3; ++corner) {
            const cgltf_size element = triangle * 3 + corner;
            const cgltf_size vertex_index = primitive.indices ? cgltf_accessor_read_index(primitive.indices, element) : element;
            if (vertex_index >= positions->count) continue;

            float position[3] = {};
            if (!cgltf_accessor_read_float(positions, vertex_index, position, 3)) continue;
            float color[4] = { material_color[0], material_color[1], material_color[2], material_color[3] };
            if (colors && vertex_index < colors->count) {
                const cgltf_size component_count = std::min<cgltf_size>(4, cgltf_num_components(colors->type));
                float vertex_color[4] = { 1, 1, 1, 1 };
                if (cgltf_accessor_read_float(colors, vertex_index, vertex_color, component_count)) {
                    for (int component = 0; component < 4; ++component) color[component] *= vertex_color[component];
                }
            }

            const float x = transform[0] * position[0] + transform[4] * position[1] + transform[8]  * position[2] + transform[12];
            const float y = transform[1] * position[0] + transform[5] * position[1] + transform[9]  * position[2] + transform[13];
            const float z = transform[2] * position[0] + transform[6] * position[1] + transform[10] * position[2] + transform[14];
            if (!build.Append(x, y, z, color)) return false;
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

    for (cgltf_size node_index = 0; node_index < data->nodes_count; ++node_index) {
        const cgltf_node& node = data->nodes[node_index];
        if (!node.mesh) continue;
        for (cgltf_size primitive_index = 0; primitive_index < node.mesh->primitives_count; ++primitive_index) {
            if (!AppendGLTFPrimitive(build, &node, node.mesh->primitives[primitive_index])) {
                free_data();
                SetError(error, error_capacity, "The glTF preview exceeds Vai's geometry safety limit.");
                return false;
            }
        }
    }
    free_data();
    return true;
}

void FBXMaterialColor(const ufbx_node* node, const ufbx_mesh* mesh, size_t face_index, float color[4]) {
    color[0] = 0.78f; color[1] = 0.80f; color[2] = 0.84f; color[3] = 1.0f;
    if (mesh->face_material.count == 0 || face_index >= mesh->face_material.count) return;
    const uint32_t material_index = mesh->face_material.data[face_index];
    const ufbx_material_list& materials = node->materials.count ? node->materials : mesh->materials;
    if (material_index >= materials.count || !materials.data[material_index]) return;
    const ufbx_material* material = materials.data[material_index];
    const ufbx_material_map& map = material->pbr.base_color.has_value
        ? material->pbr.base_color : material->fbx.diffuse_color;
    if (!map.has_value) return;
    color[0] = static_cast<float>(map.value_vec3.x);
    color[1] = static_cast<float>(map.value_vec3.y);
    color[2] = static_cast<float>(map.value_vec3.z);
}

bool LoadFBX(const char* path, PreviewBuild& build, char* error, uint32_t error_capacity) {
    ufbx_load_opts options = {};
    options.ignore_missing_external_files = true;
    options.generate_missing_normals = true;
    options.use_blender_pbr_material = true;
    ufbx_error load_error = {};
    ufbx_scene* scene = ufbx_load_file(path, &options, &load_error);
    if (!scene) {
        char ufbx_error[512] = {};
        ufbx_format_error(ufbx_error, sizeof(ufbx_error), &load_error);
        SetError(error, error_capacity, ufbx_error);
        return false;
    }

    std::vector<uint32_t> triangle_indices;
    for (size_t node_index = 0; node_index < scene->nodes.count; ++node_index) {
        const ufbx_node* node = scene->nodes.data[node_index];
        if (!node || !node->mesh || !node->visible) continue;
        const ufbx_mesh* mesh = node->mesh;
        triangle_indices.resize(mesh->max_face_triangles * 3);
        for (size_t face_index = 0; face_index < mesh->num_faces; ++face_index) {
            const size_t triangle_count = ufbx_triangulate_face(triangle_indices.data(), triangle_indices.size(), mesh, mesh->faces.data[face_index]);
            float color[4];
            FBXMaterialColor(node, mesh, face_index, color);
            for (size_t triangle = 0; triangle < triangle_count; ++triangle) {
                for (size_t corner = 0; corner < 3; ++corner) {
                    const uint32_t index = triangle_indices[triangle * 3 + corner];
                    if (index >= mesh->skinned_position.indices.count) continue;
                    ufbx_vec3 position = ufbx_get_vertex_vec3(&mesh->skinned_position, index);
                    if (mesh->skinned_is_local) position = ufbx_transform_position(&node->geometry_to_world, position);
                    if (!build.Append(static_cast<float>(position.x), static_cast<float>(position.y), static_cast<float>(position.z), color)) {
                        ufbx_free_scene(scene);
                        SetError(error, error_capacity, "The FBX preview exceeds Vai's geometry safety limit.");
                        return false;
                    }
                }
            }
        }
    }
    ufbx_free_scene(scene);
    return true;
}

void AppendUSDNode(const tinyusdz::tydra::Node& node, const tinyusdz::tydra::RenderScene& scene, PreviewBuild& build, bool* exceeded_limit) {
    if (node.nodeType == tinyusdz::tydra::NodeType::Mesh && node.id >= 0 && static_cast<size_t>(node.id) < scene.meshes.size()) {
        const tinyusdz::tydra::RenderMesh& mesh = scene.meshes[static_cast<size_t>(node.id)];
        float color[4] = { mesh.displayColor[0], mesh.displayColor[1], mesh.displayColor[2], mesh.displayOpacity };
        if (mesh.material_id >= 0 && static_cast<size_t>(mesh.material_id) < scene.materials.size()) {
            const auto& material = scene.materials[static_cast<size_t>(mesh.material_id)];
            color[0] = material.surfaceShader.diffuseColor.value[0];
            color[1] = material.surfaceShader.diffuseColor.value[1];
            color[2] = material.surfaceShader.diffuseColor.value[2];
            color[3] *= material.surfaceShader.opacity.value;
        }
        const std::vector<uint32_t>& indices = mesh.faceVertexIndices();
        const std::vector<uint32_t>& face_counts = mesh.faceVertexCounts();
        size_t face_offset = 0;
        for (uint32_t face_count : face_counts) {
            if (face_offset + face_count > indices.size()) break;
            for (uint32_t triangle_index = 1; triangle_index + 1 < face_count; ++triangle_index) {
                const uint32_t corners[3] = { indices[face_offset], indices[face_offset + triangle_index], indices[face_offset + triangle_index + 1] };
                for (uint32_t corner : corners) {
                    if (corner >= mesh.points.size()) continue;
                    const auto& position = mesh.points[corner];
                    // TinyUSDZ matrices are row-major and USD multiplies points on the left.
                    const auto& matrix = node.global_matrix;
                    const float x = static_cast<float>(position[0] * matrix.m[0][0] + position[1] * matrix.m[1][0] + position[2] * matrix.m[2][0] + matrix.m[3][0]);
                    const float y = static_cast<float>(position[0] * matrix.m[0][1] + position[1] * matrix.m[1][1] + position[2] * matrix.m[2][1] + matrix.m[3][1]);
                    const float z = static_cast<float>(position[0] * matrix.m[0][2] + position[1] * matrix.m[1][2] + position[2] * matrix.m[2][2] + matrix.m[3][2]);
                    if (!build.Append(x, y, z, color)) {
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
        AppendUSDNode(child, scene, build, exceeded_limit);
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
    environment.scene_config.load_texture_assets = false;
    if (!converter.ConvertToRenderScene(environment, &render_scene)) {
        SetError(error, error_capacity, converter.GetError());
        return false;
    }

    bool exceeded_limit = false;
    for (const auto& node : render_scene.nodes) {
        AppendUSDNode(node, render_scene, build, &exceeded_limit);
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

int VAI_SCENE_PREVIEW_CALL LoadScene(const char* utf8_path, VaiScenePreviewMesh* out_mesh, char* error, uint32_t error_capacity) {
    if (!utf8_path || !out_mesh) {
        SetError(error, error_capacity, "The scene preview provider received invalid arguments.");
        return 0;
    }
    *out_mesh = {};
    PreviewBuild build;
    const std::string extension = ExtensionOf(utf8_path);
    bool loaded = false;
    if (extension == "gltf" || extension == "glb") {
        loaded = LoadGLTF(utf8_path, build, error, error_capacity);
    } else if (extension == "fbx" || extension == "obj") {
        loaded = LoadFBX(utf8_path, build, error, error_capacity);
    } else if (extension == "usd" || extension == "usda" || extension == "usdc" || extension == "usdz") {
        loaded = LoadUSD(utf8_path, build, error, error_capacity);
    } else {
        SetError(error, error_capacity, "This provider does not support the selected file type.");
        return 0;
    }
    return loaded && build.Finalize(out_mesh, error, error_capacity) ? 1 : 0;
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
};

} // namespace

VAI_SCENE_PREVIEW_EXPORT const VaiScenePreviewProvider* VAI_SCENE_PREVIEW_CALL
Vai_Get_Scene_Preview_Provider(uint32_t host_abi_version) {
    return host_abi_version == VAI_SCENE_PREVIEW_ABI_VERSION ? &kProvider : nullptr;
}
