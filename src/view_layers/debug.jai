
Render_Layer :: (using tb_view: *DebugView, is_active: bool, render_pass: ViewRenderPass) {
    if render_pass == {
    case .BACKGROUND;
        Render_Quad(Upper_Left(), Lower_Right(), .{rgb=file_editor_background_color, a=1.0});
    case .TEXT;
        Render_Debug_View_Text(tb_view, is_active, render_pass);
    }
}

Render_Debug_View_Text :: (using tb_view: *DebugView, is_active: bool, render_pass: ViewRenderPass) {
    renderer: TextRenderer;
    view_layer := View_Layer_From_Data(xx tb_view);
    Initialize_Text_Renderer(*renderer, view_layer);

    text_buffer := Layer_Text_Buffer(view_layer);
    Render_Text_Buffer_Lines(*renderer, text_buffer, true);
}

Temp_Text_Buffer :: (using tb_view: *DebugView) -> *TextBuffer {
    buf: *TextBuffer = xx talloc(size_of(TextBuffer));
    buf.* = .{};
    Assign_Bin_Pool_Allocator(*buf.line_pool, temp);
    buf.lines.allocator = temp;
    Bin_Pool_Initialize(*buf.line_pool);

    if tb_view.type == {
    case .UNDO_REDO;
        Create_Debug_View_Undo_Redo(buf);
    case .BIN_POOL;
        Create_Debug_View_Bin_Pool(buf);
    }

    return buf;
}

Create_Debug_View_Undo_Redo :: (out_buffer: *TextBuffer) {
    Init_Cursor_Proc_Or_Return();
    history := *text_buffer.change_history;
    buf := out_buffer;

    if Totally_Empty(history) then return;

    i := 0;
    found_middle := false;

    back_artifact := Peek_Back(history);
    middle_artifact := Peek_Middle(history);
    front_artifact := Peek_Front(history);

    back_index := Element_Index(back_artifact, history.items);
    middle_index := Element_Index(middle_artifact, history.items);
    front_index := Element_Index(front_artifact, history.items);

    Append_Line_To_Debug_Buffer(buf, tprint("front index: %, middle index: %, back index: %", front_index, middle_index, back_index));
    Append_Line_To_Debug_Buffer(buf, "");

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

        Append_Tack :: (tack: *BinTack, tack_prefix: string) #expand {
            bin: []u8;
            if tack.count > 0 {
                bin = Get_Bin(*undo_redo_text, *tack.bin_id);
                bin.count = tack.count;
            }
            fixed := Prefix_Postfix_String(As_String(bin), tprint("[%/%/%/%] (%) : [", i, tack_prefix, prefix, place_str, `it.flags), "]");
            Append_Line_To_Debug_Buffer(buf, fixed);
        }

        if artifact.lines.count == 0 {
            fixed := tprint("[%/%/%/%] (%) : []", i, artifact_index, prefix, place_str, "");
            Append_Line_To_Debug_Buffer(buf, fixed);
        } else for artifact.lines {
            Append_Tack(*it.undo_tack, "undo");
            // Append_Tack(*it.redo_tack, "redo");
        }
        Append_Line_To_Debug_Buffer(buf, "------------------ ");
        found_middle |= is_middle;
        i += 1;
    }
}

Create_Debug_View_Bin_Pool :: (out_buffer: *TextBuffer) {
    Init_Cursor_Proc_Or_Return();
    history := text_buffer.change_history;
    buf := out_buffer;

    // TODO: for top n visible lines
    for text_buffer.lines {
        Append_Line_To_Debug_Buffer(buf, tprint("line [%/%]: bytes: %, bin id: %", it_index, it.unique_id, it.byte_count, it.bin_id));
        if it_index == 50 {
            break;
        }
    }

    using text_buffer.line_pool;

    builder: String_Builder;
    builder.allocator = temp;
    first_byte: s32;
    byte_counter: s32;

    Append_Line_To_Debug_Buffer(buf, "");
    Append_Line_To_Debug_Buffer(buf, tprint("in use data / byte ct: %", trackers[0].in_use.count));

    for trackers[0].in_use {
        if byte_counter == 0 {
            byte := FormatInt.{value=first_byte, minimum_digits=6, padding=#char " "};
            bit  := FormatInt.{value=first_byte*8, minimum_digits=6, padding=#char " "};
            print_to_builder(*builder, "%/% :", byte, bit);
        }

        byte_str := tprint(" %", FormatInt.{value=it, minimum_digits=8, base=2});
        Reverse_String(byte_str);
        print_to_builder(*builder, byte_str);

        byte_counter += 1;
        if byte_counter == 8 {
            Append_Line_To_Debug_Buffer(buf, builder_to_string(*builder,,temp));
            byte_counter = 0;
            first_byte += 8;
        }
    }
    if byte_counter > 0 {
        Append_Line_To_Debug_Buffer(buf, builder_to_string(*builder,,temp));
    }

    collisions: [..]string;
    collisions.allocator = temp;
    first_byte = 0;
    byte_counter = 0;

    Append_Line_To_Debug_Buffer(buf, "");
    Append_Line_To_Debug_Buffer(buf, "projected in use data by bin id");

    for trackers[0].in_use {
        byte := FormatInt.{value=first_byte, minimum_digits=6, padding=#char " "};
        bit  := FormatInt.{value=first_byte*8, minimum_digits=6, padding=#char " "};
        print_to_builder(*builder, "%/% :|", byte, bit);

        byte_rep := s32.[-1, -1, -1, -1, -1, -1, -1, -1];
        first_bit := (first_byte + byte_counter) * 8;
        for text_buffer.lines {
            line := it;
            if it.bin_id.index >= first_bit && it.bin_id.index < first_bit + 8 {
                indexer := it.bin_id.index - first_bit;
                for idx : indexer..indexer+it.bin_id.bin_count-1 {
                    if byte_rep[idx] != -1 {
                        array_add(*collisions, tprint("collision at % between line % and %\n", it.bin_id.index + idx, line.unique_id, byte_rep[idx]));
                    } else {
                        byte_rep[idx] = xx line.unique_id;
                    }
                }
            }
        }

        for byte_rep {
            if it == -1 {
                print_to_builder(*builder, "     ");
            } else {
                print_to_builder(*builder, "% ", FormatInt.{value=it, minimum_digits=4, padding=#char " "});
            }
        }

        first_byte += 1;
        Append_Line_To_Debug_Buffer(buf, builder_to_string(*builder,,temp));
    }
    if byte_counter > 0 {
        Append_Line_To_Debug_Buffer(buf, builder_to_string(*builder,,temp));
    }

    Append_Line_To_Debug_Buffer(buf, "");
    Append_Line_To_Debug_Buffer(buf, "projected in use data collisions");
    for collisions {
        Append_Line_To_Debug_Buffer(buf, tprint("collision: %", it));
    }

    Append_Line_To_Debug_Buffer(buf, tprint("small mark:      %", small_mark));
    Append_Line_To_Debug_Buffer(buf, tprint("medium mark:     %", medium_mark));
    Append_Line_To_Debug_Buffer(buf, tprint("large mark:      %", large_mark));
    Append_Line_To_Debug_Buffer(buf, tprint("very large mark: %", very_large_mark));
}