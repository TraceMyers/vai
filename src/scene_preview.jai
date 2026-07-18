SCENE_PREVIEW_ABI_VERSION :: 1;

ScenePreviewNativeVertex :: struct {
    position: [3]float;
    color: [4]float;
}

ScenePreviewNativeMesh :: struct {
    vertices: *ScenePreviewNativeVertex;
    vertex_count: u32;
    bounds_min: [3]float;
    bounds_max: [3]float;
}

ScenePreviewCanPreviewFn :: #type (utf8_path: *u8) -> s32 #c_call;
ScenePreviewLoadFn :: #type (utf8_path: *u8, out_mesh: *ScenePreviewNativeMesh, error_message: *u8, error_message_capacity: u32) -> s32 #c_call;
ScenePreviewReleaseFn :: #type (mesh: *ScenePreviewNativeMesh) -> void #c_call;
ImagePreviewNative :: struct {
    pixels: *u8;
    width: u32;
    height: u32;
    row_stride: u32;
}
LitScenePreviewNativeVertex :: struct {
    position: [3]float;
    normal: [3]float;
    tangent: [4]float;
    color: [4]float;
    uv: [2]float;
}
SCENE_MATERIAL_BASE_COLOR_TEXTURE :: cast(u32)1 << 0;
SCENE_MATERIAL_NORMAL_TEXTURE     :: cast(u32)1 << 1;
SCENE_MATERIAL_WRAP_U_REPEAT      :: cast(u32)1 << 2;
SCENE_MATERIAL_WRAP_V_REPEAT      :: cast(u32)1 << 3;
LitScenePreviewNativeMaterial :: struct {
    base_color_texture: ImagePreviewNative;
    normal_texture: ImagePreviewNative;
    flags: u32;
    normal_scale: float;
}
LitScenePreviewNativeDrawRange :: struct {
    first_vertex: u32;
    vertex_count: u32;
    material_index: u32;
}
LitScenePreviewNativeMesh :: struct {
    vertices: *LitScenePreviewNativeVertex;
    vertex_count: u32;
    materials: *LitScenePreviewNativeMaterial;
    material_count: u32;
    draw_ranges: *LitScenePreviewNativeDrawRange;
    draw_range_count: u32;
    bounds_min: [3]float;
    bounds_max: [3]float;
}
ImagePreviewLoadFn :: #type (utf8_path: *u8, out_image: *ImagePreviewNative, error_message: *u8, error_message_capacity: u32) -> s32 #c_call;
ImagePreviewReleaseFn :: #type (image: *ImagePreviewNative) -> void #c_call;
LitScenePreviewLoadFn :: #type (utf8_path: *u8, out_mesh: *LitScenePreviewNativeMesh, error_message: *u8, error_message_capacity: u32) -> s32 #c_call;
LitScenePreviewReleaseFn :: #type (mesh: *LitScenePreviewNativeMesh) -> void #c_call;

ScenePreviewProviderApi :: struct {
    abi_version: u32;
    struct_size: u32;
    provider_name: *u8;
    extensions: *u8;
    can_preview: ScenePreviewCanPreviewFn;
    load_scene: ScenePreviewLoadFn;
    release_scene: ScenePreviewReleaseFn;
    load_image: ImagePreviewLoadFn;
    release_image: ImagePreviewReleaseFn;
    scene_extensions: *u8;
    image_extensions: *u8;
    load_lit_scene: LitScenePreviewLoadFn;
    release_lit_scene: LitScenePreviewReleaseFn;
}

SCENE_PREVIEW_PROVIDER_API_V1_SIZE :: #run Offset_Of(ScenePreviewProviderApi, "scene_extensions");
SCENE_PREVIEW_PROVIDER_API_SEPARATED_EXTENSIONS_SIZE :: #run Offset_Of(ScenePreviewProviderApi, "load_lit_scene");
SCENE_PREVIEW_PROVIDER_API_LIT_SIZE :: #run size_of(ScenePreviewProviderApi);

ScenePreviewGetProviderFn :: #type (host_abi_version: u32) -> *ScenePreviewProviderApi #c_call;

ScenePreviewProvider :: struct {
    module: HMODULE;
    api: *ScenePreviewProviderApi;
    file_path: string;
}

FileExplorerSceneVertex :: struct {
    position: Vector3;
    normal: Vector3;
    tangent: Vector4;
    color: Vector4;
    uv: Vector2;
}

FileExplorerSceneTexture :: struct {
    pixels: []u8;
    width, height: s32;
    texture: u32;
}

FileExplorerSceneMaterial :: struct {
    base_color_texture: FileExplorerSceneTexture;
    normal_texture: FileExplorerSceneTexture;
    flags: u32;
    normal_scale: float = 1.0;
}

FileExplorerSceneDrawRange :: struct {
    first_vertex: s64;
    vertex_count: s64;
    material_index: s64;
}

FileExplorerScenePreview :: struct {
    file_path: string;
    vertices: []FileExplorerSceneVertex;
    vertex_buffer: u32;
    materials: []FileExplorerSceneMaterial;
    draw_ranges: []FileExplorerSceneDrawRange;
    bounds_min: Vector3;
    bounds_max: Vector3;
    error_message: string;
}

file_explorer_scene_preview: FileExplorerScenePreview;
file_explorer_scene_preview_available: bool = true;
scene_preview_providers: [..]ScenePreviewProvider;

Scene_Preview_Providers :: struct {
    Initialize :: () -> bool {
        plugin_directory := Preview_Plugin_Directory();
        make_directory_if_it_does_not_exist(plugin_directory, recursive=true);

        // User providers have priority over built-ins, so a project can supply
        // a specialized reader for an extension Vai already understands.
        success, plugin_files := Directory_List(plugin_directory);
        if success for plugin_files {
            if it.is_directory || it.is_symlink then continue;
            _, _, extension := split_from_right(it.name, #char ".");
            if To_Lower_Temp(extension) != "dll" then continue;
            Scene_Preview_Register_Provider(tprint("%/%", plugin_directory, it.name));
        }

        Scene_Preview_Register_Provider(tprint("%/vai_builtin_scene_preview.dll", exe_path), required=true);
        return true;
    }

    Shutdown :: () {
        // The worker is constructed before this service and can still finish a
        // scene load during shutdown.  Windows releases DLLs at process exit;
        // keeping them loaded here avoids unloading code under that worker.
        for *scene_preview_providers {
            String_Reset(*it.file_path);
        }
        array_reset(*scene_preview_providers);
        File_Explorer_Scene_Preview_Clear();
    }
}

Preview_Plugin_Directory :: () -> string {
    return tprint("%/plugins/preview", vai_config_directory);
}

Scene_Preview_Register_Provider :: (file_path: string, required := false) -> bool {
    module := LoadLibraryA(temp_c_string(file_path));
    if module == null {
        if required Log_Warning("could not load built-in scene preview provider [%]", file_path);
        return false;
    }

    get_provider := cast(ScenePreviewGetProviderFn)GetProcAddress(module, "Vai_Get_Scene_Preview_Provider");
    if get_provider == null {
        if required Log_Warning("scene preview provider [%] does not export Vai_Get_Scene_Preview_Provider", file_path);
        FreeLibrary(module);
        return false;
    }
    api := get_provider(SCENE_PREVIEW_ABI_VERSION);
    if api == null || api.abi_version != SCENE_PREVIEW_ABI_VERSION || api.struct_size < SCENE_PREVIEW_PROVIDER_API_V1_SIZE
    || api.can_preview == null
    || (api.load_scene == null || api.release_scene == null) && (api.load_image == null || api.release_image == null) {
        if required Log_Warning("scene preview provider [%] has an incompatible ABI", file_path);
        FreeLibrary(module);
        return false;
    }

    array_add(*scene_preview_providers, .{module, api, copy_string(file_path)});
    Log("loaded scene preview provider [%]", file_path);
    return true;
}

Scene_Preview_Has_Provider_For_Extension :: (extension: string) -> bool {
    if extension.count == 0 then return false;
    for scene_preview_providers {
        extensions := Scene_Preview_Provider_Extensions(it.api, for_scene=true);
        if it.api.load_scene != null && Scene_Preview_Extension_List_Contains(extensions, extension) return true;
    }
    return false;
}

Image_Preview_Has_Provider_For_Extension :: (extension: string) -> bool {
    if extension.count == 0 then return false;
    for scene_preview_providers {
        extensions := Scene_Preview_Provider_Extensions(it.api, for_scene=false);
        if it.api.load_image != null && Scene_Preview_Extension_List_Contains(extensions, extension) return true;
    }
    return false;
}

Scene_Preview_Provider_Extensions :: (api: *ScenePreviewProviderApi, for_scene: bool) -> *u8 {
    if api.struct_size >= SCENE_PREVIEW_PROVIDER_API_SEPARATED_EXTENSIONS_SIZE {
        separated := ifx for_scene then api.scene_extensions else api.image_extensions;
        if separated != null {
            return separated;
        }
    }
    return api.extensions;
}

Scene_Preview_Extension_List_Contains :: (extensions: *u8, wanted_extension: string) -> bool {
    if extensions == null then return false;
    begin: *u8 = extensions;
    cursor: *u8 = extensions;
    while true {
        if cursor.* == #char ";" || cursor.* == 0 {
            candidate := string.{cast(s64)(cursor-begin), begin};
            if candidate == wanted_extension return true;
            if cursor.* == 0 return false;
            cursor += 1;
            begin = cursor;
        } else {
            cursor += 1;
        }
    }
    return false;
}

Scene_Preview_Copy_Native_Texture :: (source: ImagePreviewNative, destination: *FileExplorerSceneTexture, total_bytes: *s64) -> bool {
    if source.pixels == null || source.width == 0 || source.height == 0 {
        return true;
    }
    MAX_PREVIEW_TEXTURE_DIMENSION :: 16384;
    MAX_PREVIEW_TEXTURE_BYTES :: 256 * 1024 * 1024;
    MAX_PREVIEW_SCENE_TEXTURE_BYTES :: 512 * 1024 * 1024;
    byte_count := cast(s64)source.width * cast(s64)source.height * 4;
    if source.width > MAX_PREVIEW_TEXTURE_DIMENSION || source.height > MAX_PREVIEW_TEXTURE_DIMENSION
    || source.row_stride < source.width * 4
    || byte_count <= 0 || byte_count > MAX_PREVIEW_TEXTURE_BYTES
    || total_bytes.* + byte_count > MAX_PREVIEW_SCENE_TEXTURE_BYTES {
        return false;
    }
    destination.pixels = NewArray(byte_count, u8, initialized=false);
    for row: 0..source.height-1 {
        memcpy(
            destination.pixels.data + cast(s64)row * source.width * 4,
            source.pixels + row * source.row_stride,
            source.width * 4,
        );
    }
    destination.width = xx source.width;
    destination.height = xx source.height;
    total_bytes.* += byte_count;
    return true;
}

Scene_Preview_Generate_Legacy_Frames :: (vertices: []FileExplorerSceneVertex) {
    triangle: s64;
    while triangle + 2 < vertices.count {
        a := *vertices[triangle+0];
        b := *vertices[triangle+1];
        c := *vertices[triangle+2];
        face_normal := cross(b.position-a.position, c.position-a.position);
        if length_squared(face_normal) > 0.000000000001 {
            face_normal = unit_vector(face_normal);
        } else {
            face_normal = .{0, 1, 0};
        }
        reference := ifx abs(face_normal.y) < 0.95 then Vector3.{0, 1, 0} else Vector3.{1, 0, 0};
        tangent := cross(reference, face_normal);
        if length_squared(tangent) > 0.000000000001 then tangent = unit_vector(tangent);
        else tangent = .{1, 0, 0};
        for corner: 0..2 {
            vertices[triangle+corner].normal = face_normal;
            vertices[triangle+corner].tangent = .{tangent.x, tangent.y, tangent.z, 1.0};
        }
        triangle += 3;
    }
}

Scene_Preview_Free_Result_Geometry :: (result: *LoadFileExplorerScenePreviewResult) {
    if result.vertex_buffer != 0 {
        glDeleteBuffers(1, *result.vertex_buffer);
    }
    if result.vertices.data != null then free(result.vertices.data);
    if result.materials.data != null {
        for result.materials {
            if it.base_color_texture.texture != 0 then glDeleteTextures(1, *it.base_color_texture.texture);
            if it.normal_texture.texture != 0 then glDeleteTextures(1, *it.normal_texture.texture);
            if it.base_color_texture.pixels.data != null then free(it.base_color_texture.pixels.data);
            if it.normal_texture.pixels.data != null then free(it.normal_texture.pixels.data);
        }
        free(result.materials.data);
    }
    result.vertex_buffer = 0;
    if result.draw_ranges.data != null then free(result.draw_ranges.data);
    result.vertices = .{};
    result.materials = .{};
    result.draw_ranges = .{};
}

Scene_Preview_Load_File :: (file_path: string, result: *LoadFileExplorerScenePreviewResult) {
    error_buffer: [1024]u8;
    for scene_preview_providers {
        if it.api.load_scene == null then continue;
        if it.api.can_preview(temp_c_string(file_path)) == 0 then continue;

        has_lit_api := it.api.struct_size >= SCENE_PREVIEW_PROVIDER_API_LIT_SIZE
            && it.api.load_lit_scene != null && it.api.release_lit_scene != null;
        if has_lit_api {
            native_mesh: LitScenePreviewNativeMesh;
            if it.api.load_lit_scene(temp_c_string(file_path), *native_mesh, error_buffer.data, error_buffer.count) != 0 {
                defer it.api.release_lit_scene(*native_mesh);
                valid := native_mesh.vertices != null && native_mesh.vertex_count >= 3
                    && native_mesh.vertex_count % 3 == 0
                    && native_mesh.materials != null && native_mesh.material_count > 0
                    && native_mesh.draw_ranges != null && native_mesh.draw_range_count > 0;
                if !valid {
                    result.error_message = copy_string("The lit scene provider returned invalid geometry.");
                    return;
                }

                result.vertices = NewArray(native_mesh.vertex_count, FileExplorerSceneVertex, initialized=false);
                for 0..native_mesh.vertex_count-1 {
                    source := native_mesh.vertices[it];
                    result.vertices[it] = .{
                        position=.{source.position[0], source.position[1], source.position[2]},
                        normal=.{source.normal[0], source.normal[1], source.normal[2]},
                        tangent=.{source.tangent[0], source.tangent[1], source.tangent[2], source.tangent[3]},
                        color=.{source.color[0], source.color[1], source.color[2], source.color[3]},
                        uv=.{source.uv[0], source.uv[1]},
                    };
                }

                result.materials = NewArray(native_mesh.material_count, FileExplorerSceneMaterial, initialized=true);
                total_texture_bytes: s64;
                for 0..native_mesh.material_count-1 {
                    source := native_mesh.materials[it];
                    destination := *result.materials[it];
                    destination.flags = source.flags;
                    destination.normal_scale = source.normal_scale;
                    if !Scene_Preview_Copy_Native_Texture(source.base_color_texture, *destination.base_color_texture, *total_texture_bytes)
                    || !Scene_Preview_Copy_Native_Texture(source.normal_texture, *destination.normal_texture, *total_texture_bytes) {
                        Scene_Preview_Free_Result_Geometry(result);
                        result.error_message = copy_string("The scene preview textures exceed Vai's safety limit.");
                        return;
                    }
                }

                result.draw_ranges = NewArray(native_mesh.draw_range_count, FileExplorerSceneDrawRange, initialized=false);
                for 0..native_mesh.draw_range_count-1 {
                    source := native_mesh.draw_ranges[it];
                    range_end := cast(s64)source.first_vertex + cast(s64)source.vertex_count;
                    if source.vertex_count == 0 || range_end > native_mesh.vertex_count || source.material_index >= native_mesh.material_count {
                        Scene_Preview_Free_Result_Geometry(result);
                        result.error_message = copy_string("The lit scene provider returned an invalid material range.");
                        return;
                    }
                    result.draw_ranges[it] = .{
                        first_vertex=source.first_vertex,
                        vertex_count=source.vertex_count,
                        material_index=source.material_index,
                    };
                }
                result.bounds_min = .{native_mesh.bounds_min[0], native_mesh.bounds_min[1], native_mesh.bounds_min[2]};
                result.bounds_max = .{native_mesh.bounds_max[0], native_mesh.bounds_max[1], native_mesh.bounds_max[2]};
                result.success = true;
                return;
            }
        } else {
            native_mesh: ScenePreviewNativeMesh;
            if it.api.load_scene(temp_c_string(file_path), *native_mesh, error_buffer.data, error_buffer.count) != 0 {
                defer it.api.release_scene(*native_mesh);
                if native_mesh.vertices == null || native_mesh.vertex_count < 3 || native_mesh.vertex_count % 3 != 0 {
                    result.error_message = copy_string("The scene provider returned invalid geometry.");
                    return;
                }
                result.vertices = NewArray(native_mesh.vertex_count, FileExplorerSceneVertex, initialized=true);
                for 0..native_mesh.vertex_count-1 {
                    native_vertex := native_mesh.vertices[it];
                    result.vertices[it].position = .{native_vertex.position[0], native_vertex.position[1], native_vertex.position[2]};
                    result.vertices[it].color = .{native_vertex.color[0], native_vertex.color[1], native_vertex.color[2], native_vertex.color[3]};
                }
                Scene_Preview_Generate_Legacy_Frames(result.vertices);
                result.materials = NewArray(1, FileExplorerSceneMaterial, initialized=true);
                result.materials[0].normal_scale = 1.0;
                result.draw_ranges = NewArray(1, FileExplorerSceneDrawRange, initialized=true);
                result.draw_ranges[0] = .{first_vertex=0, vertex_count=native_mesh.vertex_count, material_index=0};
                result.bounds_min = .{native_mesh.bounds_min[0], native_mesh.bounds_min[1], native_mesh.bounds_min[2]};
                result.bounds_max = .{native_mesh.bounds_max[0], native_mesh.bounds_max[1], native_mesh.bounds_max[2]};
                result.success = true;
                return;
            }
        }

        error_count: s64;
        while error_count < error_buffer.count && error_buffer[error_count] != 0 {
            error_count += 1;
        }
        if error_count > 0 then result.error_message = copy_string(string.{error_count, error_buffer.data});
        else result.error_message = copy_string("The scene provider could not load this asset.");
        return;
    }
    result.error_message = copy_string("No installed scene preview provider handles this file type.");
}

Image_Preview_Load_File :: (file_path: string, result: *LoadFileExplorerImagePreviewResult) -> bool {
    error_buffer: [1024]u8;
    for scene_preview_providers {
        if it.api.load_image == null then continue;
        if it.api.can_preview(temp_c_string(file_path)) == 0 then continue;

        native_image: ImagePreviewNative;
        if it.api.load_image(temp_c_string(file_path), *native_image, error_buffer.data, error_buffer.count) == 0 {
            continue;
        }
        defer it.api.release_image(*native_image);

        MAX_PREVIEW_DIMENSION :: 16384;
        MAX_PREVIEW_BYTES :: 256 * 1024 * 1024;
        pixel_byte_count := cast(s64)native_image.width * cast(s64)native_image.height * 4;
        if native_image.pixels == null || native_image.width == 0 || native_image.height == 0
        || native_image.width > MAX_PREVIEW_DIMENSION || native_image.height > MAX_PREVIEW_DIMENSION
        || native_image.row_stride < native_image.width * 4
        || pixel_byte_count <= 0 || pixel_byte_count > MAX_PREVIEW_BYTES {
            return false;
        }

        result.pixels = NewArray(pixel_byte_count, u8, initialized=false);
        for row: 0..native_image.height-1 {
            source := native_image.pixels + row * native_image.row_stride;
            destination := result.pixels.data + row * native_image.width * 4;
            memcpy(destination, source, native_image.width * 4);
        }
        result.width = xx native_image.width;
        result.height = xx native_image.height;
        result.success = true;
        return true;
    }
    return false;
}

File_Explorer_Scene_Preview_Clear :: () {
    if file_explorer_scene_preview.vertex_buffer != 0 {
        glDeleteBuffers(1, *file_explorer_scene_preview.vertex_buffer);
    }
    if file_explorer_scene_preview.vertices.data != null {
        free(file_explorer_scene_preview.vertices.data);
    }
    if file_explorer_scene_preview.materials.data != null {
        for file_explorer_scene_preview.materials {
            if it.base_color_texture.texture != 0 then glDeleteTextures(1, *it.base_color_texture.texture);
            if it.normal_texture.texture != 0 then glDeleteTextures(1, *it.normal_texture.texture);
            if it.base_color_texture.pixels.data != null then free(it.base_color_texture.pixels.data);
            if it.normal_texture.pixels.data != null then free(it.normal_texture.pixels.data);
        }
        free(file_explorer_scene_preview.materials.data);
    }
    if file_explorer_scene_preview.draw_ranges.data != null {
        free(file_explorer_scene_preview.draw_ranges.data);
    }
    String_Reset(*file_explorer_scene_preview.file_path);
    String_Reset(*file_explorer_scene_preview.error_message);
    file_explorer_scene_preview = .{};
}

File_Explorer_Scene_Preview_Is_For_File :: (file_path: string) -> bool {
    return file_explorer_scene_preview.file_path == file_path;
}

Scene_Preview_Upload_Texture :: (texture: *FileExplorerSceneTexture, repeat_u: bool, repeat_v: bool) {
    if texture.texture != 0 || texture.pixels.count == 0 || texture.width <= 0 || texture.height <= 0 {
        return;
    }
    glGenTextures(1, *texture.texture);
    glBindTexture(GL_TEXTURE_2D, texture.texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, cast(s32)(ifx repeat_u then GL_REPEAT else GL_CLAMP_TO_EDGE));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, cast(s32)(ifx repeat_v then GL_REPEAT else GL_CLAMP_TO_EDGE));
    maximum_anisotropy: float = 1.0;
    glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, *maximum_anisotropy);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, clamp(maximum_anisotropy, 1.0, 8.0));
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(
        GL_TEXTURE_2D, 0, cast(s32)GL_RGBA8,
        xx texture.width, xx texture.height, 0,
        GL_RGBA, GL_UNSIGNED_BYTE, texture.pixels.data,
    );
    glGenerateMipmap(GL_TEXTURE_2D);
    free(texture.pixels.data);
    texture.pixels = .{};
}

// Runs on the main thread during result install, with the main GL context already
// current.  Uploading here (instead of on the worker's own context sharing the
// window's single CS_OWNDC HDC) avoids concurrent wglMakeCurrent crashes.
Scene_Preview_Upload_Result_To_GPU :: (result: *LoadFileExplorerScenePreviewResult) -> bool {
    if result.vertices.count < 3 {
        return false;
    }
    glGenBuffers(1, *result.vertex_buffer);
    if result.vertex_buffer == 0 {
        return false;
    }
    glBindBuffer(GL_ARRAY_BUFFER, result.vertex_buffer);
    glBufferData(
        GL_ARRAY_BUFFER,
        size_of(FileExplorerSceneVertex) * result.vertices.count,
        result.vertices.data,
        GL_STATIC_DRAW,
    );

    glActiveTexture(GL_TEXTURE0);
    for *material: result.materials {
        repeat_u := (material.flags & SCENE_MATERIAL_WRAP_U_REPEAT) != 0;
        repeat_v := (material.flags & SCENE_MATERIAL_WRAP_V_REPEAT) != 0;
        if (material.flags & SCENE_MATERIAL_BASE_COLOR_TEXTURE) != 0 {
            Scene_Preview_Upload_Texture(*material.base_color_texture, repeat_u, repeat_v);
        }
        if (material.flags & SCENE_MATERIAL_NORMAL_TEXTURE) != 0 {
            Scene_Preview_Upload_Texture(*material.normal_texture, repeat_u, repeat_v);
        }
    }
    // Uploading here changed the GL_ARRAY_BUFFER binding; restore the invariant
    // the 2D batch pipeline relies on before returning to the renderer.
    Restore_Batch_Vertex_Buffer();
    return true;
}

Render_File_Explorer_Scene_Preview :: (ul: IntVector2, lr: IntVector2) {
    if file_explorer_scene_preview.error_message.count > 0 {
        Render_Text_String_At(file_explorer_scene_preview.error_message, ul.x + 12, ul.y + 24, .{rgb=.{1.0, 0.55, 0.42}, a=1.0});
        return;
    }
    if file_explorer_scene_preview.vertices.count < 3
    || file_explorer_scene_preview.materials.count == 0
    || file_explorer_scene_preview.draw_ranges.count == 0 {
        return;
    }

    preview_width := lr.x - ul.x;
    preview_height := lr.y - ul.y;
    if preview_width <= 0 || preview_height <= 0 {
        return;
    }

    center := (file_explorer_scene_preview.bounds_min + file_explorer_scene_preview.bounds_max) * 0.5;
    extent := file_explorer_scene_preview.bounds_max - file_explorer_scene_preview.bounds_min;
    radius := max(max(extent.x, extent.y), extent.z) * 0.5;
    radius = max(radius, 0.05);

    // A fixed, slightly elevated three-quarter camera makes an unfamiliar
    // asset legible immediately; interaction controls can adjust this later.
    camera_position := center + .{radius * 1.55, radius * 1.15, radius * 1.55};
    view_matrix := make_look_at_matrix(camera_position, center, .{0, 1, 0}, x_is_forward=false);
    aspect_ratio := cast(float)preview_width / cast(float)preview_height;
    projection_matrix := make_projection_matrix(55.0 * PI / 180.0, aspect_ratio, 0.01, max(radius * 30.0, 100.0));
    mvp := projection_matrix * view_matrix;
    downstage_direction := unit_vector(camera_position-center);
    light_direction := unit_vector(Vector3.{0, 1, 0} * 0.82 + downstage_direction * 0.32);
    // The renderer owns the OpenGL buffer and restores the normal text shader
    // after issuing this direct 3D draw.
    Render_Scene_Triangle_List(
        file_explorer_scene_preview.vertex_buffer,
        file_explorer_scene_preview.vertices.count,
        size_of(FileExplorerSceneVertex),
        Offset_Of(FileExplorerSceneVertex, "position"),
        Offset_Of(FileExplorerSceneVertex, "normal"),
        Offset_Of(FileExplorerSceneVertex, "tangent"),
        Offset_Of(FileExplorerSceneVertex, "color"),
        Offset_Of(FileExplorerSceneVertex, "uv"),
        file_explorer_scene_preview.materials.data,
        file_explorer_scene_preview.materials.count,
        file_explorer_scene_preview.draw_ranges.data,
        file_explorer_scene_preview.draw_ranges.count,
        light_direction,
        mvp,
        ul,
        lr,
    );
}

Run_Production_Scene_Preview_Smoke_Test :: (requested_scene_path := "") -> bool {
    scene_path := ifx requested_scene_path.count > 0
        then requested_scene_path
        else tprint("%/../native_preview/testdata/Box.glb", exe_path);

    if File_Explorer_Preview_Kind_For_Extension("glb") != .SCENE
    || File_Explorer_Preview_Kind_For_Extension("obj") != .SCENE
    || File_Explorer_Preview_Kind_For_Extension("dds") != .IMAGE {
        Log_Error("scene/image provider extensions were classified into the wrong explorer preview pipeline");
        return false;
    }

    File_Explorer_Scene_Preview_Clear();
    request_data := LoadFileExplorerScenePreviewRequest.{file_path=copy_string(scene_path)};
    request := AsyncTaskRequest.{type=.LOAD_FILE_EXPLORER_SCENE_PREVIEW, load_file_explorer_scene_preview=request_data};
    if !Make_Unique_Thread_Work_Request(request) {
        free(request_data.file_path);
        Log_Error("scene preview smoke test could not queue [%]", scene_path);
        return false;
    }

    dispatched_changed_ui := Process_Async_Results();
    installed_changed_ui := false;
    for 0..30000 {
        installed_changed_ui |= Process_Async_Results();
        if File_Explorer_Scene_Preview_Is_For_File(scene_path) {
            break;
        }
        sleep_milliseconds(1);
    }
    if !dispatched_changed_ui || !installed_changed_ui
    || !File_Explorer_Scene_Preview_Is_For_File(scene_path)
    || file_explorer_scene_preview.vertices.count < 3 {
        Log_Error(
            "scene preview smoke test could not asynchronously load [%]: %",
            scene_path,
            ifx file_explorer_scene_preview.error_message.count > 0
                then file_explorer_scene_preview.error_message
                else "invalid triangle list"
        );
        return false;
    }

    background_rgb := fRGB.{0.05, 0.07, 0.09};
    Begin_Draw_Frame(true);
    Set_Shader_For_Blended_Color();
    Render_Quad(.{0, 0}, .{window.width, window.height}, .{rgb=background_rgb, a=1.0});
    Flush_Draws();

    // Deliberately keep this square far from the full-window center. A scene
    // draw that forgets to install the preview-local viewport will miss the
    // sampled region even if its scissor happens to be correct.
    preview_ul := IntVector2.{8, 8};
    preview_lr := IntVector2.{88, 88};
    Set_Scissor(preview_ul, preview_lr);
    Render_File_Explorer_Scene_Preview(preview_ul, preview_lr);
    glFinish();

    pixel_byte_count := cast(s64)window.width * cast(s64)window.height * 4;
    pixels := NewArray(pixel_byte_count, u8, initialized=false);
    defer free(pixels.data);
    glReadBuffer(GL_BACK);
    glReadPixels(0, 0, xx window.width, xx window.height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data);
    glReadBuffer(GL_FRONT);

    expected := s32.[
        cast(s32)(background_rgb.r * 255.0),
        cast(s32)(background_rgb.g * 255.0),
        cast(s32)(background_rgb.b * 255.0),
    ];
    changed_inside: s64;
    changed_outside: s64;
    minimum_inside_luminance: s32 = 255 * 3;
    maximum_inside_luminance: s32;
    framebuffer_preview_y_min := window.height - preview_lr.y;
    framebuffer_preview_y_max := window.height - preview_ul.y;
    for y: 0..window.height-1 {
        for x: 0..window.width-1 {
            pixel_offset := (cast(s64)y * cast(s64)window.width + cast(s64)x) * 4;
            changed := abs(cast(s32)pixels[pixel_offset+0] - expected[0]) > 4
                || abs(cast(s32)pixels[pixel_offset+1] - expected[1]) > 4
                || abs(cast(s32)pixels[pixel_offset+2] - expected[2]) > 4;
            if !changed {
                continue;
            }
            inside := x >= preview_ul.x && x < preview_lr.x
                && y >= framebuffer_preview_y_min && y < framebuffer_preview_y_max;
            if inside {
                changed_inside += 1;
                luminance := cast(s32)pixels[pixel_offset+0] + cast(s32)pixels[pixel_offset+1] + cast(s32)pixels[pixel_offset+2];
                minimum_inside_luminance = min(minimum_inside_luminance, luminance);
                maximum_inside_luminance = max(maximum_inside_luminance, luminance);
            } else {
                changed_outside += 1;
            }
        }
    }

    File_Explorer_Scene_Preview_Clear();
    if changed_inside < 64 || changed_outside != 0 {
        Log_Error(
            "scene preview smoke test changed % pixels inside and % outside its viewport",
            changed_inside,
            changed_outside
        );
        return false;
    }
    Log(
        "production scene preview smoke test passed (% changed pixels, luminance span %)",
        changed_inside,
        maximum_inside_luminance-minimum_inside_luminance,
    );
    return true;
}
