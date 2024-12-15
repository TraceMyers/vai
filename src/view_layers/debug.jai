
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

    if history.count > 0 then for 0..history.count-1 {
        artifact := Peek_Back_Minus(history, xx it);
        if artifact.raw_text_count == 0 {
            Append_Line(buf, "");
        } else {
            bin := Get_Bin(*undo_redo_text, artifact.raw_text_id);
            bin.count = artifact.raw_text_count;
            temp_utf32_array := Temp_Buffer(u32, artifact.raw_text_count);
            for bin {
                temp_utf32_array[it_index] = Remove_Modifier_Flags(it);
            }
            utf8 := Encode(As_String(temp_utf32_array), .UTF32, .UTF8);
            Append_Line(buf, utf8);
        }
    }

    return buf;
}