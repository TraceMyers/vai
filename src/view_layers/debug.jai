
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

    If_Match_Sequence_Then_Print_String :: (builder: *String_Builder, pattern: []u32, text: string, text_to_print: string, str_index: *s64) -> bool {
        for pattern {
            if str_index.* + it_index >= text.count || text[str_index.* + it_index] != it {
                return false;
            }
        }
        print_to_builder(builder, text_to_print);
        str_index.* = str_index.* + PLATFORM_CARRIAGE_RETURN.count - 1;
        return true;
    }

    Process_Utf32_Bin :: (bin: []u32, prefix: string, artifact: *ChangeArtifact, artifact_index: s64, bin_count: s64) -> string {
        input_utf8 := Utf8_From_Modified_Utf32_Array(bin, bin_count);
        full_prefix := tprint("%   [%], cursor (%, %): [", prefix, artifact_index, artifact.end_position.x, artifact.end_position.y);
        text := Prefix_Postfix_String(input_utf8, full_prefix, "]");

        builder: String_Builder;
        builder.allocator = temp;
        for i : 0..text.count-1 {
            if If_Match_Sequence_Then_Print_String(*builder, PLATFORM_CARRIAGE_RETURN, text, "{CR}", *i) then continue;
            if If_Match_Sequence_Then_Print_String(*builder, ESCAPE_CODE_SEQUENCE, text, "{ESC}", *i) then continue;
            if If_Match_Sequence_Then_Print_String(*builder, u32.[#char "\t"], text, "{TAB}", *i) then continue;
            char_to_print := string.{1, text.data + i};
            print_to_builder(*builder, "%", char_to_print);
        }
        return builder_to_string(*builder);
    }

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
                input_processed := Process_Utf32_Bin(bin, "input", artifact, it, artifact.input_text.count);
                Append_Line(buf, input_processed);
            }
            if artifact.deleted_text.count > 0 {
                bin = Get_Bin(*undo_redo_text, artifact.deleted_text.bin_id);
                deleted_processed := Process_Utf32_Bin(bin, "deleted", artifact, it, artifact.deleted_text.count);
                Append_Line(buf, deleted_processed);
            }
        }
        artifact = Seek_Back(history, artifact);
    }

    return buf;
}