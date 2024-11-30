
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
        temp_utf32_buffers.allocator = temp;
        return true;
    }

    Shutdown :: () {
        Shutdown(*file_buffers, Shutdown_Text_Buffer);
        Shutdown_Text_Buffer(*general_text_buffer);
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
}

Shutdown_Text_Buffer :: (buffer: *TextBuffer) {
    Bin_Pool_Shutdown(*buffer.line_pool);
    array_reset(*buffer.lines);
    String_Reset(*buffer.file_path);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Get_File_Buffer :: (file_path: string) -> *TextBuffer {
    existing_buffer := Find_Item(*file_buffers, file_path, (buf, path) => buf.file_path == path);
    if existing_buffer == -1 {
        existing_buffer = Load_File_Into_Buffer(file_path);
    }
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

    INNEFICIENCY_FACTOR :: 1.25;
    avg_line_len := line_len_total / line_count;
    expected_bin_ct: s64 = xx (cast(float32)(Div_Ceil(avg_line_len, 32) * line_count) * INNEFICIENCY_FACTOR);
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

Remove_Line :: (buffer: *TextBuffer, line_index: s64) {
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

Line_View :: inline (buffer: *TextBuffer, row: s64) -> []u32 {
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    return utf32_buffer.array;
}

Line_Count :: inline (buffer: *TextBuffer, row: s64) -> s64 {
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

Replace_Code_Point :: (buffer: *TextBuffer, row: s64, col: s64, code_point: u32) {
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    assert(col < utf32_buffer.array.count);
    #if DEBUG_TEXT_BUFFERS {
        assert(utf32_buffer.array[col] != UTF32_TAB_EXPANDED_SPACE);
    }
    replacing_tab := utf32_buffer.array[col] == #char "\t";
    utf32_buffer.array[col] = code_point;
    if replacing_tab {
        Collapse_Tabs_Inline(*utf32_buffer.array);
        Expand_Utf32_Buffer_Tabs(utf32_buffer);
    }
}

Insert_Code_Point :: (buffer: *TextBuffer, row: s64, col: s64, code_point: u32) {
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    assert(col <= utf32_buffer.array.count);
    #if DEBUG_TEXT_BUFFERS {
        if col < utf32_buffer.array.count {
            assert(utf32_buffer.array[col] != UTF32_TAB_EXPANDED_SPACE);
        }
    }
    Resize_Utf32_Buffer(utf32_buffer, xx (utf32_buffer.array.count + 1));
    Collapse_Tabs_Inline_And_Insert(*utf32_buffer.array, col, code_point);
    Expand_Utf32_Buffer_Tabs(utf32_buffer);
}

Remove_Code_Point :: (buffer: *TextBuffer, row: s64, col: s64) {
    utf32_buffer := Get_Utf32_Buffer(buffer, row);
    assert(col < utf32_buffer.array.count);
    #if DEBUG_TEXT_BUFFERS {
        assert(utf32_buffer.array[col] != UTF32_TAB_EXPANDED_SPACE);
    }
    Collapse_Tabs_Inline_And_Remove(*utf32_buffer.array, col);
    Expand_Utf32_Buffer_Tabs(utf32_buffer);
}

Commit_Utf32_To_Line :: (utf32_buffer: *Utf32Buffer) {
    Collapse_Tabs_Inline(*utf32_buffer.array);
    utf32_string := As_String(utf32_buffer.array);
    utf8_string := Encode(utf32_string, .UTF32, .UTF8);
    Set_Bin_Data(*utf32_buffer.home_buffer.line_pool, *utf32_buffer.home_bin_id, As_Array(utf8_string, u8));
    line := *utf32_buffer.home_buffer.lines[utf32_buffer.home_row];
    line.bin_id = utf32_buffer.home_bin_id;
    line.byte_count = xx utf8_string.count;
}

Remove_Utf32_Buffer :: (buffer: *TextBuffer, row: s64) {
    utf32_buffer := Get_Utf32_Buffer(buffer, row, false);
    if utf32_buffer != null {
        index := Array_Item_Index(utf32_buffer, temp_utf32_buffers);
        if utf32_buffer.temp_bin_id.index != -1 {
            Release_Bin(*temp_utf32_buffer_pool, *utf32_buffer.temp_bin_id);
        }
        array_ordered_remove_by_index(*temp_utf32_buffers, index);
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// types

LineBuffer :: struct {
    bin_id: BinID;
    byte_count: u32;
}

TextBuffer :: struct {
    lines: [..]LineBuffer;
    line_pool: BinPool(24, u8);
    file_path: string;
}

Utf32Buffer :: struct {
    home_buffer: *TextBuffer;
    home_row: u32;
    home_bin_id: BinID;
    temp_bin_id: BinID;
    array: []u32;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// data

file_buffers: DynamicPool(TextBuffer);
general_text_buffer: TextBuffer;

temp_utf32_buffer_pool: BinPool(24, u32); 
temp_utf32_buffers: [..]Utf32Buffer;

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

Get_Utf32_Buffer :: (buffer: *TextBuffer, line_index: s64, $ALLOW_ALLOCATION := true) -> *Utf32Buffer {
    line := *buffer.lines[line_index];
    utf32_buffer: *Utf32Buffer;
    buffer_index := -1;
    for temp_utf32_buffers {
        if it.home_bin_id.index == line.bin_id.index {
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
        bin := Get_Bin(*temp_utf32_buffer_pool, utf32_buffer.temp_bin_id);
        utf32_buffer.array.data = bin.data;
    }
    return utf32_buffer;
}

Resize_Utf32_Buffer :: inline (utf32_buffer: *Utf32Buffer, count: u32) {
    if utf32_buffer.temp_bin_id.index == -1 && count > 0 {
        utf32_buffer.temp_bin_id = Request_Bin(*temp_utf32_buffer_pool, count);
        bin := Get_Bin(*temp_utf32_buffer_pool, utf32_buffer.temp_bin_id);
        utf32_buffer.array.data = bin.data;
    } else {
        Resize_Bin(*temp_utf32_buffer_pool, *utf32_buffer.temp_bin_id, count);
    }
    utf32_buffer.array.count = count;
}

// for appending into a buffer where the input and output buffer are the same.
Inline_Append_Code_Point :: inline (buffer: *[]u32, code_point: u32, iter_index: s64) {
    if code_point == UTF32_TAB_EXPANDED_SPACE {
        return;
    } else if code_point == UTF32_EXPANDED_TAB {
        Inline_Buffer_Append(buffer, #char "\t");
    } else if iter_index == buffer.count {
        // no need to copy, code point already in the right place
        buffer.count += 1;
    } else {
        // copy back + increase count
        Inline_Buffer_Append(buffer, code_point);
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
            Inline_Buffer_Append(*inline_buffer, code_point);
        } else {
            // from this point forward, appended code points may ovewrite the code points that are already in the buffer, so the in-buffer code points need to be copied out before appending.
            if remember_code_point != UTF32_TAB_EXPANDED_SPACE {
                prev_remember_code_point = remember_code_point;
                remember_code_point = data.*[i];
                if prev_remember_code_point == UTF32_EXPANDED_TAB {
                    Inline_Buffer_Append(*inline_buffer, #char "\t");
                } else {
                    Inline_Buffer_Append(*inline_buffer, prev_remember_code_point);
                }
            } else {
                remember_code_point = data.*[i];
            }
        }
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

Commit_And_Empty_Utf32_Buffers :: () {
    for temp_utf32_buffers {
        Commit_Utf32_To_Line(*it);
    }
    array_reset(*temp_utf32_buffers);
}