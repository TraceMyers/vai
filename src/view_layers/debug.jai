
Render_Layer :: (using tb_view: *DebugView, is_active: bool, render_pass: ViewRenderPass) {
    if render_pass == {
    case .BACKGROUND;
        Render_Quad(Upper_Left(), Lower_Right(), .{rgb=file_editor_background_color, a=1.0});
    case .TEXT;
        Render_Debug_View_Text(tb_view, is_active, render_pass);
    }
}

Render_Debug_View_Text :: (using tb_view: *DebugView, is_active: bool, render_pass: ViewRenderPass) {
    // assuming history thing

    renderer: TextRenderer;
    view_layer := View_Layer_From_Data(xx tb_view);
    Initialize_Text_Renderer(*renderer, view_layer);

    text_buffer := Layer_Text_Buffer(view_layer);
    Render_Text_Buffer_Lines(*renderer, text_buffer, true);
}

Temp_Text_Buffer :: (history: *CircularBuffer(ChangeArtifact)) -> *TextBuffer {
    buf: *TextBuffer = xx talloc(size_of(TextBuffer));
    Assign_Bin_Pool_Allocator(*buf.line_pool, temp);
    buf.lines.allocator = temp;
    Bin_Pool_Initialize(*buf.line_pool);

    if history.count == 0 then return buf;

    artifact := Peek_Back(history);
    if history.count > 0 then for 0..history.count-1 {
        if artifact.input_text.count == 0 && artifact.deleted_text.count == 0 {
            Append_Line(buf, "");
        } else {
            bin: []u32;
            if artifact.input_text.count > 0 {
                bin = Get_Bin(*undo_redo_text, artifact.input_text.bin_id);
                input_utf8 := Utf8_From_Modified_Utf32_Array(bin, artifact.input_text.count);
                input_prefixed := Prefix_Postfix_String(input_utf8,     tprint("input   [%], cursor (%, %): [", it, artifact.end_position.x, artifact.end_position.y), "]");
                Append_Line(buf, input_prefixed);
            }
            if artifact.deleted_text.count > 0 {
                bin = Get_Bin(*undo_redo_text, artifact.deleted_text.bin_id);
                deleted_utf8 := Utf8_From_Modified_Utf32_Array(bin, artifact.deleted_text.count);
                deleted_prefixed := Prefix_Postfix_String(deleted_utf8, tprint("deleted [%], cursor (%, %): [", it, artifact.end_position.x, artifact.end_position.y), "]");
                Append_Line(buf, deleted_prefixed);
            }
        }
        artifact = Seek_Back(history, artifact);
    }

    return buf;
}