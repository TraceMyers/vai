// TODO: directory tracking by ID rather than by string
// OpenFileById() and GetFileInformationByHandleEx().
// GetFileInformationByHandleEx :: (hFile: HANDLE, FileInformationClass: FILE_INFO_BY_HANDLE_CLASS, lpFileInformation: *void, dwBufferSize: u32) -> BOOL #foreign kernel32;
// TODO: make this interface more flexy, less magic numbery
// how typing path works:
// - all editing happens in a false top row, which represents the end of the path
//      - if the buffer has been validated and is unchanged, the directory list remains the same, otherwise it goes up a directory
//      - if the buffer is empty and you backspace, the super-directory becomes the edited directory
//      - if you stop editing and the directory isn't valid, the buffer is emptied

Render_Layer :: (using file_explorer: *FileExplorer, is_active: bool, render_pass: ViewRenderPass) {
    view := *view_pool.items[tool_view_id];
    if view.viewport.left <= 0.0 {
        return;
    }
    boxes: FileExplorerBoxes = ---;
    Calculate_File_Explorer_Boxes(*boxes, File_Explorer_Preview_Proportion(file_explorer), file_explorer.preview_hidden);
    if render_pass == {
    case .BACKGROUND;
        Render_File_Explorer_Background(file_explorer, is_active);
    case .TEXT;
        Render_File_Explorer_Text(file_explorer, is_active);
    case .LINES;
        Render_File_Explorer_Lines(file_explorer, is_active);
    }
    if file_explorer.preview_hidden {
        rendering_scissor_ul = boxes.preview_ul;
        rendering_scissor_lr = boxes.preview_lr;
        if render_pass == .TEXT || render_pass == .FOREGROUND {
            Set_Scissor(rendering_scissor_ul, rendering_scissor_lr);
        }
        Render_Collapsed_Tab("file preview", .TOP, false, render_pass);
    }
}

Render_File_Explorer_Background :: (using file_explorer: *FileExplorer, is_active: bool) {
    Render_Quad(rendering_scissor_ul, rendering_scissor_lr, .{rgb=file_explorer_background_color, a=1.0});
}

Render_File_Explorer_Text :: (using file_explorer: *FileExplorer, is_active: bool) {
    view_layer := View_Layer_From_Data(xx file_explorer);

    ul := Upper_Left();
    lr := Lower_Right();

    boxes: FileExplorerBoxes = ---;
    Calculate_File_Explorer_Boxes(*boxes, File_Explorer_Preview_Proportion(file_explorer), file_explorer.preview_hidden);
    Set_View_Scissor(boxes.directory_list_ul, boxes.directory_list_lr);

    renderer: TextRenderer;
    Initialize_Text_Renderer(*renderer, view_layer, 8);
    renderer.screen_render_begin.y += 1;

    buf: *TextBuffer = Layer_Text_Buffer(view_layer);
    working_path := Temp_Copy_String(file_explorer.directory);

    // TODO: failure?

    recreate_directory_list := buf.file_path != working_path;
    keep_path_as_shown := false;

    if !recreate_directory_list {
        path_as_shown := Get_Line_Bytes(buf, 0);
        success_1, upper_path_as_shown, directory_as_shown := split_from_right(path_as_shown, #char "/");
        success_2, upper_path_true, directory_true := split_from_right(working_path, #char "/");
        if directory_as_shown != directory_true {
            if upper_path_as_shown == directory_true {
                // path being typed is editing the directory at the end of the path.
                // `upper_path_true` is derived from a temporary copy of the path.
                // The explorer owns this field across frames, so keep an owned copy
                // instead of leaving it pointing at temporary storage.
                File_Explorer_Set_Directory(upper_path_true);
                working_path = Temp_Copy_String(file_explorer.directory);
                recreate_directory_list = true;
                keep_path_as_shown = vi_mode == .INSERT;
            }
        }
    }

    success, directory_list := Directory_List(working_path);
    Convert_To_Forward_Slashes(working_path);

    if recreate_directory_list {
        top_line: string;
        if keep_path_as_shown {
            top_line = Temp_Copy_String(Get_Line_Bytes(buf, 0));
        } else {
            top_line = working_path;
        }
        Clear_Text_Buffer(buf, true);
        Initialize_Text_Buffer(buf, copy_string(working_path), 64, 64, false);
        Append_Line(buf, top_line, false);
        Append_Line(buf, "", false);
        File_Explorer_Reset_Cursor_On_Path(*file_explorer.cursor, buf);
    }

    Set_Shader_For_Blended_Color();

    selected_preview_kind := FileExplorerPreviewKind.NONE;
    selected_preview_path := "";
    line_y : s32 = 2;

    for item : directory_list {
        color: fRGBA;
        alpha := ifx line_y == cursor.y then 0.8 else 0.5;
        if item.is_directory {
            color = fRGBA.{rgb=.{0.94, 0.835, 0.57}, a=alpha};
        } else if item.is_symlink {
            color = fRGBA.{rgb=.{0.94, 0.57, 0.835}, a=alpha};
        } else {
            continue;
        }
        Draw_Folder_Icon(*renderer, 0, line_y, *color);
        line_y += 1;

        if recreate_directory_list {
            name := tprint("   %", item.name);
            Append_Line(buf, name, false);
        }
    }

    for item : directory_list {
        if item.is_directory || item.is_symlink {
            continue;
        }
        preview_kind := FileExplorerPreviewKind.NONE;
        _, _, ext := split_from_right(item.name, #char ".");
        if ext.count > 0 {
            ext = To_Lower_Temp(ext);
            preview_kind = File_Explorer_Preview_Kind_For_Extension(ext);
        }
        on_selected_line := line_y == cursor.y;
        alpha := ifx on_selected_line then 0.8 else 0.5;
        if Is_Basic_Text_File_Extension(ext) {
            Draw_Text_File_Icon(*renderer, 0, line_y, alpha);
        } else if Is_Code_File_Extension(ext) {
            Draw_Code_File_Icon(*renderer, 0, line_y, alpha);
        } else if Is_Binary_File_Extension(ext) {
            Draw_Binary_File_Icon(*renderer, 0, line_y, alpha);
        } else {
            Draw_Unknown_File_Icon(*renderer, 0, line_y, alpha);
        }

        if on_selected_line {
            selected_preview_kind = preview_kind;
            selected_preview_path = tprint("%/%", working_path, item.name);
        }
        line_y += 1;
        
        if recreate_directory_list {
            name := tprint("   %", item.name);
            Append_Line(buf, name, false);
        }
    }

    File_Explorer_Select_Preview(selected_preview_kind, selected_preview_path);

    // The directory list always retains a path-sized row, even when the
    // preview has been expanded to its maximum size.
    Render_Text_Buffer_Lines(view_layer, *renderer, buf, false);
    Render_File_Explorer_Forward_Path(file_explorer, *renderer);
    Flush_Draws();

    View_Scroll(View_Layer_From_Data(xx file_explorer), *renderer, buf);

    if file_explorer.cursor.y == 0 {
        if vi_mode == .NORMAL {
            path_view := Line_View(buf, 0);
            if view_layer.need_reinit {
                file_explorer.cursor.x = xx (path_view.count-1);
                Cursor_Back_Up_To_Slash(*file_explorer.cursor, path_view);
                view_layer.need_reinit = false;
            }
            end_x := file_explorer.cursor.x;
            if file_explorer.cursor.x <= path_view.count-2 for file_explorer.cursor.x..path_view.count-2 {
                if Is_Slash(path_view[it]) {
                    end_x -= 1;
                    break;
                }
                end_x += 1;
            }
            file_explorer.cursor.begin_selection = .{end_x, file_explorer.cursor.y};
            Render_Text_Selection_Blocks(*renderer, buf, *file_explorer.cursor);
        } else if vi_mode == .INSERT {
            cursor.style = .VERTICAL_LINE;
            Render_Text_Cursor(*renderer, *file_explorer.cursor);
        }
    } else {
        Render_Cursor_Line_Block(*renderer, *file_explorer.cursor, 0.18);
    }

    Set_Shader_For_Text();

    if !File_Explorer_Preview_Is_Visible(file_explorer) {
        return;
    }

    Set_View_Scissor(ul, lr);
    Set_View_Scissor(boxes.preview_ul, boxes.preview_lr);
    if file_explorer_preview_state == .LOADING {
        Render_File_Explorer_Loading_Preview(boxes.preview_ul, boxes.preview_lr);
    } else if file_explorer_preview_state == .UNAVAILABLE {
        Render_File_Explorer_Unavailable_Preview(boxes.preview_ul, boxes.preview_lr);
    } else if file_explorer_preview_state == .READY
    && selected_preview_kind == .TEXT
    && file_explorer_text_preview.lines.count > 0
    && file_explorer_text_preview.file_path == selected_preview_path {
        renderer = .{};
        save_view_position := view_layer.view_position;
        view_layer.view_position = .{};
        Initialize_Text_Renderer(*renderer, view_layer, 0);
        view_layer.view_position = save_view_position;
        // renderer.cursor_pos = .{};
        Render_Text_Buffer_Lines(null, *renderer, *file_explorer_text_preview, false);
        Flush_Draws();
    } else if file_explorer_preview_state == .READY
    && selected_preview_kind == .IMAGE
    && File_Explorer_Image_Preview_Is_For_File(selected_preview_path) {
        Render_File_Explorer_Image_Preview(boxes.preview_ul, boxes.preview_lr);
    } else if file_explorer_preview_state == .READY
    && selected_preview_kind == .SCENE
    && File_Explorer_Scene_Preview_Is_For_File(selected_preview_path) {
        Render_File_Explorer_Scene_Preview(boxes.preview_ul, boxes.preview_lr);
    }
}

Render_File_Explorer_Lines :: (using file_explorer: *FileExplorer, is_active: bool) {
    boxes: FileExplorerBoxes = ---;
    Calculate_File_Explorer_Boxes(*boxes, File_Explorer_Preview_Proportion(file_explorer), file_explorer.preview_hidden);
    Render_Quad_Lines(boxes.outer_ul, boxes.outer_lr, .{rgb=fRGB_WHITE, a=0.8});
    view_position := View_Layer_From_Data(xx file_explorer).view_position;
    if view_position.y == 0.0 {
        file_explorer.directory_list_outline_alpha = min(file_explorer.directory_list_outline_alpha + Smoothed_Delta_Time() * DIRECTORY_LIST_ALPHA_FADE_SPEED, DIRECTORY_LIST_ALPHA_MAX);
    } else {
        file_explorer.directory_list_outline_alpha = max(file_explorer.directory_list_outline_alpha - Smoothed_Delta_Time() * DIRECTORY_LIST_ALPHA_FADE_SPEED, 0.0);
    }
    Render_Quad_Lines(boxes.directory_list_ul, boxes.directory_list_lr, .{rgb=fRGB_WHITE, a=file_explorer.directory_list_outline_alpha});
    if File_Explorer_Preview_Is_Visible(file_explorer) {
        Render_Quad_Lines(boxes.preview_ul, boxes.preview_lr, .{rgb=fRGB_WHITE, a=0.3});
    }
}

Process_Text_Input :: (using file_explorer: *FileExplorer, utf32: []u32) {
    if text_buffer < 0 then return;
    buf := *file_buffers.items[text_buffer];
    Insert_Code_Points(buf, cursor.y, cursor.x, utf32, false);
    for 0..utf32.count-1 {
        Cursor_Scroll_Right();
    }
}

Render_File_Explorer_Forward_Path :: (file_explorer: *FileExplorer, renderer: *TextRenderer) {
    if vi_mode != .NORMAL || renderer.text_view_clip.y != 0 {
        return;
    }

    suffix := File_Explorer_Forward_Path_Suffix();
    if suffix.count == 0 {
        return;
    }

    render_x := renderer.align_info_main.screen_x + xx file_explorer.directory.count * renderer.screen_char_width;
    render_y := renderer.screen_render_begin.y;

    Render_Text_String_At(suffix, render_x, render_y, color=.{rgb=fRGB_WHITE, a=0.5});
}

File_Explorer_Preview_Proportion :: (file_explorer: *FileExplorer) -> float {
    return clamp(file_explorer.preview_vertical_proportion, 0.0, 1.0);
}

File_Explorer_Preview_Is_Visible :: (file_explorer: *FileExplorer) -> bool {
    return !file_explorer.preview_hidden && File_Explorer_Preview_Proportion(file_explorer) > 0.0;
}

File_Explorer_Directory_Minimum_Height :: () -> s32 {
    line_height: s32 = xx (get_baseline_height(font) * 4);
    line_height += xx (cast(float32)line_height * line_spacing_factor);
    return max(line_height, sdw(1));
}

File_Explorer_Preview_Maximum_Proportion :: (view_height: s32) -> float {
    outer_height := max(view_height - FILE_EXPLORER_OUTER_VERTICAL_PADDING * 2, 1);
    required_directory_height := File_Explorer_Directory_Minimum_Height()
        + FILE_EXPLORER_DIRECTORY_TOP_PADDING
        + FILE_EXPLORER_DIRECTORY_BOTTOM_PADDING;
    return clamp(1.0 - cast(float)required_directory_height / cast(float)outer_height, 0.0, 1.0);
}

Set_File_Explorer_Preview_Proportion :: (file_explorer: *FileExplorer, proportion: float, view_height: s32) {
    maximum := File_Explorer_Preview_Maximum_Proportion(view_height);
    clamped := clamp(proportion, 0.0, maximum);
    if clamped <= 0.0 {
        Hide_File_Explorer_Preview(file_explorer);
        return;
    }
    file_explorer.preview_hidden = false;
    file_explorer.preview_vertical_proportion = clamped;
    file_explorer.preview_saved_vertical_proportion = clamped;
}

Hide_File_Explorer_Preview :: (file_explorer: *FileExplorer) {
    if file_explorer.preview_hidden {
        return;
    }
    if file_explorer.preview_vertical_proportion > 0.0 {
        file_explorer.preview_saved_vertical_proportion = file_explorer.preview_vertical_proportion;
    }
    file_explorer.preview_hidden = true;
}

Show_File_Explorer_Preview :: (file_explorer: *FileExplorer, view_height: s32) {
    if !file_explorer.preview_hidden {
        return;
    }
    file_explorer.preview_hidden = false;
    restore_proportion := ifx file_explorer.preview_saved_vertical_proportion > 0.0
        then file_explorer.preview_saved_vertical_proportion
        else 0.5;
    maximum := File_Explorer_Preview_Maximum_Proportion(view_height);
    file_explorer.preview_vertical_proportion = clamp(restore_proportion, 0.01, maximum);
}

File_Explorer_Preview_Divider_Y :: (view_ul: IntVector2, view_lr: IntVector2, proportion: float) -> s32 {
    outer_ul_y := view_ul.y + FILE_EXPLORER_OUTER_VERTICAL_PADDING;
    outer_lr_y := view_lr.y - FILE_EXPLORER_OUTER_VERTICAL_PADDING;
    outer_height := max(outer_lr_y - outer_ul_y, 1);
    return outer_ul_y + cast(s32)(cast(float)outer_height * (1.0 - proportion));
}

File_Explorer_Preview_Proportion_From_Divider_Y :: (view_ul: IntVector2, view_lr: IntVector2, divider_y: s32) -> float {
    view_height := view_lr.y - view_ul.y;
    outer_ul_y := view_ul.y + FILE_EXPLORER_OUTER_VERTICAL_PADDING;
    outer_lr_y := view_lr.y - FILE_EXPLORER_OUTER_VERTICAL_PADDING;
    outer_height := max(outer_lr_y - outer_ul_y, 1);
    proportion := cast(float)(outer_lr_y - divider_y) / cast(float)outer_height;
    return clamp(proportion, 0.0, File_Explorer_Preview_Maximum_Proportion(view_height));
}

File_Explorer_Directory_List_Box :: (view_ul: IntVector2, view_lr: IntVector2, preview_proportion: float, preview_hidden := false) -> IntVector2, IntVector2 {
    saved_scissor_ul := rendering_scissor_ul;
    saved_scissor_lr := rendering_scissor_lr;
    rendering_scissor_ul = view_ul;
    rendering_scissor_lr = view_lr;
    defer {
        rendering_scissor_ul = saved_scissor_ul;
        rendering_scissor_lr = saved_scissor_lr;
    }

    boxes: FileExplorerBoxes = ---;
    Calculate_File_Explorer_Boxes(*boxes, preview_proportion, preview_hidden);
    return boxes.directory_list_ul, boxes.directory_list_lr;
}

File_Explorer_Preview_Box :: (view_ul: IntVector2, view_lr: IntVector2, preview_proportion: float, preview_hidden := false) -> IntVector2, IntVector2 {
    saved_scissor_ul := rendering_scissor_ul;
    saved_scissor_lr := rendering_scissor_lr;
    rendering_scissor_ul = view_ul;
    rendering_scissor_lr = view_lr;
    defer {
        rendering_scissor_ul = saved_scissor_ul;
        rendering_scissor_lr = saved_scissor_lr;
    }

    boxes: FileExplorerBoxes = ---;
    Calculate_File_Explorer_Boxes(*boxes, preview_proportion, preview_hidden);
    return boxes.preview_ul, boxes.preview_lr;
}

FileExplorerBoxes :: struct {
    outer_ul: IntVector2;
    outer_lr: IntVector2;
    directory_list_ul: IntVector2;
    directory_list_lr: IntVector2;
    preview_ul: IntVector2;
    preview_lr: IntVector2;
}

Calculate_File_Explorer_Boxes :: (using boxes: *FileExplorerBoxes, preview_proportion: float, preview_hidden := false) {
    outer_ul = Upper_Left();
    outer_lr = Lower_Right();
    outer_ul.x += FILE_EXPLORER_OUTER_HORIZONTAL_PADDING;
    outer_ul.y += FILE_EXPLORER_OUTER_VERTICAL_PADDING;
    outer_lr.x -= FILE_EXPLORER_OUTER_HORIZONTAL_PADDING;
    outer_lr.y -= FILE_EXPLORER_OUTER_VERTICAL_PADDING;

    directory_list_ul = outer_ul;
    directory_list_lr = outer_lr;
    directory_list_ul.x += FILE_EXPLORER_DIRECTORY_HORIZONTAL_PADDING;
    directory_list_ul.y += FILE_EXPLORER_DIRECTORY_TOP_PADDING;
    directory_list_lr.x -= FILE_EXPLORER_DIRECTORY_HORIZONTAL_PADDING;
    if preview_hidden {
        collapsed_height := min(Collapsed_View_Bar_Thickness(.TOP), outer_lr.y - outer_ul.y);
        directory_list_lr.y = outer_lr.y - collapsed_height;
    } else {
        directory_list_lr.y = File_Explorer_Preview_Divider_Y(Upper_Left(), Lower_Right(), preview_proportion);
    }

    preview_ul = directory_list_ul;
    preview_lr = directory_list_lr;
    if preview_hidden {
        preview_ul.x = outer_ul.x;
        preview_ul.y = directory_list_lr.y;
        preview_lr = outer_lr;
    } else if preview_proportion > 0.0 {
        preview_ul.y = directory_list_lr.y + FILE_EXPLORER_PREVIEW_SPLIT_PADDING;
        preview_lr.y = outer_lr.y - FILE_EXPLORER_PREVIEW_BOTTOM_PADDING;
    } else {
        preview_ul.y = outer_lr.y;
        preview_lr.y = outer_lr.y;
    }
}

DIRECTORY_LIST_ALPHA_MAX :: 0.3;
DIRECTORY_LIST_ALPHA_FADE_SPEED :: 2.2;
FILE_EXPLORER_OUTER_HORIZONTAL_PADDING :: 4;
FILE_EXPLORER_OUTER_VERTICAL_PADDING :: 4;
FILE_EXPLORER_DIRECTORY_HORIZONTAL_PADDING :: 5;
FILE_EXPLORER_DIRECTORY_TOP_PADDING :: 5;
FILE_EXPLORER_DIRECTORY_BOTTOM_PADDING :: 6;
FILE_EXPLORER_PREVIEW_SPLIT_PADDING :: 5;
FILE_EXPLORER_PREVIEW_BOTTOM_PADDING :: 5;
