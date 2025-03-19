
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// data

TEXT_BUFFER_SMALL_CHUNK_LEN :: 24;
TEXT_REGISTER_SMALL_CHUNK_LEN :: 48;

file_buffers: DynamicPool(TextBuffer);

temp_utf32_buffer_pool: BinPool(TEXT_BUFFER_SMALL_CHUNK_LEN, u32); 
temp_utf32_buffers: [..]Utf32Buffer;

undo_redo_text: BinPool(16, u8);
register_text: BinPool(TEXT_REGISTER_SMALL_CHUNK_LEN, u32);
registers: TextRegisters;

file_explorer_text_preview: TextBuffer;
file_explorer_preview_available: bool;

small_strings : BinPool(16, u8);

// NOTE TO SELF: be careful not to alias data when working with bins inline then copying into the bin
// NOTE TO SELF: tab-expanded column is the only real column outside this file, but tab-expanded spaces are invalid to edit

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// init/shutdown

// for use with Scoped_Construct
Text_Buffers :: struct {

    Initialize :: () -> success: bool {
        Initialize(*file_buffers, 32);
        Assign_Bin_Pool_Allocator(*temp_utf32_buffer_pool, temp);
        Bin_Pool_Initialize(*undo_redo_text);
        Bin_Pool_Initialize(*register_text);
        Bin_Pool_Initialize(*small_strings);
        // for register keys 0-9, initialize them all with "";
        Circular_Buffer_Initialize(*registers.number_registers, 10, Cleanup_Text_Register, true);
        for 0..9 {
            Push_Back(*registers.number_registers, .{});
        }
        init(*registers.tack_map, 128);
        temp_utf32_buffers.allocator = temp;
        file_explorer_preview_available = true;
        return true;
    }

    Shutdown :: () {
        Shutdown(*file_buffers, Shutdown_Text_Buffer);
        Bin_Pool_Shutdown(*undo_redo_text);
        Bin_Pool_Shutdown(*small_strings);
        Circular_Buffer_Reset(*registers.number_registers);
        Bin_Pool_Shutdown(*register_text);
        deinit(*registers.tack_map);
        // Shutdown_Text_Buffer(*file_explorer_text_preview);
    }

}

Begin_Update_Text_Buffers :: () {
    Bin_Pool_Initialize(*temp_utf32_buffer_pool, 256);
}

End_Update_Text_Buffers :: () {
    Commit_And_Empty_Utf32_Buffers();
    Bin_Pool_Shutdown(*temp_utf32_buffer_pool);
}

Initialize_Text_Buffer :: (buffer: *TextBuffer, path: string, prealloc_lines := 0, prealloc_bins := 0, init_circular_buffer := true) {
    if prealloc_bins > 0 {
        Bin_Pool_Initialize(*buffer.line_pool, prealloc_bins);
    } else {
        Bin_Pool_Initialize(*buffer.line_pool);
    }
    if prealloc_lines > 0 {
        array_reserve(*buffer.lines, prealloc_lines);
    }
    buffer.file_path = path;
    if init_circular_buffer {
        Opposing_Circular_Buffer_Initialize(*buffer.change_history, settings_file_data.change_history_count, Cleanup_Text_Change, true);
    }
}

Shutdown_Text_Buffer :: no_inline (buffer: *TextBuffer) {
    Bin_Pool_Shutdown(*buffer.line_pool);
    array_reset(*buffer.lines);
    String_Reset(*buffer.file_path);
    Opposing_Circular_Buffer_Reset(*buffer.change_history);
}

Clear_Text_Buffer :: (using buffer: *TextBuffer, keep_allocations: bool) {
    if buffer != *file_explorer_text_preview {
        Commit_And_Empty_Utf32_Buffers();
    }
    if (keep_allocations) {
        array_reset_keeping_memory(*lines);
    } else {
        array_reset(*lines);
    }
    Bin_Pool_Shutdown(*line_pool, keep_allocations);
    String_Reset(*file_path);
    Opposing_Circular_Buffer_Reset(*buffer.change_history);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Get_File_Buffer_ID :: (file_path: string) -> s64 {
    existing_buffer := Find_Item(*file_buffers, file_path, (buf, path) => buf.file_path == path);
    if existing_buffer == -1 {
        existing_buffer = Load_File_Into_Buffer(file_path);
    }
    return existing_buffer;
}

Get_File_Buffer :: (file_path: string) -> *TextBuffer {
    existing_buffer := Get_File_Buffer_ID(file_path);
    return ifx existing_buffer == -1 then null else *file_buffers.items[existing_buffer];
}

Load_File_Into_Buffer :: (path: string) -> s64 {
    buf_index := Request_Item(*file_buffers);
    buffer := Get_Item(*file_buffers, buf_index);

    if Load_File_Into_Buffer(path, buffer) {
        return buf_index;
    }

    Return_Item(*file_buffers, buf_index);
    return -1;
}

Load_File_Into_Buffer :: (file_path: string, buffer: *TextBuffer, initialize_changes := true) -> bool {
    file_string, success := Read_Entire_File(file_path, true);
    if !success {
        Log_Error("unable to open [%]", file_path);
        return false;
    }

    line_len_total: s64;
    Count_Len_Total :: inline (line: *string, total: *s64) { total.* += line.count; }
    line_count := Process_Per_Line(file_string, Count_Len_Total, *line_len_total);

    INEFFICIENCY_FACTOR :: 1.25;
    expected_bin_ct := 32;
    if line_count != 0 {
        avg_line_len := line_len_total / line_count;
        expected_bin_ct = xx (cast(float32)(Div_Ceil(avg_line_len, 32) * line_count) * INEFFICIENCY_FACTOR);
    }
    Initialize_Text_Buffer(buffer, copy_string(file_path), line_count, expected_bin_ct, initialize_changes);

    in_main_thread := GetCurrentThreadId() == main_thread_index;

    if line_count != 0 {
        if in_main_thread {
            Append_Line_To_Buffer :: inline (line: *string, buffer: *TextBuffer) { Append_Line(buffer, line.*, false, false, true); }
            Process_Per_Line(file_string, Append_Line_To_Buffer, buffer);
        } else {
            Append_Line_To_Buffer :: inline (line: *string, buffer: *TextBuffer) { Append_Line(buffer, line.*, false, false, false); }
            Process_Per_Line(file_string, Append_Line_To_Buffer, buffer);
        }
    } else {
        if in_main_thread {
            Append_Line(buffer, .{}, false, false, true);
        } else {
            Append_Line(buffer, .{}, false, false, false);
        }
    }

    return true;
}

Save_Buffer_To_File :: (id: s64) {
    Commit_And_Empty_Utf32_Buffers();
    text_buffer := *file_buffers.items[id];

    // count bytes for allocation
    byte_count := 0;
    for 0..text_buffer.lines.count-1 {
        line_bytes := Get_Line_Bytes(text_buffer, it);
        byte_count += line_bytes.count + 1;
    }
    byte_count -= 1; // no newline at the end

    out_buffer := Temp_Buffer(u8, byte_count);
    dest := 0;
    for 0..text_buffer.lines.count-1 {
        line_bytes := Get_Line_Bytes(text_buffer, it);
        if line_bytes.count > 0 {
            memcpy(out_buffer.data + dest, line_bytes.data, line_bytes.count);
            dest += line_bytes.count;
        }
        if it != text_buffer.lines.count-1 {
            out_buffer[dest] = #char "\n";
            dest += 1;
        }
    }
    out_buffer.count = dest;

    write_entire_file(text_buffer.file_path, As_String(out_buffer));
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// add/remove lines and get/set line bytes

Append_Line_To_Debug_Buffer :: inline (buffer: *TextBuffer, line_str: string) {
    Append_Line(buffer, line_str, false, true);
}

Append_Line :: (buffer: *TextBuffer, line_str: string, is_change := true, $FOR_DEBUG := false, $EMPTY_UTF32_BUFFERS := true) {
    #if EMPTY_UTF32_BUFFERS {
        Commit_And_Empty_Utf32_Buffers();
    }
    #if FOR_DEBUG {
        array_add(*buffer.lines, .{unique_id=debug_line_id_counter});
        debug_line_id_counter += 1;
    } else {
        array_add(*buffer.lines, .{unique_id=line_id_counter});
        line_id_counter += 1;
    }
    Set_Line_Bytes(buffer, buffer.lines.count-1, line_str);
    if is_change then Add_Line_To_Change(buffer, buffer.lines.count-1, .INSERT_LINE);
}

// returns whether or not indentation was inserted
Insert_Line :: (buffer: *TextBuffer, i: s64, is_change := true, $FOR_DEBUG := false) -> bool {
    Commit_And_Empty_Utf32_Buffers();
    #if FOR_DEBUG {
        array_insert_at(*buffer.lines, .{unique_id=debug_line_id_counter}, i);
        debug_line_id_counter += 1;
    } else {
        array_insert_at(*buffer.lines, .{unique_id=line_id_counter}, i);
        line_id_counter += 1;
    }

    added_indent := false;
    if is_change {
        do_auto_indent := Bool_Option_Value(.AUTO_INDENT);
        if do_auto_indent {
            indent_level := Get_Indent_Level_From_Context(buffer, i);
            if indent_level > 0 {
                for 0..indent_level-1 {
                    Insert_Code_Point(buffer, i, it, #char "\t", false);
                }
                added_indent = true;
            }
        }
        Add_Line_To_Change(buffer, i, .INSERT_LINE);
    }
    return added_indent;
}

Remove_Line :: (buffer: *TextBuffer, line_index: s64, is_change := true, moving_backward := false) {
    if buffer.lines.count == 1 {
        Clear_Line(buffer, line_index, is_change);
        return;
    }
    if is_change {
        Add_Line_To_Change(buffer, line_index, .DELETE_LINE);
    }
    Commit_And_Empty_Utf32_Buffers();
    line := *buffer.lines[line_index];
    if line.bin_id.index != -1 {
        Release_Bin(*buffer.line_pool, *line.bin_id);
    }
    array_ordered_remove_by_index(*buffer.lines, line_index);
}

Get_Line_Bytes :: (buffer: *TextBuffer, line_index: s64) -> string {
    line := *buffer.lines[line_index];
    if line.bin_id.bin_count == 0 {
        return .{};
    } else {
        bin := Get_Bin(*buffer.line_pool, line.bin_id);        
        #if DEBUG_TEXT_BUFFERS {
            assert(bin.count >= line.byte_count);
        }
        return string.{count=line.byte_count, data=bin.data};
    }
}

Set_Line_Bytes :: (buffer: *TextBuffer, line_index: s64, line_str: string) {
    line := *buffer.lines[line_index];
    if line_str.count == 0 {
        if line.bin_id.bin_count != 0 {
            Release_Bin(*buffer.line_pool, *line.bin_id);
        }
        line.byte_count = 0;
    } else {
        if line.bin_id.bin_count == 0 {
            line.bin_id = Request_Bin(*buffer.line_pool, line_str.count);
        }
        assert(line.bin_id.index != -1);
        Set_Bin_Data(*buffer.line_pool, *line.bin_id, As_Array(line_str, u8));
        line.byte_count = xx line_str.count;
        // bytes := Get_Line_Bytes(buffer, line_index);
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// line utf32 temp buffers

Raw_Line_View :: (buffer: *TextBuffer, row: s64) -> []u32 {
    if buffer.lines.count == 0 then return .[];
    bytes := Get_Line_Bytes(buffer, row);
    utf32_str := Encode(bytes, .UTF8, .UTF32);
    return As_Array(utf32_str, u32);
}

Line_View :: (buffer: *TextBuffer, row: s64) -> []u32 {
    if buffer.lines.count == 0 then return .[];
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    return utf32_buffer.array;
}

Line_Count :: (buffer: *TextBuffer, row: s64) -> s64 {
    if buffer.lines.count == 0 then return 0;
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    return utf32_buffer.array.count;
}

Set_Utf32_Buffer_Data :: inline (utf32_buffer: *Utf32Buffer, data: []u32) {
    Set_Bin_Data(*temp_utf32_buffer_pool, *utf32_buffer.temp_bin_id, data);
    if utf32_buffer.temp_bin_id.index == -1 {
        assert(data.count == 0);
        utf32_buffer.array.data = null;
    } else {
        utf32_buffer.array.data = Get_Bin(*temp_utf32_buffer_pool, utf32_buffer.temp_bin_id).data;
    }
    utf32_buffer.array.count = data.count;
}

Expand_Utf32_Buffer_Tabs :: inline (utf32_buffer: *Utf32Buffer) {
    expanded := Expand_Tabs(utf32_buffer.array, 4, true);
    Set_Utf32_Buffer_Data(utf32_buffer, expanded);
}

Replace_Code_Point :: (buffer: *TextBuffer, row: s64, col: s64, code_point: u32, is_change := true) {
    if is_change then Add_Line_To_Change(buffer, row, 0);
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    assert(col < utf32_buffer.array.count);
    #if DEBUG_TEXT_BUFFERS {
        assert(!Is_Tab_Expanded_Space(utf32_buffer.array[col]));
    }
    replacing_tab := utf32_buffer.array[col] == #char "\t";
    utf32_buffer.array[col] = code_point;
    if replacing_tab {
        Collapse_Tabs_Inline(*utf32_buffer.array);
        Expand_Utf32_Buffer_Tabs(utf32_buffer);
    }
}

Try_Collapsed_Utf32_Unindent :: (buffer: *[]u32, evaluated_indent: s64) {
    if evaluated_indent <= 0 {
        return;
    }
    if buffer.count <= 1 {
        return;
    }
    counted_indent := 0;
    for 0..buffer.count - 1 {
        if buffer.*[it] != #char "\t" {
            break;
        }
        counted_indent += 1;
    }
    if counted_indent != evaluated_indent {
        return;
    }
    for 0..buffer.count - 2 {
        buffer.*[it] = buffer.*[it+1];
    }
    buffer.count -= 1;
}

Insert_Code_Point :: (buffer: *TextBuffer, row: s64, col: s64, code_point: u32, is_change := true) {
    if is_change then Add_Line_To_Change(buffer, row, 0);
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    assert(col <= utf32_buffer.array.count);
    #if DEBUG_TEXT_BUFFERS {
        if col < utf32_buffer.array.count {
            assert(!Is_Tab_Expanded_Space(utf32_buffer.array[col]));
        }
    }
    try_auto_unindent := Insert_Code_Point_Should_Try_Unindent(row, col, utf32_buffer, code_point);
    Resize_Utf32_Buffer(utf32_buffer, xx (utf32_buffer.array.count + 1));
    Collapse_Tabs_Inline_And_Insert(*utf32_buffer.array, col, code_point);
    if try_auto_unindent {
        cur_indent := Get_Indent_Level_From_Context(buffer, row);
        Try_Collapsed_Utf32_Unindent(*utf32_buffer.array, cur_indent);
    }
    Expand_Utf32_Buffer_Tabs(utf32_buffer);
}

Insert_Code_Points :: (buffer: *TextBuffer, row: s64, col: s64, code_points: []u32, is_change := true, is_line_join := false) {
    if code_points.count <= 0 then return;
    flags : LineChangeFlags = ifx is_line_join then .INSERT_FRONT else xx 0;
    if is_change then Add_Line_To_Change(buffer, row, flags);
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    assert(col <= utf32_buffer.array.count);
    #if DEBUG_TEXT_BUFFERS {
        if col < utf32_buffer.array.count {
            assert(!Is_Tab_Expanded_Space(utf32_buffer.array[col]));
        }
    }
    prev_count := utf32_buffer.array.count;
    try_auto_unindent := Insert_Code_Point_Should_Try_Unindent(row, col, utf32_buffer, code_points[0]);
    Resize_Utf32_Buffer(utf32_buffer, xx (utf32_buffer.array.count + code_points.count));
    utf32_buffer.array.count = prev_count; // below proc depends on this
    Collapse_Tabs_Inline_And_Insert(*utf32_buffer.array, col, code_points);
    if try_auto_unindent {
        cur_indent := Get_Indent_Level_From_Context(buffer, row);
        Try_Collapsed_Utf32_Unindent(*utf32_buffer.array, cur_indent);
    }
    Expand_Utf32_Buffer_Tabs(utf32_buffer);
}

Remove_Code_Point :: (buffer: *TextBuffer, row: s64, col: s64, is_change := true) {
    // TODO: check if line deletion
    if is_change {
        Add_Line_To_Change(buffer, row, 0);
    }
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    assert(col < utf32_buffer.array.count);
    #if DEBUG_TEXT_BUFFERS {
        assert(!Is_Tab_Expanded_Space(utf32_buffer.array[col]));
    }
    Collapse_Tabs_Inline_And_Remove(*utf32_buffer.array, col);
    Expand_Utf32_Buffer_Tabs(utf32_buffer);
}

Remove_Code_Points :: (buffer: *TextBuffer, row: s64, col: s64, count: s64, is_change := true) {
    // TODO: check if line deletion
    if is_change {
        Add_Line_To_Change(buffer, row, 0);
    }
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    assert(col < utf32_buffer.array.count);
    #if DEBUG_TEXT_BUFFERS {
        assert(!Is_Tab_Expanded_Space(utf32_buffer.array[col]));
    }
    Collapse_Tabs_Inline_And_Remove_Count(*utf32_buffer.array, col, count);
    Expand_Utf32_Buffer_Tabs(utf32_buffer);
}

Break_Line_At :: (buffer: *TextBuffer, row: s64, col: s64, is_change := true) -> added_indent: bool {
    added_indent := Insert_Line(buffer, row+1, is_change);
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    assert(col <= utf32_buffer.array.count);
    #if DEBUG_TEXT_BUFFERS {
        if col < utf32_buffer.array.count {
            assert(!Is_Tab_Expanded_Space(utf32_buffer.array[col]));
        }
    }
    if (col < utf32_buffer.array.count) {
        copy_down: []u32 = ---;
        copy_down.data = utf32_buffer.array.data + col;
        copy_down.count = utf32_buffer.array.count - col;
        Insert_Code_Points(buffer, row+1, 0, copy_down, is_change);
        Resize_Utf32_Buffer(utf32_buffer, xx col);
    }
    return added_indent;
}

Clear_Line :: (buffer: *TextBuffer, row: s64, is_change := true) {
    if is_change {
        Add_Line_To_Change(buffer, row, 0);
    }
    Clear_Line_Impl(buffer, row);
}

Clear_Line_Impl :: (buffer: *TextBuffer, row: s64) {
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    Resize_Utf32_Buffer(utf32_buffer, 0);
}

// gets the line in its current form, whether it is currently being edited (and thus has a utf32 buffer representing the changed version) or not
Get_Current_Utf8_For_Line :: (buffer: *TextBuffer, row: s64) -> string {
    utf32_buffer := Get_Utf32_Buffer(buffer, row, false);
    utf8_string: string;
    if utf32_buffer == null {
        utf8_string = Get_Line_Bytes(buffer, row);
    } else {
        // if we collapse  the tabs inline before copying, it will fuck up the temp buffer, which should have expanded tabs
        utf32_copy := Temp_Copy_Array(utf32_buffer.array);
        Collapse_Tabs_Inline(*utf32_copy);
        utf32_string := As_String(utf32_copy);
        utf8_string = Encode(utf32_string, .UTF32, .UTF8);
    }
    return utf8_string;
}

Expanded_To_Collapsed_Column :: (buffer: *TextBuffer, row: s32, col: s32) -> s32 {
    utf8_text := Get_Current_Utf8_For_Line(buffer, row);
    expanded_col: s32 = 0;
    unexpanded_col: s32 = col;
    for 0..utf8_text.count-1 {
        if utf8_text[it] == #char "\t" {
            // TODO: tab size
            expanded_col += 4 - (expanded_col % 4);
        } else {
            expanded_col += 1;
        }
        if expanded_col >= col {
            unexpanded_col = xx it;
        }
    }
    return unexpanded_col;
}

Collapsed_To_Expanded_Column :: (buffer: *TextBuffer, row: s32, col: s32) -> s32 {
    utf8_text := Get_Current_Utf8_For_Line(buffer, row);
    expanded_col: s32 = 0;
    iter_ct := min(utf8_text.count, col);
    for 0..iter_ct-1 {
        if utf8_text[it] == #char "\t" {
            // TODO: tab size
            expanded_col += 4 - (expanded_col % 4);
        } else {
            expanded_col += 1;
        }
    }
    return expanded_col;
}

Commit_Utf32_To_Line :: (utf32_buffer: *Utf32Buffer) {
    Collapse_Tabs_Inline(*utf32_buffer.array);
    utf32_string := As_String(utf32_buffer.array);
    utf8_string := Encode(utf32_string, .UTF32, .UTF8);
    if utf32_buffer.home_bin_id.index == -1 {
        utf32_buffer.home_bin_id = Request_Bin(*utf32_buffer.home_buffer.line_pool, utf32_buffer.array.count);
    } 
    if utf32_buffer.home_bin_id.index != -1 {
        Set_Bin_Data(*utf32_buffer.home_buffer.line_pool, *utf32_buffer.home_bin_id, As_Array(utf8_string, u8));
    }
    line := *utf32_buffer.home_buffer.lines[utf32_buffer.home_row];
    line.bin_id = utf32_buffer.home_bin_id;
    line.byte_count = xx utf8_string.count;
}

Remove_Utf32_Buffer :: (buffer: *TextBuffer, row: s64) {
    utf32_buffer := Get_Utf32_Buffer(buffer, row, false);
    if utf32_buffer != null {
        index := Element_Index(utf32_buffer, temp_utf32_buffers);
        if utf32_buffer.temp_bin_id.index != -1 {
            Release_Bin(*temp_utf32_buffer_pool, *utf32_buffer.temp_bin_id);
        }
        array_ordered_remove_by_index(*temp_utf32_buffers, index);
    }
}

Init_Utf32_Buffer_Data :: inline (utf32_buffer: *Utf32Buffer) {
    if utf32_buffer.temp_bin_id.index != -1 {
        bin := Get_Bin(*temp_utf32_buffer_pool, utf32_buffer.temp_bin_id);
        utf32_buffer.array.data = bin.data;
    } else {
        utf32_buffer.array.data = null;
        utf32_buffer.array.count = 0;
    }
}

Get_Utf32_Buffer :: (buffer: *TextBuffer, line_index: s64, $ALLOW_ALLOCATION := true) -> *Utf32Buffer {
    line := *buffer.lines[line_index];
    utf32_buffer: *Utf32Buffer;
    for temp_utf32_buffers {
        if it.line_id == line.unique_id {
            assert(it.home_bin_id == line.bin_id);
            utf32_buffer = *it;
            break;
        }
    }
    #if ALLOW_ALLOCATION {
        if utf32_buffer == null {
            utf32_buffer = Allocate_Utf32_Buffer(buffer, line_index);
        } else {
            Init_Utf32_Buffer_Data(utf32_buffer);
        }
    }
    return utf32_buffer;
}

Allocate_Utf32_Buffer :: (buffer: *TextBuffer, line_index: s64) -> *Utf32Buffer {
    line := *buffer.lines[line_index];
    utf32_buffer := array_add(*temp_utf32_buffers);
    utf32_buffer.home_buffer = buffer;
    utf32_buffer.home_row = xx line_index;
    utf32_buffer.line_id = line.unique_id;
    utf32_buffer.home_bin_id = line.bin_id;

    if line.byte_count > 0 {
        bytes := Get_Line_Bytes(buffer, line_index);
        utf32_string := Encode(bytes, .UTF8, .UTF32);
        utf32_array := As_Array(utf32_string, u32);
        expanded := Expand_Tabs(utf32_array, 4, true);
        utf32_buffer.temp_bin_id = Request_Bin(*temp_utf32_buffer_pool, expanded.count + 8);
        utf32_buffer.array.count = expanded.count;
        Set_Bin_Data(*temp_utf32_buffer_pool, *utf32_buffer.temp_bin_id, expanded);
    } else {
        return utf32_buffer;
    }

    Init_Utf32_Buffer_Data(utf32_buffer);

    return utf32_buffer;
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

Resize_Utf32_Buffer :: (utf32_buffer: *Utf32Buffer, count: u32) {
    if utf32_buffer.temp_bin_id.index == -1 {
        if count > 0 {
            utf32_buffer.temp_bin_id = Request_Bin(*temp_utf32_buffer_pool, count);
        }
    } else {
        Resize_Bin(*temp_utf32_buffer_pool, *utf32_buffer.temp_bin_id, count);
    }
    if utf32_buffer.temp_bin_id.index != -1 {
        bin := Get_Bin(*temp_utf32_buffer_pool, utf32_buffer.temp_bin_id);
        utf32_buffer.array.data = bin.data;
        utf32_buffer.array.count = count;
    } else {
        utf32_buffer.array.data = null;
        utf32_buffer.array.count = 0;
    }
}

// for appending into a buffer where the input and output buffer are the same.
Inline_Append_Code_Point :: inline (buffer: *[]u32, code_point: u32, iter_index: s64) {
    if Is_Tab_Expanded_Space(code_point) {
        return;
    } else if Is_Expanded_Tab(code_point) {
        Inline_Buffer_Append(buffer, #char "\t");
    } else if iter_index == buffer.count {
        // no need to copy, code point already in the right place
        buffer.count += 1;
        Strip_Markup_Inline(*(buffer.*[buffer.count-1]));
    } else {
        // copy back + increase count
        Inline_Buffer_Append(buffer, Strip_Markup(code_point));
    }
}

Inline_Append_Code_Point_No_Alias :: inline (buffer: *[]u32, code_point: u32) {
    if Is_Tab_Expanded_Space(code_point) {
        return;
    } else if Is_Expanded_Tab(code_point) {
        Inline_Buffer_Append(buffer, #char "\t");
    } else {
        Inline_Buffer_Append(buffer, Strip_Markup(code_point));
    }
}

Collapse_Tabs_Inline :: (data: *[]u32) {
    if data.count == 0 {
        return;
    }
    inline_buffer := Inline_Buffer(data.*);
    for data.* {
        Inline_Append_Code_Point(*inline_buffer, it, it_index);
    }
    data.count = inline_buffer.count;
}

Collapse_Tabs_Inline_And_Insert :: (data: *[]u32, col: s64, code_point: u32) {
    if data.count == 0 {
        return;
    }
    inline_buffer := Inline_Buffer(data.*);
    remember_code_point, prev_remember_code_point: u32;
    for i: 0..data.count-1 {
        if i < col {
            Inline_Append_Code_Point(*inline_buffer, data.*[i], i);
        } else if i == col {
            remember_code_point = data.*[i];
            Inline_Buffer_Append(*inline_buffer, Strip_Markup(code_point));
        } else {
            // from this point forward, appended code points may ovewrite the code points that are already in the buffer, so the in-buffer code points need to be copied out before appending.
            if !Is_Tab_Expanded_Space(remember_code_point) {
                prev_remember_code_point = remember_code_point;
                remember_code_point = data.*[i];
                if Is_Expanded_Tab(prev_remember_code_point) {
                    Inline_Buffer_Append(*inline_buffer, #char "\t");
                } else {
                    Inline_Buffer_Append(*inline_buffer, Strip_Markup(prev_remember_code_point));
                }
            } else {
                remember_code_point = data.*[i];
            }
        }
    }
    data.count = inline_buffer.count;
}

Collapse_Tabs_Inline_And_Insert :: (data: *[]u32, col: s64, code_points: []u32) {
    inline_buffer := Inline_Buffer(data.*);
    post_insert_memory := Temp_Buffer(u32, data.count-col);
    post_insert_memory.count = 0;
    if col > 0 then for i: 0..col-1 {
        Inline_Append_Code_Point(*inline_buffer, data.*[i], i);
    }
   
    if col < data.count then for j: col..data.count-1 {
        Inline_Buffer_Append(*post_insert_memory, data.*[j]);
    }
    for code_points {
        Inline_Append_Code_Point_No_Alias(*inline_buffer, it);
    }
    for post_insert_memory {
        Inline_Append_Code_Point_No_Alias(*inline_buffer, it);
    }

    data.count = inline_buffer.count;
}

Collapse_Tabs_Inline_And_Remove :: (data: *[]u32, col: s64) {
    if data.count == 0 {
        return;
    }
    inline_buffer := Inline_Buffer(data.*);
    for data.* {
        if it_index == col then continue;
        Inline_Append_Code_Point(*inline_buffer, it, it_index);
    }
    data.count = inline_buffer.count;
}

Collapse_Tabs_Inline_And_Remove_Count :: (data: *[]u32, col: s64, count: s64) {
    if data.count == 0 {
        return;
    }
    inline_buffer := Inline_Buffer(data.*);
    for data.* {
        if it_index >= col && it_index < (col + count) then continue;
        Inline_Append_Code_Point(*inline_buffer, it, it_index);
    }
    data.count = inline_buffer.count;
}

Commit_And_Empty_Utf32_Buffers :: () {
    for temp_utf32_buffers {
        Commit_Utf32_To_Line(*it);
    }
    array_reset(*temp_utf32_buffers);
}

#scope_export // -------------------------------------------------------------------------------------------- { EXPORT }

Utf8_From_Modified_Utf32_Array :: (bin: []u32, true_count: s64) -> string {
    temp_utf32_array := Temp_Buffer(u32, true_count);
    for 0..true_count-1 {
        temp_utf32_array[it] = Remove_Modifier_Flags(bin[it]);
    }
    return Encode(As_String(temp_utf32_array), .UTF32, .UTF8);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// types

Get_Current_Change :: (buffer: *TextBuffer) -> *TextChange {
    if buffer.change_history.count == 0 {
        Push_Middle(*buffer.change_history, .{});
    }
    return Peek_Middle(*buffer.change_history);   
}

Add_Line_To_Change :: (buffer: *TextBuffer, row: s64, flags: LineChangeFlags) {
    Init_Cursor_Proc_Or_Return();
    mid_change = true;

    current_change := Get_Current_Change(buffer);
    if current_change.need_overwrite {
        Reset_Back(*buffer.change_history);
    }

    if vi_mode == .VISUAL {
        selection_begin, _ := Cursor_Selection(cursor);
        current_change.cursor_position.x = selection_begin.x;
        current_change.cursor_position.y = selection_begin.y;
    } else {
        current_change.cursor_position.x = cursor.x;
        if current_change.lines.count == 0 {
            current_change.cursor_position.y = xx row;
        } else {
            current_change.cursor_position.y = min(sdw(row), current_change.cursor_position.y);
        }
    }

    line_change: *LineChange;
    change_exists := false;
    line_id := buffer.lines[row].unique_id;

    for current_change.lines {
        if it.line_id == line_id {
            line_change = *it;
            if flags == .DELETE_LINE && (line_change.flags & .INSERT_LINE) != 0 {
                array_ordered_remove_by_index(*current_change.lines, it_index);
                return;
            }
            change_exists = true;
            break;
        }
    }
    if line_change == null {
        if flags & .INSERT_FRONT {
            array_insert_at(*current_change.lines, .{}, 0);
            line_change = *current_change.lines[0];
        } else {
            line_change = array_add(*current_change.lines);
        }
    }
    line_change.flags |= flags;
    line_change.line_id = line_id;
    line_change.line_index = row;
    if change_exists {
        return;
    }

    line_str := Get_Current_Utf8_For_Line(buffer, row);
    if line_str.count > 0 {
        if line_change.undo_tack.bin_id.index == -1 {
            line_change.undo_tack.bin_id = Request_Bin(*undo_redo_text, line_str.count);
            Set_Bin_Data(*undo_redo_text, *line_change.undo_tack.bin_id, As_Array(line_str, u8));
            line_change.undo_tack.count = line_str.count;
        }
    }
}

End_Current_Change :: () {
    Init_Cursor_Proc_Or_Return();
    if Totally_Empty(*text_buffer.change_history) {
        return;
    }
    current_change := Get_Current_Change(text_buffer); 
    Push_Middle(*text_buffer.change_history);
}

Is_Current_Change_Empty :: () -> bool {
    Init_Cursor_Proc_Or_Return_Value(false);
     if text_buffer.change_history.count == 0 {
        return true;
    }
    change := Peek_Middle(*text_buffer.change_history);
    return change.lines.count == 0;
}

LineBuffer :: struct {
    bin_id: BinID;
    unique_id: u32; // 'unique' is sort of a misnomer. maybe rename to 'counter_id' ?
    byte_count: u32;
}

SpecialTextArtifact :: enum {
    NONE;
    GO_TO_NEW_LINE_ABOVE;
    GO_TO_NEW_LINE_BELOW;
}

BinTack :: struct {
    bin_id: BinID;
    count: s64;
}

// TODO: INSERTION and DELETION don't need to be tracked with different flags. whatever the line was will be restored. the only extra information needed: line was added/deleted?
LineChangeFlags :: enum_flags u8 {
    INSERT_LINE;
    DELETE_LINE;
    INSERT_FRONT;
}

LineChange :: struct {
    line_index: s64;
    undo_tack: BinTack;
    redo_tack: BinTack;
    line_id: u32;
    flags: LineChangeFlags;
}

Cleanup_Text_Register :: (using register_tack: *BinTack) {
    if register_tack.bin_id.index != -1 {
        Release_Bin(*register_text, *register_tack.bin_id);
    }
    register_tack.* = .{};
}

Cleanup_Text_Change :: (using change: *TextChange) {
    for *lines {
        if it.undo_tack.bin_id.index != -1 {
            Release_Bin(*undo_redo_text, *it.undo_tack.bin_id);
        }
        if it.redo_tack.bin_id.index != -1 {
            Release_Bin(*undo_redo_text, *it.redo_tack.bin_id);
        }
    }
    array_reset(*lines);
    change.* =.{};
}

TextChange :: struct {
    lines: [..]LineChange;
    cursor_position: IntVector2;
    need_overwrite: bool;
}

TextBuffer :: struct {
    lines: [..]LineBuffer;
    line_pool: BinPool(TEXT_BUFFER_SMALL_CHUNK_LEN, u8);
    file_path: string;
    change_history: OpposingCircularBuffer(TextChange);
    saved_cursor: Cursor;
    flags: enum_flags {
        FILE_EXPLORER;
    }
}

Utf32Buffer :: struct {
    home_buffer: *TextBuffer;
    home_row: u32;
    line_id: u32;
    home_bin_id: BinID;
    temp_bin_id: BinID;
    array: []u32;
}

line_id_counter: u32;
debug_line_id_counter: u32;

DEFAULT_REGISTER : u32 : 0xffff_ffff;

TextRegisters :: struct {
    tack_map: Table(u32, BinTack);
    number_registers: CircularBuffer(BinTack);
}

Get_Register_Text :: (register: u32) -> []u32 {
    tack := table_find_pointer(*registers.tack_map, register);
    if tack != null && tack.bin_id.index != - 1 {
        bin := Get_Bin(*register_text, tack.bin_id);
        bin.count = tack.count;
        return bin;
    }
    return u32.[];
}

Set_Register_Text :: (register: u32, text: []u32) {
    tack := table_find_pointer(*registers.tack_map, register);
    if tack == null {
        tack = table_set(*registers.tack_map, register, .{});
    }
    if tack.bin_id.index == -1 {
        tack.bin_id = Request_Bin(*register_text, text.count);
    }
    if tack.bin_id.index != -1 {
        Set_Bin_Data(*register_text, *tack.bin_id, text);
    }
    tack.count = text.count;
    if register < #char "0" || register > #char "9" {
        Push_Text_To_Number_Registers(text);
    }
}

Push_Text_To_Number_Registers :: (text: []u32) {
    tack := Push_Front(*registers.number_registers, .{});   
    if text.count > 0 {
        tack.bin_id = Request_Bin(*register_text, text.count);
        Set_Bin_Data(*register_text, *tack.bin_id, text);
        tack.count = text.count;
    }
}

Get_Raw_Line_Indent :: (line: []u32) -> s64 {
    tab_count := 0;
    space_count := 0;
    spaces_per_tab := Integer_Option_Value(.INDENT_WIDTH);
    for c : 0..line.count-1 {
        if line[c] == #char "\t" {
            tab_count += 1;
        } else if line[c] == #char " " {
            space_count += 1;
        } else {
            break;
        }
    }
    return tab_count + (space_count / spaces_per_tab);
}

Get_Marked_Line_Indent :: (line: []u32) -> s64 {
    space_count := 0;
    spaces_per_tab := Integer_Option_Value(.INDENT_WIDTH);
    for c : 0..line.count-1 {
        code_point := Strip_Markup(line[c]);
        if code_point == #char " " {
            space_count += 1;
        } else {
            break;
        }
    }
    return space_count / spaces_per_tab;
}

// TODO: support non-curly brace languages
// TODO: support non-tab indent
Get_Indent_Level_From_Context :: (buffer: *TextBuffer, i: s64) -> s64 {
    ITER_MAX :: 256;
    if i == 0 then return 0;
    curly_open_level := 0;
    iter_ct := 1;
    line_min := max(0, i - ITER_MAX);
    // try using curly braces relative to our current pos
    while (i - iter_ct) >= line_min {
        line := Raw_Line_View(buffer, i - iter_ct);
        if line.count > 0 then for #v2 < cback : 0..line.count-1 {
            if line[cback] == #char "{" {
                curly_open_level += 1;
                if curly_open_level > 0 {
                    return Get_Raw_Line_Indent(line) + 1;
                }
            } else if line[cback] == #char "}" {
                curly_open_level -= 1;
            }
        }
        iter_ct += 1;
    }
    // fallback: prev line might be good enough
    return Get_Raw_Line_Indent(Raw_Line_View(buffer, i - 1));
}

Insert_Code_Point_Should_Try_Unindent :: (row: s64, col: s64, utf32_buffer: *Utf32Buffer, code_point: u32) -> bool {
    return row > 0 
        && utf32_buffer.array.count > 0
        && col == utf32_buffer.array.count 
        && code_point == #char "}" 
        && Bool_Option_Value(.AUTO_INDENT);
}