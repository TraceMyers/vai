
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
    outer_box_ul.y += 4;
    outer_box_lr.x -= 9;
    outer_box_lr.y -= 404;
    Set_View_Scissor(outer_box_ul, outer_box_lr);

    renderer: TextRenderer;
    Initialize_Text_Renderer(*renderer, view_layer, 8);
    renderer.screen_render_begin.y += renderer.screen_line_height - 1;

    buf: *TextBuffer = *file_buffers.items[file_explorer.text_buffer];
    working_directory := view_layer.file_explorer.directory;
    // TODO: faildure?
    success, directory_list := Directory_List(working_directory);
    Convert_To_Forward_Slashes(working_directory);

    if buf.file_path != working_directory {
        Clear_Text_Buffer(buf, true);
        Initialize_Text_Buffer(buf, copy_string(working_directory), 64, 64);

        Append_Line(buf, working_directory, false);
        Append_Line(buf, "", false);

        for item : directory_list {
            if !item.is_directory && !item.is_symlink {
                continue;
            }
            name := tprint("   %", item.name);
            Append_Line(buf, name, false);
        }
        for item : directory_list {
            if item.is_directory || item.is_symlink {
                continue;
            }
            name := tprint("   %", item.name);
            Append_Line(buf, name, false);
        }
    }

    // draw icons
    Set_Shader_For_Blended_Color();
    line_y : s32 = 2;
    for item : directory_list {
        name: string;
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
    }

    // draw text
    Render_Text_Buffer_Lines(*renderer, buf, false);
    Flush_Draws();

    Cursor_Scroll(View_Layer_From_Data(xx file_explorer), *renderer, *file_buffers.items[file_explorer.text_buffer]);

    if file_explorer.cursor.y == 0 {
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
    dir_inner_box_ul.y += 40;
    dir_inner_box_lr.x -= 5;
    dir_inner_box_lr.y -= 400;
    Render_Quad_Lines(dir_inner_box_ul, dir_inner_box_lr, .{rgb=fRGB_WHITE, a=0.3});
    preview_inner_box_ul := dir_inner_box_ul;
    preview_inner_box_lr := dir_inner_box_lr;
    preview_inner_box_ul.y = dir_inner_box_lr.y + 5;
    preview_inner_box_lr.y = outer_box_lr.y - 5;
    Render_Quad_Lines(preview_inner_box_ul, preview_inner_box_lr, .{rgb=fRGB_WHITE, a=0.3});
}