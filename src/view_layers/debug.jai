
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

    back_artifact := Peek_Back(history);
    middle_artifact := Peek_Middle(history);
    front_artifact := Peek_Front(history);

    back_index := Element_Index(back_artifact, history.items);
    middle_index := Element_Index(middle_artifact, history.items);
    front_index := Element_Index(front_artifact, history.items);

    Append_Line(buf, tprint("front index: %, middle index: %, back index: %", front_index, middle_index, back_index));
    Append_Line(buf, "");

    place_buffer: [3]u8;
    place_str := string.{3, place_buffer.data};

    for 0..history.items.count-1 {
        artifact := *history.items[it];
        is_front := artifact == front_artifact;
        is_middle := artifact == middle_artifact;
        is_back := artifact == back_artifact;
        place_str[0] = ub(ifx is_front then #char "F" else #char " ");
        place_str[1] = ub(ifx is_middle then #char "M" else #char " ");
        place_str[2] = ub(ifx is_back then #char "B" else #char " ");
        artifact_index := Element_Index(artifact, history.items);

        prefix := ifx found_middle then " past " else "future";
        if artifact.lines.count == 0 {
            fixed := tprint("[%/%/%/%] (%) : []", i, artifact_index, prefix, place_str, "");
            Append_Line(buf, fixed);
        } else for artifact.lines {
            bin: []u8;
            if it.count > 0 {
                bin = Get_Bin(*undo_redo_text, *it.bin_id);
                bin.count = it.count;
            }
            fixed := Prefix_Postfix_String(As_String(bin), tprint("[%/%/%/%] (%) : [", i, artifact_index, prefix, place_str, it.flags), "]");
            Append_Line(buf, fixed);
        }
        Append_Line(buf, "");
        found_middle |= is_middle;
        i += 1;
    }

    return buf;
}