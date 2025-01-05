
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// data

file_buffers: DynamicPool(TextBuffer);
general_text_buffer: TextBuffer;

temp_utf32_buffer_pool: BinPool(24, u32); 
temp_utf32_buffers: [..]Utf32Buffer;
undo_redo_text: BinPool(16, u8);

// NOTE TO SELF: be careful not to alias data when working with bins inline then copying into the bin
// NOTE TO SELF: tab-expanded column is the only real column outside this file, but tab-expanded spaces are invalid to edit

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// init/shutdown

// for use with Scoped_Construct
Text_Buffers :: struct {

    Initialize :: () -> success: bool {
        Initialize(*file_buffers, 32);
        Initialize_Text_Buffer(*general_text_buffer, "", 1024, 1024);
        Assign_Bin_Pool_Allocator(*temp_utf32_buffer_pool, temp);
        Bin_Pool_Initialize(*undo_redo_text);
        temp_utf32_buffers.allocator = temp;
        return true;
    }

    Shutdown :: () {
        Shutdown(*file_buffers, Shutdown_Text_Buffer);
        Shutdown_Text_Buffer(*general_text_buffer);
        Bin_Pool_Shutdown(*undo_redo_text);
    }

}

Begin_Update_Text_Buffers :: () {
    Bin_Pool_Initialize(*temp_utf32_buffer_pool, 256);
}

End_Update_Text_Buffers :: () {
    Commit_And_Empty_Utf32_Buffers();
    Bin_Pool_Shutdown(*temp_utf32_buffer_pool);
}

Initialize_Text_Buffer :: (buffer: *TextBuffer, path: string, prealloc_lines := 0, prealloc_bins := 0) {
    if prealloc_bins > 0 {
        Bin_Pool_Initialize(*buffer.line_pool, prealloc_bins);
    } else {
        Bin_Pool_Initialize(*buffer.line_pool);
    }
    if prealloc_lines > 0 {
        array_reserve(*buffer.lines, prealloc_lines);
    }
    buffer.file_path = path;
    Opposing_Circular_Buffer_Initialize(*buffer.change_history, settings_file_data.change_history_count, Cleanup_Text_Change, true);
}

Shutdown_Text_Buffer :: (buffer: *TextBuffer) {
    Bin_Pool_Shutdown(*buffer.line_pool);
    array_reset(*buffer.lines);
    String_Reset(*buffer.file_path);
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
    file_string, success := Read_Entire_File(path, true);
    if !success {
        Log_Error("unable to open [%]", path);
        return -1;
    }

    line_len_total: s64;
    Count_Len_Total :: inline (line: *string, total: *s64) { total.* += line.count; }
    line_count := Process_Per_Line(file_string, Count_Len_Total, *line_len_total);

    INEFFICIENCY_FACTOR :: 1.25;
    avg_line_len := line_len_total / line_count;
    expected_bin_ct: s64 = xx (cast(float32)(Div_Ceil(avg_line_len, 32) * line_count) * INEFFICIENCY_FACTOR);
    buf_index := Request_Item(*file_buffers);
    buffer := Get_Item(*file_buffers, buf_index);
    Initialize_Text_Buffer(buffer, copy_string(path), line_count, expected_bin_ct);

    Append_Line_To_Buffer :: inline (line: *string, buffer: *TextBuffer) { Append_Line(buffer, line.*); }
    Process_Per_Line(file_string, Append_Line_To_Buffer, buffer);
    return buf_index;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// add/remove lines and get/set line bytes

Append_Line :: (buffer: *TextBuffer, line_str: string) {
    Commit_And_Empty_Utf32_Buffers();
    array_add(*buffer.lines, .{});
    Set_Line_Bytes(buffer, buffer.lines.count-1, line_str);
}

Insert_Line :: (buffer: *TextBuffer, i: s64) {
    Commit_And_Empty_Utf32_Buffers();
    array_insert_at(*buffer.lines, .{}, i);
}

Remove_Line :: (buffer: *TextBuffer, line_index: s64, is_change := true) {
    if is_change {
        Add_Line_To_Deletion_Change(buffer, line_index, true);
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
        Set_Bin_Data(*buffer.line_pool, *line.bin_id, As_Array(line_str, u8));
        line.byte_count = xx line_str.count;
        bytes := Get_Line_Bytes(buffer, line_index);
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// line utf32 temp buffers

Raw_Line_View :: (buffer: *TextBuffer, row: s64) -> []u32 {
    bytes := Get_Line_Bytes(buffer, row);
    utf32_str := Encode(bytes, .UTF8, .UTF32);
    return As_Array(utf32_str, u32);
}

Line_View :: (buffer: *TextBuffer, row: s64) -> []u32 {
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    return utf32_buffer.array;
}

Line_Count :: (buffer: *TextBuffer, row: s64) -> s64 {
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    return utf32_buffer.array.count;
}

Set_Utf32_Buffer_Data :: inline (utf32_buffer: *Utf32Buffer, data: []u32) {
    Set_Bin_Data(*temp_utf32_buffer_pool, *utf32_buffer.temp_bin_id, data);
    utf32_buffer.array.data = Get_Bin(*temp_utf32_buffer_pool, utf32_buffer.temp_bin_id).data;
    utf32_buffer.array.count = data.count;
}

Expand_Utf32_Buffer_Tabs :: inline (utf32_buffer: *Utf32Buffer) {
    expanded := Expand_Tabs(utf32_buffer.array, 4, true);
    Set_Utf32_Buffer_Data(utf32_buffer, expanded);
}

// NOTE: undo not implemented for this
// Replace_Code_Point :: (buffer: *TextBuffer, row: s64, col: s64, code_point: u32) {
//     utf32_buffer := Get_Utf32_Buffer(buffer, row);
//     assert(col < utf32_buffer.array.count);
//     #if DEBUG_TEXT_BUFFERS {
//         assert(!Is_Tab_Expanded_Space(utf32_buffer.array[col]));
//     }
//     replacing_tab := utf32_buffer.array[col] == #char "\t";
//     utf32_buffer.array[col] = code_point;
//     if replacing_tab {
//         Collapse_Tabs_Inline(*utf32_buffer.array);
//         Expand_Utf32_Buffer_Tabs(utf32_buffer);
//     }
// }

Insert_Code_Point :: (buffer: *TextBuffer, row: s64, col: s64, code_point: u32) {
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    assert(col <= utf32_buffer.array.count);
    #if DEBUG_TEXT_BUFFERS {
        if col < utf32_buffer.array.count {
            assert(!Is_Tab_Expanded_Space(utf32_buffer.array[col]));
        }
    }
    Resize_Utf32_Buffer(utf32_buffer, xx (utf32_buffer.array.count + 1));
    Collapse_Tabs_Inline_And_Insert(*utf32_buffer.array, col, code_point);
    Expand_Utf32_Buffer_Tabs(utf32_buffer);
}

Insert_Code_Points :: (buffer: *TextBuffer, row: s64, col: s64, code_points: []u32) {
    if code_points.count <= 0 then return;
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    assert(col <= utf32_buffer.array.count);
    #if DEBUG_TEXT_BUFFERS {
        if col < utf32_buffer.array.count {
            assert(!Is_Tab_Expanded_Space(utf32_buffer.array[col]));
        }
    }
    prev_count := utf32_buffer.array.count;
    Resize_Utf32_Buffer(utf32_buffer, xx (utf32_buffer.array.count + code_points.count));
    utf32_buffer.array.count = prev_count; // below proc depends on this
    Collapse_Tabs_Inline_And_Insert(*utf32_buffer.array, col, code_points);
    Expand_Utf32_Buffer_Tabs(utf32_buffer);
}

Remove_Code_Point :: (buffer: *TextBuffer, row: s64, col: s64) {
    // TODO: check if line deletion
    Add_Line_To_Deletion_Change(buffer, row, false);
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    assert(col < utf32_buffer.array.count);
    #if DEBUG_TEXT_BUFFERS {
        assert(!Is_Tab_Expanded_Space(utf32_buffer.array[col]));
    }
    Collapse_Tabs_Inline_And_Remove(*utf32_buffer.array, col);
    Expand_Utf32_Buffer_Tabs(utf32_buffer);
}

Remove_Code_Points :: (buffer: *TextBuffer, row: s64, col: s64, count: s64) {
    // TODO: check if line deletion
    Add_Line_To_Deletion_Change(buffer, row, false);
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    assert(col < utf32_buffer.array.count);
    #if DEBUG_TEXT_BUFFERS {
        assert(!Is_Tab_Expanded_Space(utf32_buffer.array[col]));
    }
    Collapse_Tabs_Inline_And_Remove_Count(*utf32_buffer.array, col, count);
    Expand_Utf32_Buffer_Tabs(utf32_buffer);
}

Break_Line_At :: (buffer: *TextBuffer, row: s64, col: s64) {
    Insert_Line(buffer, row+1);

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
        Insert_Code_Points(buffer, row+1, 0, copy_down);
        Resize_Utf32_Buffer(utf32_buffer, xx col);
    }
}

Clear_Line :: (buffer: *TextBuffer, row: s64) {
    Add_Line_To_Deletion_Change(buffer, row, false);
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

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

Get_Utf32_Buffer :: (buffer: *TextBuffer, line_index: s64, $ALLOW_ALLOCATION := true) -> *Utf32Buffer {
    line := *buffer.lines[line_index];
    utf32_buffer: *Utf32Buffer;
    buffer_index := -1;
    for temp_utf32_buffers {
        if it.home_bin_id == line.bin_id && it.home_row == line_index {
            utf32_buffer = *it;
            buffer_index = it_index;
            break;
        }
    }
    #if ALLOW_ALLOCATION {
        if utf32_buffer == null {
            utf32_buffer = array_add(*temp_utf32_buffers);
            buffer_index = temp_utf32_buffers.count-1;
            utf32_buffer.home_buffer = buffer;
            utf32_buffer.home_row = xx line_index;
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
        }
        if utf32_buffer.temp_bin_id.index != -1 {
            bin := Get_Bin(*temp_utf32_buffer_pool, utf32_buffer.temp_bin_id);
            utf32_buffer.array.data = bin.data;
        } else {
            utf32_buffer.array.data = null;
            utf32_buffer.array.count = 0;
        }
    }
    return utf32_buffer;
}

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
                remember_code_point = Strip_Markup(data.*[i]);
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


// LineChange :: struct {
//     row: s64;
//     using bin_tack: BinTack;
    // flags: enum_flags {
    //     NONE = 0;
    //     INSERTION;
    //     DELETION;
    // }
// }

// TextChange :: struct {
//     id: u64;
//     cursor_position: IntVector2;
//     lines: [..]LineChange;    
// }

// TextBuffer :: struct {
//     lines: [..]LineBuffer;
//     line_pool: BinPool(24, u8);
//     file_path: string;
//     // change_history: CircularBuffer(ChangeArtifact);
//     change_history: CircularBuffer(TextChange);
// }

Get_Current_Change :: (buffer: *TextBuffer) -> *TextChange {
    if buffer.change_history.count == 0 {
        Push_Middle(*buffer.change_history, .{});
    }
    return Peek_Middle(*buffer.change_history);   
}

Add_Line_To_Deletion_Change :: (buffer: *TextBuffer, row: s64, delete_line: bool) {
    Init_Cursor_Proc_Or_Return();
    current_change := Get_Current_Change(buffer);
    if current_change.need_overwrite {
        Reset_Back(*buffer.change_history);
    }
    if current_change.lines.count == 0 {
        current_change.cursor_position.x = cursor.x;
        current_change.cursor_position.y = cursor.y;
    }
    line_change: *LineChange;

    flags: LineChangeFlags = ---;
    if delete_line {
        flags = .DELETION | .DELETE_LINE;
    } else {
        flags = .DELETION;
    }

    for current_change.lines {
        if it.row == row {
            line_change = *it;
            if line_change.flags & flags == flags {
                return;
            }
            break;
        }
    }
    if line_change == null {
        line_change = array_add(*current_change.lines);
    }
    line_change.flags |= flags;

    line_str := Get_Current_Utf8_For_Line(buffer, row);
    if line_str.count > 0 {
        if line_change.bin_id.index == -1 {
            line_change.bin_id = Request_Bin(*undo_redo_text, line_str.count);
            Set_Bin_Data(*undo_redo_text, *line_change.bin_id, As_Array(line_str, u8));
            line_change.count = line_str.count;
        }
    }
}

End_Current_Change :: () {
    Init_Cursor_Proc_Or_Return();
    if Totally_Empty(*text_buffer.change_history) {
        return;
    }
    Push_Middle(*text_buffer.change_history);
}

// Push_Deleted_Text_Section_To_Current_Change :: (buffer: *TextBuffer, row: s64, prepend: []u32, append: []u32, start_col := -1, end_col := -1) {
    // TODO: this is wrong, because its the old line view, as opposed to the current, temp frame view
    // need to use utf32 buffer with collapsed tabs
    // raw_view := Raw_Line_View(buffer, row);
    // if start_col == -1 {
    //     // whole line
    //     if prepend.count > 0 || append.count > 0 {
    //         raw_view = Temp_Array_Prepend_Append(raw_view, prepend, append);
    //     }
    //     Push_Deleted_Text_To_Current_Change(raw_view, false);
    // } else {
    //     // adjust column numbers with collapsed tabs
    //     utf32_buffer := Get_Utf32_Buffer(buffer, row);
    //     adjusted_start_col, adjusted_count: s64;
    //     for utf32_buffer.array {
    //         if !Is_Tab_Expanded_Space(it) {
    //             if it_index < start_col {
    //                 adjusted_start_col += 1;
    //             } else if it_index < end_col {
    //                 adjusted_count += 1;
    //             } else break;
    //         } else {
    //             Log("DETECTED TAB EXPANDED SPACE");
    //         }
    //     }
    //     // adjusted_start_col -= prepend.count;
    //     raw_view.data += adjusted_start_col;
    //     raw_view.count = max(adjusted_count, 1);
    //     if prepend.count > 0 || append.count > 0 {
    //         raw_view = Temp_Array_Prepend_Append(raw_view, prepend, append);
    //     }

    //     raw_str := Encode(As_String(raw_view), .UTF32, .UTF8);
    //     for *raw_str {
    //         if it.* == 27 {
    //             it.* = #char "Z";
    //         }
    //     }
    //     Log("raw view: (%)", raw_str);
    //     Log("prepend: %, append: %", prepend, append);
    //     Log("start col: %, end col: %", start_col, end_col);
    //     Log("adjusted start col: %, adjusted count: %", adjusted_start_col, adjusted_count);

    //     if end_col == -1 {
    //         // one code point
    //         // raw_view.data += adjusted_start_col;
    //         // raw_view.count = min(1, raw_view.count);
    //         Push_Deleted_Text_To_Current_Change(raw_view, false);
    //     } /*else if end_col == raw_view.count + 1{
    //         // to the end of the line + newline
    //         assert(end_col > start_col);
    //         raw_view.data += start_col;
    //         raw_view.count = (end_col - 1) - start_col;
    //         Push_Deleted_Text_To_Current_Change(raw_view, true);
    //     }*/ else {
    //         // section of line
    //         assert(end_col > adjusted_start_col);
    //         // raw_view.data += adjusted_start_col;
    //         // raw_view.count = adjusted_end_col - adjusted_start_col;
    //         Push_Deleted_Text_To_Current_Change(raw_view, false);
    //     }
    // }
// }

Is_Current_Change_Empty :: () -> bool {
    Init_Cursor_Proc_Or_Return_Value(false);
     if text_buffer.change_history.count == 0 {
        return true;
    }
    change := Peek_Middle(*text_buffer.change_history);
    return change.lines.count == 0;
}

// Push_Input_Text_To_Current_Change :: (text: []$T) {
//     Init_Cursor_Proc_Or_Return();
    // if text.count <= 0 return;
    // if text_buffer.change_history.count == 0 {
    //     Push_Back(*text_buffer.change_history, .{});
    // }
    // change := Peek_Back(*text_buffer.change_history);
    // change.flags |= .ADD_TEXT;
    // Add_Text_To_Change(*change.input_text, text);
// }

// Push_Deleted_Text_To_Current_Change :: (text: []u32, newline_at_end: bool) {
//     Init_Cursor_Proc_Or_Return();
    // if text.count <= 0 && !newline_at_end then return;
    // if text_buffer.change_history.count == 0 {
    //     Push_Back(*text_buffer.change_history, .{});
    // }
    // change := Peek_Back(*text_buffer.change_history);
    // change.flags |= .DELETE_TEXT;
    // Add_Text_To_Change(*change.deleted_text, text, newline_at_end);
// }
 

// Add_Text_To_Change :: (using change_tack: *BinTack, text: []$T, add_newline_at_end := false) {
    // additional_code_pt_ct := text.count + (ifx add_newline_at_end then PLATFORM_CARRIAGE_RETURN.count else 0);
    // new_count := count + additional_code_pt_ct;
    // if bin_id.index == -1 {
    //     bin_id = Request_Bin(*undo_redo_text, additional_code_pt_ct);
    // } else {
    //     Resize_Bin(*undo_redo_text, *bin_id, new_count);
    // }
    // bin := Get_Bin(*undo_redo_text, bin_id);
    // if text.count > 0 then for 0..text.count - 1 {
    //     bin[count + it] = text[it];
    // }
    // if add_newline_at_end {
    //     for 0..PLATFORM_CARRIAGE_RETURN.count-1 {
    //         bin[count + text.count + it] = PLATFORM_CARRIAGE_RETURN[it];
    //     }
    // }
    // count += xx additional_code_pt_ct;
// }

LineBuffer :: struct {
    bin_id: BinID;
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

// ChangeArtifact :: struct {
//     id: u64;
//     end_position: IntVector2;
//     input_text: BinTack;
//     deleted_text: BinTack;
//     flags: enum_flags u8 {
//         NONE :: 0;
//         ADD_TEXT :: 1;
//         DELETE_TEXT;
//     };
// }

// TODO: INSERTION and DELETION don't need to be tracked with different flags. whatever the line was will be restored. the only extra information needed: line was added/deleted?
LineChangeFlags :: enum_flags u8 {
    NONE :: 0;
    INSERTION :: 1;
    INSERT_LINE;
    DELETION;
    DELETE_LINE;
}

LineChange :: struct {
    row: s64;
    using bin_tack: BinTack;
    flags: LineChangeFlags;
}

Cleanup_Text_Change :: (using change: *TextChange) {
    for *lines {
        if it.bin_id.index != -1 {
            Release_Bin(*undo_redo_text, *it.bin_id);
        }
    }
    array_reset(*lines);
    change.* =.{};
}

TextChange :: struct {
    id: u64;
    cursor_position: IntVector2;
    lines: [..]LineChange;   
    need_overwrite: bool;
}

TextBuffer :: struct {
    lines: [..]LineBuffer;
    line_pool: BinPool(24, u8);
    file_path: string;
    change_history: OpposingCircularBuffer(TextChange);
}

Utf32Buffer :: struct {
    home_buffer: *TextBuffer;
    home_row: u32;
    home_bin_id: BinID;
    temp_bin_id: BinID;
    array: []u32;
}