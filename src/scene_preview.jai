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
ImagePreviewLoadFn :: #type (utf8_path: *u8, out_image: *ImagePreviewNative, error_message: *u8, error_message_capacity: u32) -> s32 #c_call;
ImagePreviewReleaseFn :: #type (image: *ImagePreviewNative) -> void #c_call;

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
}

ScenePreviewGetProviderFn :: #type (host_abi_version: u32) -> *ScenePreviewProviderApi #c_call;

ScenePreviewProvider :: struct {
    module: HMODULE;
    api: *ScenePreviewProviderApi;
    file_path: string;
}

FileExplorerSceneVertex :: struct {
    position: Vector3;
    color: Vector4;
}

FileExplorerScenePreview :: struct {
    file_path: string;
    vertices: []FileExplorerSceneVertex;
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
    if api == null || api.abi_version != SCENE_PREVIEW_ABI_VERSION || api.struct_size < size_of(ScenePreviewProviderApi)
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
        if it.api.load_scene != null && Scene_Preview_Extension_List_Contains(it.api.extensions, extension) return true;
    }
    return false;
}

Image_Preview_Has_Provider_For_Extension :: (extension: string) -> bool {
    if extension.count == 0 then return false;
    for scene_preview_providers {
        if it.api.load_image != null && Scene_Preview_Extension_List_Contains(it.api.extensions, extension) return true;
    }
    return false;
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

Scene_Preview_Load_File :: (file_path: string, result: *LoadFileExplorerScenePreviewResult) {
    error_buffer: [1024]u8;
    for scene_preview_providers {
        if it.api.load_scene == null then continue;
        if it.api.can_preview(temp_c_string(file_path)) == 0 then continue;

        native_mesh: ScenePreviewNativeMesh;
    if it.api.load_scene(temp_c_string(file_path), *native_mesh, error_buffer.data, error_buffer.count) != 0 {
            if native_mesh.vertices == null || native_mesh.vertex_count == 0 {
                String_Reset(*result.error_message);
                result.error_message = copy_string("The scene provider returned no geometry.");
                return;
            }
            result.vertices = NewArray(native_mesh.vertex_count, FileExplorerSceneVertex, initialized=false);
            for 0..native_mesh.vertex_count-1 {
                native_vertex := native_mesh.vertices[it];
                result.vertices[it] = .{
                    position=.{native_vertex.position[0], native_vertex.position[1], native_vertex.position[2]},
                    color=.{native_vertex.color[0], native_vertex.color[1], native_vertex.color[2], native_vertex.color[3]},
                };
            }
            result.bounds_min = .{native_mesh.bounds_min[0], native_mesh.bounds_min[1], native_mesh.bounds_min[2]};
            result.bounds_max = .{native_mesh.bounds_max[0], native_mesh.bounds_max[1], native_mesh.bounds_max[2]};
            it.api.release_scene(*native_mesh);
            result.success = true;
            return;
        }

        error_count: s64;
        while error_count < error_buffer.count && error_buffer[error_count] != 0 {
            error_count += 1;
        }
        if error_count > 0 {
            result.error_message = copy_string(string.{error_count, error_buffer.data});
        } else {
            result.error_message = copy_string("The scene provider could not load this asset.");
        }
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
    if file_explorer_scene_preview.vertices.data != null {
        free(file_explorer_scene_preview.vertices.data);
    }
    String_Reset(*file_explorer_scene_preview.file_path);
    String_Reset(*file_explorer_scene_preview.error_message);
    file_explorer_scene_preview = .{};
}

File_Explorer_Scene_Preview_Is_For_File :: (file_path: string) -> bool {
    return file_explorer_scene_preview.file_path == file_path;
}

Render_File_Explorer_Scene_Preview :: (ul: IntVector2, lr: IntVector2) {
    if file_explorer_scene_preview.error_message.count > 0 {
        Render_Text_String_At(file_explorer_scene_preview.error_message, ul.x + 12, ul.y + 24, .{rgb=.{1.0, 0.55, 0.42}, a=1.0});
        return;
    }
    if file_explorer_scene_preview.vertices.count < 3 {
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

    // The renderer owns the OpenGL buffer and restores the normal text shader
    // after issuing this direct 3D draw.
    Render_Scene_Triangle_List(
        xx file_explorer_scene_preview.vertices.data,
        file_explorer_scene_preview.vertices.count,
        size_of(FileExplorerSceneVertex),
        Offset_Of(FileExplorerSceneVertex, "position"),
        Offset_Of(FileExplorerSceneVertex, "color"),
        mvp,
    );
}
