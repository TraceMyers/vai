

fRGB :: struct {
    r, g, b: float32;
}

fRGBA :: struct {
    using rgb: fRGB;
    a := 1.0;
}

COLOR_WHITE :: fRGBA.{.{1, 1, 1}, 1};

// ctor/dtor style scope-dependent resource management. not used for individual data, but rather whole systems. (there is no data tied to the call.) to use, define an empty struct with an [Initialize :: () -> bool] and a [Shutdown :: ()]. Shutdown() should be callable even if initialization fails.
Scoped_Construct :: ($T: Type) -> bool #expand {
    init_success := T.Initialize();
    `defer T.Shutdown();
    return init_success;
}

String_Reset :: inline (s: *string) {
    if s.data != null {
        free(s);
        s.data = null;
    }
    s.count = 0;
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

// appending for when you know how much space you have. manual dynamic array.
String_Append :: inline (str: *string, char: u8) {
    str.count += 1;
    str.*[str.count-1] = char;
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
UTF32_TAB_EXPANDED_SPACE    : u32 : 0x80_00_00_00 | #char " ";
UTF32_EXPANDED_TAB          : u32 : 0x40_00_00_00 | #char " ";
UTF32_TAB_OR_EXPANDED_SPACE : u32 : UTF32_TAB_EXPANDED_SPACE | UTF32_EXPANDED_TAB;

Expand_Tabs :: (data: []$T, indent_width: s64, $MARK_TABS := false) -> []T {
    #if MARK_TABS then assert(T == u32); // can only mark tabs with 32 bits per code point
    if data.count == 0 then return T.[];
    // indent_width := Option_Value(.INDENTATION_WIDTH, s32); // TOOD: reimplement options
    temp_buffer_max := data.count * indent_width;
    temp_buffer := Temp_Buffer(T, temp_buffer_max);
    #if DEBUG_TEXT_BUFFERS memset(temp_buffer.data, 0, temp_buffer_max * size_of(T));
    temp_buffer.count = 0;
    for i : 0..data.count-1 {
        if data[i] == #char "\t" {
            space_ct := indent_width - (temp_buffer.count % indent_width);
            #if MARK_TABS {
                Inline_Buffer_Append(*temp_buffer, UTF32_EXPANDED_TAB);
                if space_ct > 1 then for 1..space_ct-1 {
                    Inline_Buffer_Append(*temp_buffer, UTF32_TAB_EXPANDED_SPACE);
                }
            } else {
                for 0..space_ct-1 {
                    Inline_Buffer_Append(*temp_buffer, xx #char " ");
                }
            }
        } else {
            Inline_Buffer_Append(*temp_buffer, xx data[i]);
        }
    }
    return temp_buffer;
}

Unmark_Code_Point :: inline (code_point: u32) -> u32 {
    return code_point & ~UTF32_TAB_OR_EXPANDED_SPACE;
}

Process_Per_Line :: (str: string, $PER_LINE: (*string, data: $T), data: T) -> s64 {
    line_count: s64;
    left, right: string;
    right = str;
    success: bool;
    while true {
        prev_right := right;
        success, left, right = split_from_left(right, #char "\n");
        if !success {
            if prev_right.count > 0 {
                PER_LINE(*prev_right, data); 
                line_count += 1;
            }
            break;
        }
        if left.count > 0 && left[left.count-1] == #char "\r" {
            left.count -= 1;
        }
        PER_LINE(*left, data); 
        line_count += 1;
    }
    return line_count;
}

Offset_Of :: inline ($T: Type, $FIELD: string) -> s64 {
    // place a constant pointer of this type at address 0. so, if you get a pointer to a field in the type, the
    // address will be the offset to that field.
    offset_of: *T: null;
    #insert -> string {
        return tprint("return xx *offset_of.%;", FIELD);
    }
}

Inline_Buffer :: inline (from_data: []$T) -> []T {
    buf: []T = ---;
    buf.data = from_data.data;
    buf.count = 0;
    return buf;
}

// appending for when you know how much space you have. manual dynamic array.
Inline_Buffer_Append :: (buf: *[]$T, item: T) #expand {
    buf.count += 1;
    buf.*[buf.count-1] = item;
}
