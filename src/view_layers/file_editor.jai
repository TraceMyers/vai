
Render_Layer :: (using file_editor: *FileEditor, is_active: bool, render_pass: ViewRenderPass) {
    if render_pass == {
    case .BACKGROUND;
        Render_Quad(Upper_Left(), Lower_Right(), .{rgb=file_editor_background_color, a=1.0});
    case .LINES;
        Render_File_Editor_Lines(file_editor, is_active);
    case .TEXT;
        Render_File_Editor_Text(file_editor, is_active);
    case;
    }
}

Render_File_Editor_Lines :: (using file_editor: *FileEditor, is_active: bool) {
    Render_Quad_Lines(Upper_Left(), Lower_Right(), file_editor_outline_color);
    // TODO: line numbers option
    gutter_width := Screen_Gutter_Width();
    gutter_line_ul := rendering_scissor_ul;
    gutter_line_ul.x += gutter_width;
    gutter_line_lr := rendering_scissor_lr;
    gutter_line_lr.x = gutter_line_ul.x;
    Render_Line(gutter_line_ul, gutter_line_lr, file_editor_outline_color);
}

Render_File_Editor_Text :: (using file_editor: *FileEditor, is_active: bool) {
    if file_editor.file_buffer < 0 then return;

    renderer: TextRenderer;
    view_layer := View_Layer_From_Data(xx file_editor);
    Initialize_Text_Renderer(*renderer, view_layer);

    text_buffer := *file_buffers.items[file_editor.file_buffer];
    Render_Text_Buffer_Lines(*renderer, text_buffer, true);
}

