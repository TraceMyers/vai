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

    outer_box_ul := ul;
    outer_box_lr := lr;
    outer_box_ul.x += 4;
    outer_box_ul.y += 14;
    outer_box_lr.x -= 9;
    outer_box_lr.y -= 404;
    Set_View_Scissor(outer_box_ul, outer_box_lr);

    renderer: TextRenderer;
    Initialize_Text_Renderer(*renderer, view_layer, 8);
    renderer.screen_render_begin.y += 1;

    buf: *TextBuffer = *file_buffers.items[file_explorer.text_buffer];
    working_directory := view_layer.file_explorer.directory;
    // TODO: failure?
    success, directory_list := Directory_List(working_directory);
    Convert_To_Forward_Slashes(working_directory);

    initializing_text := false;
    if buf.file_path != working_directory {
        initializing_text = true;
        Clear_Text_Buffer(buf, true);
        Initialize_Text_Buffer(buf, copy_string(working_directory), 64, 64, false);
        Append_Line(buf, working_directory, false);
        Append_Line(buf, "", false);
    }

    Set_Shader_For_Blended_Color();
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

        if initializing_text {
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
            alpha := ifx line_y == cursor.y then 0.8 else 0.5;
            ext = To_Lower_Temp(ext);
            if Is_Basic_Text_File_Extension(ext) {
                Draw_Text_File_Icon(*renderer, 0, line_y, alpha);
            } else if Is_Code_File_Extension(ext) {
                Draw_Code_File_Icon(*renderer, 0, line_y, alpha);
            } else if Is_Binary_File_Extension(ext) {
                Draw_Binary_File_Icon(*renderer, 0, line_y, alpha);
            } else {
                Draw_Unknown_File_Icon(*renderer, 0, line_y, alpha);
            }
        }
        line_y += 1;
        
        if initializing_text {
            name := tprint("   %", item.name);
            Append_Line(buf, name, false);
        }
    }

    // draw text
    Render_Text_Buffer_Lines(view_layer, *renderer, buf, false);
    Flush_Draws();

    Cursor_Scroll(View_Layer_From_Data(xx file_explorer), *renderer, *file_buffers.items[file_explorer.text_buffer]);

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
}

Render_File_Explorer_Lines :: (using file_explorer: *FileExplorer, is_active: bool) {
    outer_box_ul := Upper_Left();
    outer_box_lr := Lower_Right();
    outer_box_ul.x += 4;
    outer_box_ul.y += 14;
    outer_box_lr.x -= 4;
    outer_box_lr.y -= 4;
    Render_Quad_Lines(outer_box_ul, outer_box_lr, .{rgb=fRGB_WHITE, a=0.8});
    dir_inner_box_ul := outer_box_ul;
    dir_inner_box_lr := outer_box_lr;
    dir_inner_box_ul.x += 5;
    dir_inner_box_ul.y += 30;
    dir_inner_box_lr.x -= 5;
    dir_inner_box_lr.y -= 400;
    view_position := View_Layer_From_Data(xx file_explorer).view_position;
    if view_position.y == 0.0 {
        file_explorer.directory_list_outline_alpha = min(file_explorer.directory_list_outline_alpha + Smoothed_Delta_Time() * DIRECTORY_LIST_ALPHA_FADE_SPEED, DIRECTORY_LIST_ALPHA_MAX);
    } else {
        file_explorer.directory_list_outline_alpha = max(file_explorer.directory_list_outline_alpha - Smoothed_Delta_Time() * DIRECTORY_LIST_ALPHA_FADE_SPEED, 0.0);
    }
    Render_Quad_Lines(dir_inner_box_ul, dir_inner_box_lr, .{rgb=fRGB_WHITE, a=file_explorer.directory_list_outline_alpha});
    preview_inner_box_ul := dir_inner_box_ul;
    preview_inner_box_lr := dir_inner_box_lr;
    preview_inner_box_ul.y = dir_inner_box_lr.y + 5;
    preview_inner_box_lr.y = outer_box_lr.y - 5;
    Render_Quad_Lines(preview_inner_box_ul, preview_inner_box_lr, .{rgb=fRGB_WHITE, a=0.3});
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

DIRECTORY_LIST_ALPHA_MAX :: 0.3;
DIRECTORY_LIST_ALPHA_FADE_SPEED :: 2.2;