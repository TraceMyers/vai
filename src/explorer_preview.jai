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

    Set_Image_Shader_Texture(file_explorer_image_preview.texture);
    Render_Quad(image_ul, image_lr, .{rgb=fRGB_WHITE, a=1.0}, .{0, 0}, .{1, 1});
    Flush_Draws();
}
