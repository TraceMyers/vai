
Render_Layer :: (using file_editor: *FileEditor, is_active: bool, render_pass: ViewRenderPass) {
    if render_pass == {
    case .BACKGROUND;
        Render_File_Editor_Background(file_editor, is_active);
    case .LINES;
        Render_File_Editor_Lines(file_editor, is_active);
    case .TEXT;
        Render_File_Editor_Text(file_editor, is_active);
    case .FOREGROUND;
        Render_File_Editor_Foreground(file_editor, is_active);
    case;
    }
}

Render_File_Editor_Background :: (using file_editor: *FileEditor, is_active: bool) {
    Render_Quad(Upper_Left(), Lower_Right(), .{rgb=file_editor_background_color, a=1.0});

    if vi_mode == .VISUAL && is_active {
        renderer: TextRenderer;
        view_layer := View_Layer_From_Data(xx file_editor);
        Initialize_Text_Renderer(*renderer, view_layer);
        text_buffer := *file_buffers.items[file_editor.file_buffer];
    
        Render_Text_Selection_Blocks(*renderer, text_buffer, *cursor);
        Set_Shader_For_Color();
    }
}

Render_File_Editor_Lines :: (using file_editor: *FileEditor, is_active: bool) {
    Render_Quad_Lines(Upper_Left(), Lower_Right(), file_editor_outline_color);
    // TODO: line numbers option
    Render_Gutter_Separator_Line(file_editor_outline_color);
}

Render_File_Editor_Text :: (using file_editor: *FileEditor, is_active: bool) {
    if file_editor.file_buffer < 0 then return;

    renderer: TextRenderer;
    view_layer := View_Layer_From_Data(xx file_editor);
    Initialize_Text_Renderer(*renderer, view_layer);

    text_buffer := *file_buffers.items[file_editor.file_buffer];
    Render_Text_Buffer_Lines(*renderer, text_buffer, true);

    if is_active {
        Flush_Draws();
        cursor.style = ifx vi_mode == .INSERT then .VERTICAL_LINE else .BLOCK;
        Render_Text_Cursor(*renderer, *file_editor.cursor);
        Set_Shader_For_Text();
    }
}

Render_File_Editor_Foreground :: (using file_editor: *FileEditor, is_active: bool) {
    if file_editor.file_buffer < 0 || !is_active then return;
    view_layer := View_Layer_From_Data(xx file_editor);
    text_buffer := *file_buffers.items[file_editor.file_buffer];
    Render_Scroll_Bar(view_layer, text_buffer);
}

Process_Text_Input :: (using file_editor: *FileEditor, utf32: []u32) {
    if file_editor.file_buffer < 0 then return;
    text_buffer := *file_buffers.items[file_editor.file_buffer];
    Insert_Code_Points(text_buffer, cursor.y, cursor.x, utf32);
    for 0..utf32.count-1 {
        Cursor_Scroll_Right();
    }
}