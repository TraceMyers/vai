
Render_Layer :: (using file_explorer: *FileExplorer, is_active: bool, render_pass: ViewRenderPass) {
    if render_pass == {
    case .BACKGROUND;
        Render_File_Explorer_Background(file_explorer, is_active);
    case .TEXT;
        Render_File_Explorer_Text(file_explorer, is_active);
    }
}

Render_File_Explorer_Background :: (using file_explorer: *FileExplorer, is_active: bool) {
    Render_Quad(Upper_Left(), Lower_Right(), .{rgb=file_explorer_background_color, a=1.0});
}

Render_File_Explorer_Text :: (using file_explorer: *FileExplorer, is_active: bool) {
    view := *view_pool.items[tool_view_id];
    if view.viewport.left <= 0.0 {
        return;
    }

    view_layer := View_Layer_From_Data(xx file_explorer);
    view_layer.view_position.y = -1;

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
        Append_Line(buf, "  [up one directory]", false);
        
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

}