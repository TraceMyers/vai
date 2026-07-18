FileExplorerPreviewKind :: enum u8 {
    NONE;
    TEXT;
    IMAGE;
    SCENE;
}

FileExplorerPreviewState :: enum u8 {
    NONE;
    LOADING;
    READY;
    UNAVAILABLE;
}

file_explorer_selected_preview_kind: FileExplorerPreviewKind;
file_explorer_selected_preview_path: string;
file_explorer_preview_state: FileExplorerPreviewState;
file_explorer_preview_generation: u64;

File_Explorer_Preview_Request_Is_Current :: (
    kind: FileExplorerPreviewKind,
    file_path: string,
    generation: u64
) -> bool {
    return generation == atomic_read(*file_explorer_preview_generation)
        && kind == file_explorer_selected_preview_kind
        && file_path == file_explorer_selected_preview_path;
}

File_Explorer_Select_Preview :: (kind: FileExplorerPreviewKind, file_path: string) {
    if kind == file_explorer_selected_preview_kind && file_path == file_explorer_selected_preview_path {
        return;
    }

    Cancel_Pending_File_Explorer_Preview_Tasks();
    String_Reset(*file_explorer_selected_preview_path);
    file_explorer_selected_preview_path = copy_string(file_path);
    file_explorer_selected_preview_kind = kind;
    generation := atomic_add(*file_explorer_preview_generation, cast(u64)1) + 1;

    if file_path.count == 0 {
        file_explorer_preview_state = .NONE;
        return;
    }
    if kind == .NONE {
        file_explorer_preview_state = .UNAVAILABLE;
        return;
    }

    file_explorer_preview_state = .LOADING;
    request: AsyncTaskRequest;
    if kind == {
    case .TEXT;
        request = .{
            type=.LOAD_FILE_EXPLORER_PREVIEW,
            load_file_explorer_preview=.{file_path=copy_string(file_path), generation=generation},
        };
    case .IMAGE;
        request = .{
            type=.LOAD_FILE_EXPLORER_IMAGE_PREVIEW,
            load_file_explorer_image_preview=.{file_path=copy_string(file_path), generation=generation},
        };
    case .SCENE;
        request = .{
            type=.LOAD_FILE_EXPLORER_SCENE_PREVIEW,
            load_file_explorer_scene_preview=.{file_path=copy_string(file_path), generation=generation},
        };
    case;
        file_explorer_preview_state = .UNAVAILABLE;
        return;
    }
    Make_Unique_Thread_Work_Request(request);
}

File_Explorer_Selected_Preview_Name :: () -> string {
    _, _, name := split_from_right(file_explorer_selected_preview_path, #char "/");
    if name.count == 0 {
        _, _, name = split_from_right(file_explorer_selected_preview_path, #char "\\");
    }
    if name.count == 0 then return file_explorer_selected_preview_path;
    return name;
}

Circular_Feather_From_Center :: (
    position: IntVector2,
    center: IntVector2,
    inner_radius: float,
    outer_radius: float,
    invert := false
) -> float {
    dx := cast(float)(position.x-center.x);
    dy := cast(float)(position.y-center.y);
    distance_squared := dx*dx + dy*dy;
    inner_squared := inner_radius*inner_radius;
    outer_squared := max(outer_radius*outer_radius, inner_squared+1.0);
    amount := clamp((distance_squared-inner_squared)/(outer_squared-inner_squared), 0.0, 1.0);
    amount = amount*amount*(3.0-2.0*amount);
    return ifx invert then 1.0-amount else amount;
}

Render_File_Explorer_Loading_Preview :: (ul: IntVector2, lr: IntVector2) {
    width := lr.x-ul.x;
    height := lr.y-ul.y;
    if width <= 0 || height <= 0 then return;

    Set_Shader_For_Blended_Color();
    center := IntVector2.{(ul.x+lr.x)/2, (ul.y+lr.y)/2};
    field_radius := cast(float)min(width, height);
    inner_radius := field_radius * 0.20;
    outer_radius := field_radius * 0.58;
    dot_step := max(sdw(15), 8);
    dot_size := max(sdw(1), 1);
    y := ul.y + dot_step/2;
    row: s32;
    while y < lr.y {
        x := ul.x + dot_step/2 + (row%2)*(dot_step/2);
        while x < lr.x {
            feather := Circular_Feather_From_Center(.{x, y}, center, inner_radius, outer_radius, invert=true);
            if feather > 0.01 {
                color := fRGBA.{0.42, 0.50, 0.52, 0.30*feather};
                Render_Quad(.{x, y}, .{min(x+dot_size, lr.x), min(y+dot_size, lr.y)}, color);
            }
            x += dot_step;
        }
        y += dot_step;
        row += 1;
    }
    Flush_Draws();

    dot_count := cast(s64)(seconds_since_init()/0.72) % 4;
    // Keep three character cells reserved so the label itself never shifts;
    // only the old-school ellipsis changes.
    ellipsis := "   ";
    if dot_count == 1 then ellipsis = ".  ";
    else if dot_count == 2 then ellipsis = ".. ";
    else if dot_count == 3 then ellipsis = "...";
    label := tprint("Loading %%", File_Explorer_Selected_Preview_Name(), ellipsis);
    label_width := xx label.count * Width(font);
    line_height: s32 = xx (get_baseline_height(font) * 4);
    line_height += xx (cast(float32)line_height * line_spacing_factor);
    label_x := max(ul.x+(width-label_width)/2, ul.x+4);
    label_y := max(ul.y, lr.y-line_height);
    Render_Text_String_At(label, label_x, label_y, .{0.48, 0.54, 0.56, 0.72});
}

Render_File_Explorer_Unavailable_Preview :: (ul: IntVector2, lr: IntVector2) {
    width := lr.x-ul.x;
    height := lr.y-ul.y;
    if width <= 0 || height <= 0 then return;

    line_height: s32 = xx (get_baseline_height(font) * 4);
    line_height += xx (cast(float32)line_height * line_spacing_factor);
    minimum_dimension := min(width, height);
    icon_size := min(max(sdw(48), 28), max(minimum_dimension-line_height*2, 16));
    center_x := (ul.x+lr.x)/2;
    center_y := (ul.y+lr.y-line_height)/2;
    icon_left := center_x-icon_size/2;
    icon_right := center_x+icon_size/2;
    icon_top := center_y-icon_size/2;
    icon_bottom := center_y+icon_size/2;
    fold := max(icon_size/4, 4);
    color := fRGBA.{0.48, 0.54, 0.56, 0.78};

    Set_Shader_For_Lines();
    Render_Line(.{icon_left, icon_top}, .{icon_right-fold, icon_top}, color);
    Render_Line(.{icon_right-fold, icon_top}, .{icon_right, icon_top+fold}, color);
    Render_Line(.{icon_right, icon_top+fold}, .{icon_right, icon_bottom}, color);
    Render_Line(.{icon_right, icon_bottom}, .{icon_left, icon_bottom}, color);
    Render_Line(.{icon_left, icon_bottom}, .{icon_left, icon_top}, color);
    Render_Line(.{icon_right-fold, icon_top}, .{icon_right-fold, icon_top+fold}, color);
    Render_Line(.{icon_right-fold, icon_top+fold}, .{icon_right, icon_top+fold}, color);

    eye_y := center_y+icon_size/10;
    eye_half_width := max(icon_size*27/100, 4);
    eye_half_height := max(icon_size*10/100, 2);
    eye_points := IntVector2.[
        .{center_x-eye_half_width, eye_y},
        .{center_x-eye_half_width/2, eye_y-eye_half_height},
        .{center_x, eye_y-eye_half_height-eye_half_height/3},
        .{center_x+eye_half_width/2, eye_y-eye_half_height},
        .{center_x+eye_half_width, eye_y},
        .{center_x+eye_half_width/2, eye_y+eye_half_height},
        .{center_x, eye_y+eye_half_height+eye_half_height/3},
        .{center_x-eye_half_width/2, eye_y+eye_half_height},
    ];
    for 0..eye_points.count-1 {
        Render_Line(eye_points[it], eye_points[(it+1)%eye_points.count], color);
    }
    pupil_half := max(icon_size/24, 1);
    Render_Line(.{center_x-pupil_half, eye_y}, .{center_x+pupil_half, eye_y}, color);
    Render_Line(.{center_x, eye_y-pupil_half}, .{center_x, eye_y+pupil_half}, color);
    slash_inset := max(icon_size/10, 3);
    Render_Line(
        .{icon_left+slash_inset, icon_top+slash_inset},
        .{icon_right-slash_inset, icon_bottom-slash_inset},
        color,
    );
    Flush_Draws();

    label := "Preview unavailable";
    label_width := xx label.count * Width(font);
    label_x := max(ul.x+(width-label_width)/2, ul.x+4);
    label_y := min(icon_bottom+line_height, lr.y-line_height/3);
    Render_Text_String_At(label, label_x, label_y, .{0.48, 0.54, 0.56, 0.78});
}

FileExplorerImagePreview :: struct {
    file_path: string;
    pixels: []u8;
    width, height: s32;
    texture: u32;
}

file_explorer_image_preview: FileExplorerImagePreview;
file_explorer_image_preview_available: bool = true;

File_Explorer_Preview_Kind_For_Extension :: (extension: string) -> FileExplorerPreviewKind {
    if Is_Basic_Text_File_Extension(extension) || Is_Code_File_Extension(extension) {
        return .TEXT;
    }
    if Is_File_Explorer_Image_Extension(extension) || Image_Preview_Has_Provider_For_Extension(extension) {
        return .IMAGE;
    }
    if Is_File_Explorer_Scene_Extension(extension) || Scene_Preview_Has_Provider_For_Extension(extension) {
        return .SCENE;
    }
    return .NONE;
}

Is_File_Explorer_Image_Extension :: (extension: string) -> bool {
    return extension == "png"
        || extension == "jpg"
        || extension == "jpeg"
        || extension == "bmp"
        || extension == "tga"
        || extension == "psd"
        || extension == "gif"
        || extension == "hdr"
        || extension == "exr"
        || extension == "tif"
        || extension == "tiff"
        || extension == "dng"
        || extension == "pic"
        || extension == "ppm"
        || extension == "pgm";
}

// Scene previews are registered here before their providers are implemented so
// selection, async dispatch, and rendering can share one preview pipeline.
Is_File_Explorer_Scene_Extension :: (extension: string) -> bool {
    return extension == "gltf"
        || extension == "glb"
        || extension == "fbx"
        || extension == "obj"
        || extension == "usd"
        || extension == "usda"
        || extension == "usdc"
        || extension == "usdz";
}

File_Explorer_Image_Preview_Clear :: () {
    if file_explorer_image_preview.texture != 0 {
        glDeleteTextures(1, *file_explorer_image_preview.texture);
    }
    if file_explorer_image_preview.pixels.data != null {
        free(file_explorer_image_preview.pixels.data);
    }
    String_Reset(*file_explorer_image_preview.file_path);
    file_explorer_image_preview = .{};
}

File_Explorer_Image_Preview_Is_For_File :: (file_path: string) -> bool {
    return file_explorer_image_preview.file_path == file_path;
}

File_Explorer_Image_Preview_Upload_Result_To_GPU :: (result: *LoadFileExplorerImagePreviewResult) -> bool {
    if result.pixels.count == 0 || result.width <= 0 || result.height <= 0 || preview_upload_gl_context == null {
        return false;
    }
    previous_context := wglGetCurrentContext();
    previous_device_context := wglGetCurrentDC();
    if !wglMakeCurrent(device_context, preview_upload_gl_context) {
        return false;
    }
    defer wglMakeCurrent(previous_device_context, previous_context);

    glGenTextures(1, *result.texture);
    if result.texture == 0 {
        return false;
    }
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, result.texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(
        GL_TEXTURE_2D, 0, cast(s32)GL_RGBA8,
        xx result.width, xx result.height, 0,
        GL_RGBA, GL_UNSIGNED_BYTE, result.pixels.data,
    );
    glFinish();
    free(result.pixels.data);
    result.pixels = .{};
    return true;
}

Render_File_Explorer_Image_Preview :: (ul: IntVector2, lr: IntVector2) {
    if file_explorer_image_preview.width <= 0 || file_explorer_image_preview.height <= 0
    || file_explorer_image_preview.texture == 0 {
        return;
    }

    // Image previews are a 2D overlay. They must not compete with the
    // checkerboard or a previously rendered scene in the depth buffer.
    Disable_Depth_Test();
    defer Enable_Depth_Test();

    available_width := lr.x - ul.x;
    available_height := lr.y - ul.y;
    if available_width <= 0 || available_height <= 0 {
        return;
    }
    image_aspect := cast(float)file_explorer_image_preview.width / cast(float)file_explorer_image_preview.height;
    available_aspect := cast(float)available_width / cast(float)available_height;
    image_width, image_height: s32;
    if image_aspect > available_aspect {
        image_width = available_width;
        image_height = cast(s32)(cast(float)image_width / image_aspect);
    } else {
        image_height = available_height;
        image_width = cast(s32)(cast(float)image_height * image_aspect);
    }
    image_ul := IntVector2.{ul.x + (available_width-image_width)/2, ul.y + (available_height-image_height)/2};
    image_lr := image_ul + .{image_width, image_height};

    Set_Shader_For_Blended_Color();
    checker_size :: 12;
    y := image_ul.y;
    while y < image_lr.y {
        x := image_ul.x;
        while x < image_lr.x {
            parity := ((x-image_ul.x)/checker_size + (y-image_ul.y)/checker_size) & 1;
            shade := ifx parity == 0 then 0.22 else 0.32;
            checker_lr := IntVector2.{min(x+checker_size, image_lr.x), min(y+checker_size, image_lr.y)};
            Render_Quad(.{x, y}, checker_lr, .{rgb=.{shade, shade, shade}, a=1.0});
            x += checker_size;
        }
        y += checker_size;
    }
    Flush_Draws();

    Set_Image_Shader_Texture(file_explorer_image_preview.texture, image_ul, image_lr);
    Render_Quad(image_ul, image_lr, .{rgb=fRGB_WHITE, a=1.0}, .{0, 0}, .{1, 1});
    Flush_Draws();
}

// This test runs through the compiled editor's own image loader and renderer.
// It is intentionally entered only with --image-preview-smoke-test, before
// project configuration starts, so it cannot alter a user's editor session.
Run_Production_Image_Preview_Smoke_Test :: () -> bool {
    source_task: AsyncTask;
    source_task.request = .{
        type=.LOAD_FILE_EXPLORER_IMAGE_PREVIEW,
        load_file_explorer_image_preview=.{file_path="screenshot.png"},
    };
    Init_Task_Result(*source_task);
    Load_File_Explorer_Image_Preview(*source_task);
    source_result := *source_task.result.load_file_explorer_image_preview;
    if !source_result.success || source_result.width <= 0 || source_result.height <= 0
    || source_result.texture == 0 || source_result.pixels.count != 0 {
        Log_Error("image preview smoke test could not load screenshot.png");
        if source_result.pixels.data != null free(source_result.pixels.data);
        if source_result.texture != 0 then glDeleteTextures(1, *source_result.texture);
        return false;
    }
    glDeleteTextures(1, *source_result.texture);

    // Use deterministic opaque pixels for the framebuffer assertion. The
    // real PNG above verifies the production stb loader; these texels verify
    // the preview shader's UV orientation without depending on screenshot.png.
    File_Explorer_Image_Preview_Clear();
    file_explorer_image_preview.file_path = copy_string("__image_preview_smoke_test__");
    file_explorer_image_preview.width = 2;
    file_explorer_image_preview.height = 2;
    file_explorer_image_preview.pixels = NewArray(16, u8, initialized=true);
    // Source rows are top-to-bottom: red, green / blue, white.
    file_explorer_image_preview.pixels[0] = 255;
    file_explorer_image_preview.pixels[3] = 255;
    file_explorer_image_preview.pixels[5] = 255;
    file_explorer_image_preview.pixels[7] = 255;
    file_explorer_image_preview.pixels[10] = 255;
    file_explorer_image_preview.pixels[11] = 255;
    file_explorer_image_preview.pixels[12] = 255;
    file_explorer_image_preview.pixels[13] = 255;
    file_explorer_image_preview.pixels[14] = 255;
    file_explorer_image_preview.pixels[15] = 255;
    upload_result: LoadFileExplorerImagePreviewResult = .{
        success=true,
        width=file_explorer_image_preview.width,
        height=file_explorer_image_preview.height,
        pixels=file_explorer_image_preview.pixels,
    };
    if !File_Explorer_Image_Preview_Upload_Result_To_GPU(*upload_result) {
        File_Explorer_Image_Preview_Clear();
        Log_Error("image preview smoke test could not upload its deterministic texture");
        return false;
    }
    file_explorer_image_preview.pixels = .{};
    file_explorer_image_preview.texture = upload_result.texture;

    Begin_Draw_Frame(true);
    Render_File_Explorer_Image_Preview(.{0, 0}, .{64, 64});
    glFinish();
    uploaded_sample: [4]u8;
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, file_explorer_image_preview.texture);
    glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, uploaded_sample.data);
    glReadBuffer(GL_BACK);
    top_left, top_right, bottom_left, bottom_right: [4]u8;
    glReadPixels(16, window.height-16, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, top_left.data);
    glReadPixels(48, window.height-16, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, top_right.data);
    glReadPixels(16, window.height-48, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, bottom_left.data);
    glReadPixels(48, window.height-48, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, bottom_right.data);
    glReadBuffer(GL_FRONT);
    File_Explorer_Image_Preview_Clear();

    uploaded_red := uploaded_sample[0] == 255 && uploaded_sample[1] == 0 && uploaded_sample[2] == 0 && uploaded_sample[3] == 255;
    if !uploaded_red {
        Log_Error("image preview smoke test uploaded texture sample was rgba=(%, %, %, %)", uploaded_sample[0], uploaded_sample[1], uploaded_sample[2], uploaded_sample[3]);
        return false;
    }
    rendered_expected := top_left[0] >= 245 && top_left[1] <= 10 && top_left[2] <= 10 && top_left[3] == 255
        && top_right[0] <= 10 && top_right[1] >= 245 && top_right[2] <= 10 && top_right[3] == 255
        && bottom_left[0] <= 10 && bottom_left[1] <= 10 && bottom_left[2] >= 245 && bottom_left[3] == 255
        && bottom_right[0] >= 245 && bottom_right[1] >= 245 && bottom_right[2] >= 245 && bottom_right[3] == 255;
    if !rendered_expected {
        Log_Error("image preview smoke test corner samples were tl=(%, %, %, %), tr=(%, %, %, %), bl=(%, %, %, %), br=(%, %, %, %)", top_left[0], top_left[1], top_left[2], top_left[3], top_right[0], top_right[1], top_right[2], top_right[3], bottom_left[0], bottom_left[1], bottom_left[2], bottom_left[3], bottom_right[0], bottom_right[1], bottom_right[2], bottom_right[3]);
        return false;
    }
    Log("production image preview smoke test passed");
    return true;
}
