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
    if render_pass == {
    case .BACKGROUND;
        Render_File_Explorer_Background(file_explorer, is_active);
    case .TEXT;
        Render_File_Explorer_Text(file_explorer, is_active);
    case .LINES;
        Render_File_Explorer_Lines(file_explorer, is_active);
    }
}

Render_File_Explorer_Background :: (using file_explorer: *FileExplorer, is_active: bool) {
    Render_Quad(Upper_Left(), Lower_Right(), .{rgb=file_explorer_background_color, a=1.0});
}

Render_File_Explorer_Text :: (using file_explorer: *FileExplorer, is_active: bool) {
    view_layer := View_Layer_From_Data(xx file_explorer);

    ul := Upper_Left();
    lr := Lower_Right();

    boxes: FileExplorerBoxes = ---;
    Calculate_File_Explorer_Boxes(*boxes, File_Explorer_Preview_Proportion(file_explorer));
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
                file_explorer.directory = upper_path_true;
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

    clear_file_explorer_preview := true;
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
        succeess, left, ext := split_from_right(item.name, #char ".");
        if ext.count > 0 {
            try_load_preview: bool;
            on_selected_line := line_y == cursor.y;
            alpha := ifx on_selected_line then 0.8 else 0.5;
            ext = To_Lower_Temp(ext);
            if Is_Basic_Text_File_Extension(ext) {
                Draw_Text_File_Icon(*renderer, 0, line_y, alpha);
                try_load_preview = on_selected_line;
            } else if Is_Code_File_Extension(ext) {
                Draw_Code_File_Icon(*renderer, 0, line_y, alpha);
                try_load_preview = on_selected_line;
            } else if Is_Binary_File_Extension(ext) {
                Draw_Binary_File_Icon(*renderer, 0, line_y, alpha);
            } else {
                Draw_Unknown_File_Icon(*renderer, 0, line_y, alpha);
            }

            if on_selected_line {
                clear_file_explorer_preview = false;
            }
            if file_explorer_preview_available {
                if try_load_preview {
                    full_path := tprint("%/%", working_path, item.name);
                    if file_explorer_text_preview.file_path != full_path {
                        request_data := LoadFileExplorerPreviewRequest.{copy_string(full_path)};
                        request := AsyncTaskRequest.{type=.LOAD_FILE_EXPLORER_PREVIEW, load_file_explorer_preview=request_data};
                        Make_Unique_Thread_Work_Request(request);
                    }
                } else if on_selected_line {
                    clear_file_explorer_preview = true;
                }
            }
        }
        line_y += 1;
        
        if recreate_directory_list {
            name := tprint("   %", item.name);
            Append_Line(buf, name, false);
        }
    }

    if clear_file_explorer_preview {
        Clear_Text_Buffer(*file_explorer_text_preview, true);
    }

    // draw text
    if file_explorer.preview_vertical_proportion != .FULL {
        Render_Text_Buffer_Lines(view_layer, *renderer, buf, false);
    }
    Flush_Draws();

    Cursor_Scroll(View_Layer_From_Data(xx file_explorer), *renderer, buf);

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

    if file_explorer_preview_available 
    && file_explorer_text_preview.lines.count > 0 
    && file_explorer.preview_vertical_proportion != .NONE {
        Set_View_Scissor(ul, lr);
        Set_View_Scissor(boxes.preview_ul, boxes.preview_lr);
        renderer = .{};
        save_view_position := view_layer.view_position;
        view_layer.view_position = .{};
        Initialize_Text_Renderer(*renderer, view_layer, 0);
        view_layer.view_position = save_view_position;
        // renderer.cursor_pos = .{};
        Render_Text_Buffer_Lines(null, *renderer, *file_explorer_text_preview, false);
        Flush_Draws();
    }
}

Render_File_Explorer_Lines :: (using file_explorer: *FileExplorer, is_active: bool) {
    boxes: FileExplorerBoxes = ---;
    Calculate_File_Explorer_Boxes(*boxes, File_Explorer_Preview_Proportion(file_explorer));
    Render_Quad_Lines(boxes.outer_ul, boxes.outer_lr, .{rgb=fRGB_WHITE, a=0.8});
    view_position := View_Layer_From_Data(xx file_explorer).view_position;
    if view_position.y == 0.0 {
        file_explorer.directory_list_outline_alpha = min(file_explorer.directory_list_outline_alpha + Smoothed_Delta_Time() * DIRECTORY_LIST_ALPHA_FADE_SPEED, DIRECTORY_LIST_ALPHA_MAX);
    } else {
        file_explorer.directory_list_outline_alpha = max(file_explorer.directory_list_outline_alpha - Smoothed_Delta_Time() * DIRECTORY_LIST_ALPHA_FADE_SPEED, 0.0);
    }
    Render_Quad_Lines(boxes.directory_list_ul, boxes.directory_list_lr, .{rgb=fRGB_WHITE, a=file_explorer.directory_list_outline_alpha});
    Render_Quad_Lines(boxes.preview_ul, boxes.preview_lr, .{rgb=fRGB_WHITE, a=0.3});
}

Process_Text_Input :: (using file_explorer: *FileExplorer, utf32: []u32) {
    if text_buffer < 0 then return;
    buf := *file_buffers.items[text_buffer];
    Insert_Code_Points(buf, cursor.y, cursor.x, utf32, false);
    for 0..utf32.count-1 {
        Cursor_Scroll_Right();
    }
}

File_Explorer_Preview_Proportion :: (file_explorer: *FileExplorer) -> float {
    if file_explorer.preview_vertical_proportion == {
    case .NONE;
        return 0.0;
    case .ONE_QUARTER;
        return 0.25;
    case .HALF;
        return 0.5;
    case .THREE_QUARTERS;
        return 0.75;
    case .FULL;
        return 1.0;
    }
    return 0.0;
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

Calculate_File_Explorer_Boxes :: (using boxes: *FileExplorerBoxes, preview_proportion: float) {
    outer_ul = Upper_Left();
    outer_lr = Lower_Right();
    outer_ul.x += 4;
    outer_ul.y += 14;
    outer_lr.x -= 4;
    outer_lr.y -= 4;

    directory_list_ul = outer_ul;
    directory_list_lr = outer_lr;
    directory_list_ul.x += 5;
    directory_list_ul.y += Integer_Option_Value(.FONT_SIZE) * 2;
    directory_list_lr.x -= 5;
    directory_list_lr.y = outer_ul.y + cast(s32)((outer_lr.y - outer_ul.y) * (1.0 - preview_proportion));

    preview_ul = directory_list_ul;
    preview_lr = directory_list_lr;
    preview_ul.y = directory_list_lr.y + 5;
    preview_lr.y = outer_lr.y - 5;
}

FileExplorerBoxes :: struct {
    outer_ul: IntVector2;
    outer_lr: IntVector2;
    directory_list_ul: IntVector2;
    directory_list_lr: IntVector2;
    preview_ul: IntVector2;
    preview_lr: IntVector2;
}

DIRECTORY_LIST_ALPHA_MAX :: 0.3;
DIRECTORY_LIST_ALPHA_FADE_SPEED :: 2.2;