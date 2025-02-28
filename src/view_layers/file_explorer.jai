
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
    view_layer.view_position.y = -1;

    ul := Upper_Left();
    lr := Lower_Right();
    // ul.x += 5;
    lr.x -= 10;
    Set_View_Scissor(ul, lr);

    renderer: TextRenderer;
    Initialize_Text_Renderer(*renderer, view_layer, 8);

    buf: *TextBuffer = *file_buffers.items[file_explorer.text_buffer];
    working_directory := get_working_directory();

    // #run log("type of text buffer : %", type_of(text_buffer));

    if buf.file_path != working_directory {
        Clear_Text_Buffer(buf, true);
        buf.file_path = copy_string(working_directory);

        directory := tprint("%", working_directory);
        Append_Line(buf, directory, false);
        Append_Line(buf, "", false);
        
        directory_list := file_list(working_directory, follow_directory_symlinks=false);
        for full_path : directory_list {
            success, left, right := split_from_right(full_path, #char "/");
            if success {
                item := tprint("  %", right);
                Append_Line(buf, item, false);
            }
        }
    }

    Render_Text_Buffer_Lines(*renderer, buf, false);
    Flush_Draws();

    // could just use this when looking at content list
    // Render_Cursor_Line_Block(*renderer, *file_explorer.cursor, 0.18);

    if file_explorer.cursor.y == 0 {

        path_view := Line_View(buf, 0);
        
        if view_layer.need_reinit {
            file_explorer.cursor.x = xx (path_view.count-1);
            view_layer.need_reinit = false;
        }

        slash_index := 0;
        for #v2 < 0..file_explorer.cursor.x {
            if path_view[it] == #char "\\" {
                slash_index = it;
                break;
            }
        }

        file_explorer.cursor.begin_selection = .{xx (slash_index + 1), file_explorer.cursor.y};
        Render_Text_Selection_Blocks(*renderer, buf, *file_explorer.cursor);
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
    Render_Quad_Lines(dir_inner_box_ul, dir_inner_box_lr, .{rgb=fRGB_WHITE, a=0.3});
    preview_inner_box_ul := dir_inner_box_ul;
    preview_inner_box_lr := dir_inner_box_lr;
    preview_inner_box_ul.y = dir_inner_box_lr.y + 5;
    preview_inner_box_lr.y = outer_box_lr.y - 5;
    Render_Quad_Lines(preview_inner_box_ul, preview_inner_box_lr, .{rgb=fRGB_WHITE, a=0.3});
}