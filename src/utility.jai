
Scoped_Construct :: ($T: Type) #expand {
    T.Initialize();
    `defer T.Shutdown();
}

String_Reset :: inline (s: *string) {
    if s.data != null {
        free(s);
        s.data = null;
        s.count = 0;
    }
}

Read_Entire_File :: (path: string, $USE_TEMP_ALLOCATOR := false, $DEFER_FREE := false) -> string, bool #expand {
    #if USE_TEMP_ALLOCATOR {
        saved_allocator := context.allocator;
        context.allocator = temp;
    }
    file_string, success := read_entire_file(path);
    #if USE_TEMP_ALLOCATOR {
        context.allocator = saved_allocator;
    }
    #if DEFER_FREE {
        assert(!USE_TEMP_ALLOCATOR);
        `defer free(file_string);
    }
    return file_string, success;
}

As_Array :: inline (str: string, $T: Type) -> []T {
    t_array: []T = ---;
    t_array.count = str.count / size_of(T);
    t_array.data = xx str.data;
    assert(t_array.count * size_of(T) == str.count);
    return t_array;
}

As_String :: inline (array: []$T) -> string {
    return string.{array.count * size_of(T), xx array.data};
}

String_Append :: inline (str: *string, char: u8) {
    str.count += 1;
    str.*[str.count-1] = char;
}

Array_Append :: inline (array: *[]$T, item: T) {
    array.count += 1;
    array.*[array.count-1] = item;
}

Temp_Resize_Array :: inline ($T: Type, reserve_count := 0) -> [..]T {
    array: [..]T;
    array.allocator = temp;
    array_reserve(*array, reserve_count);
    return array;
}

Temp_Buffer :: inline ($T: Type, count: s64) -> []T {
    buffer: []T = ---;
    allocation := talloc(count * size_of(T));
    buffer.data = xx allocation;
    buffer.count = count;
    return buffer;
}

Array_Item_Index :: inline (item: *$T, array: []T) -> s64 {
    index := item - array.data;
    assert(index >= 0 && index < array.count);
    return index;
}

Expand_Tabs :: inline (str: string, indent_width: s64) -> string {
    expanded := Expand_Tabs(As_Array(str, u8), indent_width);
    return string.{expanded.count, expanded.data};
}

// for marking spaces that can be removed when collapsing tabs, and can be skipped over by a cursor
UTF32_TAB_EXPANDED_SPACE : u32 : 0x80_00_00_00 | #char " ";

Expand_Tabs :: (data: []$T, indent_width: s64, $MARK_NONCHARACTER_TABS := false) -> []T {
    #if MARK_NONCHARACTER_TABS then assert(T == u32); // can only mark tabs with 32 bits per code point
    if data.count == 0 then return T.[];
    // indent_width := Option_Value(.INDENTATION_WIDTH, s32); // TOOD: reimplement options
    temp_buffer_max := data.count * indent_width;
    temp_buffer := Temp_Buffer(T, temp_buffer_max);
    #if DEBUG_TEXT_BUFFERS memset(temp_buffer.data, 0, temp_buffer_max * size_of(T));
    temp_buffer.count = 0;
    for i : 0..data.count-1 {
        if data[i] == #char "\t" {
            space_ct := indent_width - (temp_buffer.count % indent_width);
            #if MARK_NONCHARACTER_TABS {
                Array_Append(*temp_buffer, xx #char " ");
                if space_ct > 1 then for 1..space_ct-1 {
                    Array_Append(*temp_buffer, UTF32_TAB_EXPANDED_SPACE);
                }
            } else {
                for 0..space_ct-1 {
                    Array_Append(*temp_buffer, xx #char " ");
                }
            }
        } else {
            Array_Append(*temp_buffer, xx data[i]);
        }
    }
    return temp_buffer;
}

Unmark_Tabs :: inline (str: string) {
    Unmark_Tabs(As_Array(str, u8));
}

Unmark_Tabs :: (data: []$T) {
    for *data {
        if it.* == UTF32_TAB_EXPANDED_SPACE {
            it.* = #char " ";
        }
    }
}