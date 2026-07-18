#include "vai_scene_preview_api.h"
#include "tinyexr.h"

#include <windows.h>

#include <cmath>
#include <cstddef>
#include <cstring>
#include <cstdio>
#include <fstream>
#include <vector>

namespace {

void WriteU32(std::vector<unsigned char>& bytes, size_t offset, unsigned value) {
    bytes[offset + 0] = static_cast<unsigned char>(value);
    bytes[offset + 1] = static_cast<unsigned char>(value >> 8);
    bytes[offset + 2] = static_cast<unsigned char>(value >> 16);
    bytes[offset + 3] = static_cast<unsigned char>(value >> 24);
}

void WriteU16(std::vector<unsigned char>& bytes, size_t offset, unsigned value) {
    bytes[offset + 0] = static_cast<unsigned char>(value);
    bytes[offset + 1] = static_cast<unsigned char>(value >> 8);
}

bool WriteDDSFixture(const char* path) {
    std::vector<unsigned char> bytes(128 + 16, 0);
    bytes[0] = 'D'; bytes[1] = 'D'; bytes[2] = 'S'; bytes[3] = ' ';
    WriteU32(bytes, 4, 124);
    WriteU32(bytes, 8, 0x0002100f); // caps, height, width, pitch, pixel format
    WriteU32(bytes, 12, 2);
    WriteU32(bytes, 16, 2);
    WriteU32(bytes, 20, 8);
    WriteU32(bytes, 76, 32);
    WriteU32(bytes, 80, 0x41); // RGB + alpha
    WriteU32(bytes, 88, 32);
    WriteU32(bytes, 92, 0x000000ff);
    WriteU32(bytes, 96, 0x0000ff00);
    WriteU32(bytes, 100, 0x00ff0000);
    WriteU32(bytes, 104, 0xff000000);
    WriteU32(bytes, 108, 0x1000);
    const unsigned char pixels[] = {
        255, 0, 0, 255,    0, 255, 0, 255,
        0, 0, 255, 255,    255, 255, 255, 255,
    };
    std::memcpy(bytes.data() + 128, pixels, sizeof(pixels));
    std::ofstream output(path, std::ios::binary);
    output.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    return output.good();
}

bool WriteBC1DDSFixture(const char* path) {
    std::vector<unsigned char> bytes(128 + 8, 0);
    bytes[0] = 'D'; bytes[1] = 'D'; bytes[2] = 'S'; bytes[3] = ' ';
    WriteU32(bytes, 4, 124);
    WriteU32(bytes, 8, 0x00081007); // caps, height, width, linear size, pixel format
    WriteU32(bytes, 12, 4);
    WriteU32(bytes, 16, 4);
    WriteU32(bytes, 20, 8);
    WriteU32(bytes, 76, 32);
    WriteU32(bytes, 80, 4); // DDPF_FOURCC
    WriteU32(bytes, 84, 0x31545844); // DXT1
    WriteU32(bytes, 108, 0x1000);
    bytes[128] = 0x00; bytes[129] = 0xf8; // red in RGB565
    bytes[130] = 0xe0; bytes[131] = 0x07; // green in RGB565
    std::ofstream output(path, std::ios::binary);
    output.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    return output.good();
}

bool WriteTIFFFixture(const char* path) {
    // A minimal 2x1, uncompressed RGB TIFF. Keeping this generated avoids
    // carrying image test assets solely for the native provider smoke test.
    std::vector<unsigned char> bytes(146, 0);
    bytes[0] = 'I'; bytes[1] = 'I';
    WriteU16(bytes, 2, 42);
    WriteU32(bytes, 4, 8);
    WriteU16(bytes, 8, 10);
    const auto entry = [&bytes](unsigned index, unsigned tag, unsigned type, unsigned count, unsigned value) {
        const size_t offset = 10 + index * 12;
        WriteU16(bytes, offset, tag);
        WriteU16(bytes, offset + 2, type);
        WriteU32(bytes, offset + 4, count);
        WriteU32(bytes, offset + 8, value);
    };
    entry(0, 256, 4, 1, 2);    // ImageWidth
    entry(1, 257, 4, 1, 1);    // ImageLength
    entry(2, 258, 3, 3, 134);  // BitsPerSample
    entry(3, 259, 3, 1, 1);    // Compression: none
    entry(4, 262, 3, 1, 2);    // RGB
    entry(5, 273, 4, 1, 140);  // StripOffsets
    entry(6, 277, 3, 1, 3);    // SamplesPerPixel
    entry(7, 278, 4, 1, 1);    // RowsPerStrip
    entry(8, 279, 4, 1, 6);    // StripByteCounts
    entry(9, 284, 3, 1, 1);    // PlanarConfiguration: chunky
    WriteU32(bytes, 130, 0);
    WriteU16(bytes, 134, 8); WriteU16(bytes, 136, 8); WriteU16(bytes, 138, 8);
    bytes[140] = 255; bytes[141] = 0; bytes[142] = 0;
    bytes[143] = 0; bytes[144] = 255; bytes[145] = 0;
    std::ofstream output(path, std::ios::binary);
    output.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    return output.good();
}

bool WriteEXRFixture(const char* path) {
    const float pixels[] = {0.5f, 0.25f, 1.0f, 1.0f};
    const char* error = nullptr;
    const int result = SaveEXR(pixels, 1, 1, 4, 0, path, &error);
    if (error) FreeEXRErrorMessage(error);
    return result == TINYEXR_SUCCESS;
}

bool WriteOBJMaterialFixture(const char* obj_path, const char* mtl_path) {
    constexpr const char* obj =
        "mtllib preview-smoke.mtl\n"
        "o triangle\n"
        "v 0 0 0\n"
        "v 1 0 0\n"
        "v 0 1 0\n"
        "usemtl smoke\n"
        "f 1 2 3\n";
    constexpr const char* mtl =
        "newmtl smoke\n"
        "Kd 0.25 0.50 0.75\n"
        "d 1.0\n"
        "illum 1\n";
    std::ofstream obj_output(obj_path, std::ios::binary);
    obj_output.write(obj, static_cast<std::streamsize>(std::strlen(obj)));
    obj_output.close();
    std::ofstream mtl_output(mtl_path, std::ios::binary);
    mtl_output.write(mtl, static_cast<std::streamsize>(std::strlen(mtl)));
    return obj_output.good() && mtl_output.good();
}

bool TestOBJMaterial(const VaiScenePreviewProvider* provider) {
    constexpr const char* obj_path = ".build/native_preview/preview-smoke.obj";
    constexpr const char* mtl_path = ".build/native_preview/preview-smoke.mtl";
    if (!WriteOBJMaterialFixture(obj_path, mtl_path)) {
        std::fprintf(stderr, "could not prepare the OBJ/MTL smoke fixture\n");
        return false;
    }

    char error[1024] = {};
    VaiScenePreviewMesh mesh = {};
    const bool loaded = provider->can_preview(obj_path) && provider->load_scene(obj_path, &mesh, error, sizeof(error));
    bool valid = loaded && mesh.vertices && mesh.vertex_count == 3;
    constexpr float expected[3] = { 0.25f, 0.50f, 0.75f };
    if (valid) {
        for (uint32_t vertex_index = 0; vertex_index < mesh.vertex_count; ++vertex_index) {
            for (size_t channel = 0; channel < 3; ++channel) {
                if (std::fabs(mesh.vertices[vertex_index].color[channel] - expected[channel]) > 0.0001f) {
                    valid = false;
                }
            }
        }
    }
    if (!valid) {
        std::fprintf(stderr, "OBJ material preview failed: %s\n", error[0] ? error : "unexpected material color");
    } else {
        std::printf("previewed OBJ/MTL smoke fixture (RGB 0.25 0.50 0.75)\n");
    }
    if (loaded) provider->release_scene(&mesh);
    return valid;
}

bool TestLitScene(const VaiScenePreviewProvider* provider, const char* scene_path) {
    constexpr size_t lit_api_size = offsetof(VaiScenePreviewProvider, release_lit_scene)
        + sizeof(VaiLitScenePreviewReleaseFn);
    if (provider->struct_size < lit_api_size || !provider->load_lit_scene || !provider->release_lit_scene) {
        return true;
    }

    char error[1024] = {};
    VaiLitScenePreviewMesh mesh = {};
    const bool loaded = provider->load_lit_scene(scene_path, &mesh, error, sizeof(error)) != 0;
    bool valid = loaded && mesh.vertices && mesh.vertex_count >= 3 && mesh.vertex_count % 3 == 0
        && mesh.materials && mesh.material_count > 0
        && mesh.draw_ranges && mesh.draw_range_count > 0;
    uint32_t nonzero_normals = 0;
    uint32_t base_textures = 0;
    uint32_t normal_textures = 0;
    if (valid) {
        for (uint32_t vertex_index = 0; vertex_index < mesh.vertex_count; ++vertex_index) {
            const VaiLitScenePreviewVertex& vertex = mesh.vertices[vertex_index];
            const float length_squared = vertex.normal[0]*vertex.normal[0]
                + vertex.normal[1]*vertex.normal[1] + vertex.normal[2]*vertex.normal[2];
            if (std::isfinite(length_squared) && length_squared > 0.25f) ++nonzero_normals;
        }
        for (uint32_t material_index = 0; material_index < mesh.material_count; ++material_index) {
            const VaiLitScenePreviewMaterial& material = mesh.materials[material_index];
            if (material.flags & VAI_SCENE_MATERIAL_BASE_COLOR_TEXTURE) ++base_textures;
            if (material.flags & VAI_SCENE_MATERIAL_NORMAL_TEXTURE) ++normal_textures;
        }
        for (uint32_t range_index = 0; range_index < mesh.draw_range_count; ++range_index) {
            const VaiLitScenePreviewDrawRange& range = mesh.draw_ranges[range_index];
            if (range.vertex_count == 0
            || static_cast<uint64_t>(range.first_vertex) + range.vertex_count > mesh.vertex_count
            || range.material_index >= mesh.material_count) {
                valid = false;
            }
        }
        valid = valid && nonzero_normals == mesh.vertex_count;
    }
    if (!valid) {
        std::fprintf(stderr, "lit preview failed for %s: %s\n", scene_path, error[0] ? error : "invalid lit mesh");
    } else {
        std::printf(
            "lit previewed %s (%u materials, %u ranges, %u base textures, %u normal textures)\n",
            scene_path, mesh.material_count, mesh.draw_range_count, base_textures, normal_textures);
    }
    if (loaded) provider->release_lit_scene(&mesh);
    return valid;
}

bool TestScene(const VaiScenePreviewProvider* provider, const char* scene_path) {
    char error[1024] = {};
    VaiScenePreviewMesh mesh = {};
    const bool supported = provider->can_preview(scene_path) != 0;
    const bool loaded = supported && provider->load_scene(scene_path, &mesh, error, sizeof(error)) != 0;
    const bool valid = loaded && mesh.vertices && mesh.vertex_count >= 3 && mesh.vertex_count % 3 == 0
        && std::isfinite(mesh.bounds_min[0]) && std::isfinite(mesh.bounds_max[0]);
    if (!valid) {
        std::fprintf(stderr, "preview failed for %s: %s\n", scene_path, error[0] ? error : "invalid triangle list");
        return false;
    }
    float color_min[3] = { mesh.vertices[0].color[0], mesh.vertices[0].color[1], mesh.vertices[0].color[2] };
    float color_max[3] = { color_min[0], color_min[1], color_min[2] };
    for (uint32_t vertex_index = 1; vertex_index < mesh.vertex_count; ++vertex_index) {
        for (size_t channel = 0; channel < 3; ++channel) {
            const float value = mesh.vertices[vertex_index].color[channel];
            if (value < color_min[channel]) color_min[channel] = value;
            if (value > color_max[channel]) color_max[channel] = value;
        }
    }
    std::printf(
        "previewed %s (%u vertices, RGB %.3f %.3f %.3f to %.3f %.3f %.3f)\n",
        scene_path,
        mesh.vertex_count,
        color_min[0], color_min[1], color_min[2],
        color_max[0], color_max[1], color_max[2]);
    provider->release_scene(&mesh);
    return TestLitScene(provider, scene_path);
}

bool TestDDS(const VaiScenePreviewProvider* provider) {
    constexpr const char* dds_path = ".build/native_preview/preview-smoke.dds";
    constexpr const char* bc1_dds_path = ".build/native_preview/preview-smoke-bc1.dds";
    if (!provider->load_image || !provider->release_image || !WriteDDSFixture(dds_path) || !WriteBC1DDSFixture(bc1_dds_path)) {
        std::fprintf(stderr, "could not prepare the DDS smoke fixture\n");
        return false;
    }
    char error[1024] = {};
    VaiImagePreview image = {};
    const bool loaded = provider->can_preview(dds_path) && provider->load_image(dds_path, &image, error, sizeof(error));
    const bool valid = loaded && image.pixels && image.width == 2 && image.height == 2 && image.row_stride == 8
        && image.pixels[0] == 255 && image.pixels[1] == 0 && image.pixels[2] == 0;
    if (!valid) {
        std::fprintf(stderr, "DDS preview failed: %s\n", error[0] ? error : "unexpected pixels");
        return false;
    }
    std::printf("previewed DDS smoke fixture (2 x 2)\n");
    provider->release_image(&image);

    image = {};
    std::memset(error, 0, sizeof(error));
    const bool loaded_bc1 = provider->load_image(bc1_dds_path, &image, error, sizeof(error));
    const bool valid_bc1 = loaded_bc1 && image.pixels && image.width == 4 && image.height == 4
        && image.pixels[0] == 255 && image.pixels[1] == 0 && image.pixels[2] == 0;
    if (!valid_bc1) {
        std::fprintf(stderr, "BC1 DDS preview failed: %s\n", error[0] ? error : "unexpected pixels");
        return false;
    }
    std::printf("previewed BC1 DDS smoke fixture (4 x 4)\n");
    provider->release_image(&image);
    return true;
}

bool TestHighPrecisionImages(const VaiScenePreviewProvider* provider) {
    constexpr const char* exr_path = ".build/native_preview/preview-smoke.exr";
    constexpr const char* tiff_path = ".build/native_preview/preview-smoke.tiff";
    if (!provider->load_image || !provider->release_image || !WriteEXRFixture(exr_path) || !WriteTIFFFixture(tiff_path)) {
        std::fprintf(stderr, "could not prepare the EXR/TIFF smoke fixtures\n");
        return false;
    }
    const auto test_image = [provider](const char* path, unsigned width, unsigned height, const char* label) {
        char error[1024] = {};
        VaiImagePreview image = {};
        const bool loaded = provider->can_preview(path) && provider->load_image(path, &image, error, sizeof(error));
        const bool valid = loaded && image.pixels && image.width == width && image.height == height && image.row_stride == width * 4;
        if (!valid) {
            std::fprintf(stderr, "%s preview failed: %s\n", label, error[0] ? error : "unexpected pixels");
            return false;
        }
        std::printf("previewed %s smoke fixture (%u x %u)\n", label, width, height);
        provider->release_image(&image);
        return true;
    };
    return test_image(exr_path, 1, 1, "OpenEXR") && test_image(tiff_path, 2, 1, "TIFF");
}

} // namespace

int main(int argc, char** argv) {
    if (argc < 3) {
        std::fprintf(stderr, "usage: vai_scene_preview_smoke_test <provider.dll> <scene> [...]\n");
        return 2;
    }

    HMODULE module = LoadLibraryA(argv[1]);
    if (!module) {
        std::fprintf(stderr, "could not load provider: %s\n", argv[1]);
        return 1;
    }
    const auto get_provider = reinterpret_cast<VaiScenePreviewGetProviderFn>(GetProcAddress(module, "Vai_Get_Scene_Preview_Provider"));
    const VaiScenePreviewProvider* provider = get_provider ? get_provider(VAI_SCENE_PREVIEW_ABI_VERSION) : nullptr;
    if (!provider || !provider->can_preview || !provider->load_scene || !provider->release_scene) {
        std::fprintf(stderr, "provider ABI is incomplete\n");
        FreeLibrary(module);
        return 1;
    }

    int failures = 0;
    for (int argument = 2; argument < argc; ++argument) {
        if (!TestScene(provider, argv[argument])) ++failures;
    }
    if (!TestOBJMaterial(provider)) ++failures;
    if (!TestLitScene(provider, ".build/native_preview/preview-smoke.obj")) ++failures;
    if (!TestDDS(provider)) ++failures;
    if (!TestHighPrecisionImages(provider)) ++failures;

    FreeLibrary(module);
    return failures ? 1 : 0;
}
