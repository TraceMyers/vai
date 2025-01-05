
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

Temp_Text_Buffer :: (history: *OpposingCircularBuffer(TextChange)) -> *TextBuffer {
    buf: *TextBuffer = xx talloc(size_of(TextBuffer));
    Assign_Bin_Pool_Allocator(*buf.line_pool, temp);
    buf.lines.allocator = temp;
    Bin_Pool_Initialize(*buf.line_pool);

    if Totally_Empty(history) then return buf;

    i := 0;
    found_middle := false;
    artifact := Peek_Back(history);
    middle_artifact := Peek_Middle(history);
    front_artifact := Peek_Front(history);
    for 0..history.items.count-1 {
        is_middle := artifact == middle_artifact;
        prefix := ifx found_middle then " past " else "future";
        mid := ifx is_middle then "M" else " ";
        if artifact.lines.count == 0 {
            fixed := tprint("[%/%/%] (%) : []", i, prefix, mid, "");
            Append_Line(buf, fixed);
        } else for artifact.lines {
            bin: []u8;
            if it.count > 0 {
                bin = Get_Bin(*undo_redo_text, *it.bin_id);
                bin.count = it.count;
            }
            fixed := Prefix_Postfix_String(As_String(bin), tprint("[%/%/%] (%) : [", i, prefix, mid, it.flags), "]");
            Append_Line(buf, fixed);
        }
        Append_Line(buf, "");
        if artifact == front_artifact {
            break;
        }
        artifact = Seek_Back(history, artifact);
        found_middle |= is_middle;
        i += 1;
    }

    return buf;
}