FileExplorerPreviewKind :: enum u8 {
    NONE;
    TEXT;
    IMAGE;
    SCENE;
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

Render_File_Explorer_Image_Preview :: (ul: IntVector2, lr: IntVector2) {
    if file_explorer_image_preview.width <= 0 || file_explorer_image_preview.height <= 0 {
        return;
    }

    // Image previews are a 2D overlay. They must not compete with the
    // checkerboard or a previously rendered scene in the depth buffer.
    Disable_Depth_Test();
    defer Enable_Depth_Test();

    if file_explorer_image_preview.texture == 0 {
        if file_explorer_image_preview.pixels.count == 0 {
            return;
        }
        glGenTextures(1, *file_explorer_image_preview.texture);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, file_explorer_image_preview.texture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        // Simp's font uploader leaves this at its atlas stride. Our decoded
        // RGBA pixels are tightly packed, so retaining that state makes GL
        // read past the image allocation when a preview texture is created.
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(GL_TEXTURE_2D, 0, cast(s32)GL_RGBA8, xx file_explorer_image_preview.width, xx file_explorer_image_preview.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, file_explorer_image_preview.pixels.data);
        free(file_explorer_image_preview.pixels.data);
        file_explorer_image_preview.pixels = .{};
    }

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
    || source_result.pixels.count != cast(s64)source_result.width * cast(s64)source_result.height * 4 {
        Log_Error("image preview smoke test could not load screenshot.png");
        if source_result.pixels.data != null free(source_result.pixels.data);
        return false;
    }
    free(source_result.pixels.data);

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
