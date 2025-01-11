
Mark_Color :: inline (code_point: u32, color_index: u8) -> u32 {
    return code_point | (udw(color_index) << 22);
}

Marked_Code_Point_Color_Index :: inline (marked_code_point: u32) -> u8 {
    index := (marked_code_point & COLOR_SPACE_MASK) >> 22;
    return ub(index);
}

Marked_Code_Point_Utf32 :: inline (marked_code_point: u32) -> u32 {
    return marked_code_point & TEXT_SPACE_MASK;
}

Unmarked_Code_Point :: inline (marked_code_point: u32) -> ColorCodePoint {
    return .{Marked_Code_Point_Utf32(marked_code_point), Marked_Code_Point_Color_Index(marked_code_point)};
}

Strip_Markup_Inline :: inline (marked_code_point: *u32) {
    marked_code_point.* = marked_code_point.* & TEXT_SPACE_MASK;
}

Strip_Markup :: inline (marked_code_point: u32) -> u32 {
    return marked_code_point & TEXT_SPACE_MASK;
}

Is_Tab_Expanded_Space :: inline (marked_code_point: u32) -> bool {
    return (marked_code_point & TAB_SPACE_MASK) == TAB_EXPANDED_SPACE;
}

Is_Expanded_Tab :: inline (marked_code_point: u32) -> bool {
    return (marked_code_point & TAB_SPACE_MASK) == EXPANDED_TAB;
}

Is_Whitespace :: inline (marked_code_point: u32) -> bool {
    return ((marked_code_point & TAB_OR_EXPANDED_SPACE_MARK) != 0) || marked_code_point == #char " ";
}

Code_Point_Equal_To :: inline (marked_code_point: u32, utf32: u32) -> bool {
    return Strip_Markup(marked_code_point) == utf32;
}

Is_Alphanumeric_Or_Underscore :: inline (marked_code_point: u32) -> bool {
    utf32 := Marked_Code_Point_Utf32(marked_code_point);
    return (utf32 >= #char "A" && utf32 <= #char "Z") 
        || (utf32 >= #char "a" && utf32 <= #char "z") 
        || (utf32 >= #char "0" && utf32 <= #char "9")
        || utf32 == #char "_";
}

Get_Unmarked_Utf8 :: (in_utf32: []u32, out_utf8: *[..]u8, out_colors: *[..]TextColorLocation) {
    array_reset_keeping_memory(out_utf8);
    array_reset_keeping_memory(out_colors);
    prev_color_index: s16 = -1;
    for in_utf32 {
        code_point := Unmarked_Code_Point(it);
        if sw(code_point.color) != prev_color_index {
            array_add(out_colors, .{text_colors[code_point.color], xx out_utf8.count});
            prev_color_index = sw(code_point.color);
        }
        utf8 := Utf32_To_Utf8(xx *code_point.utf32);
        for 0..utf8.count-1 {
            array_add(out_utf8, utf8.bytes[it]);
        }
    }
}

Get_Unmarked_Utf8 :: (in_utf32: []u32) -> utf8: []u8 {
    out_utf8 := Temp_Buffer(u8, in_utf32.count * 4);
    out_count := 0;
    for in_utf32 {
        code_point := Unmarked_Code_Point(it);
        utf8_cp := Utf32_To_Utf8(xx *code_point.utf32);
        for 0..utf8_cp.count-1 {
            out_utf8[out_count] = utf8_cp.bytes[it];
            out_count += 1;
        }
    }
    out_utf8.count = out_count;
    return out_utf8;
}

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
                Inline_Buffer_Append(*temp_buffer, EXPANDED_TAB);
                if space_ct > 1 then for 1..space_ct-1 {
                    Inline_Buffer_Append(*temp_buffer, TAB_EXPANDED_SPACE);
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

Modified_Utf32_Array_Split :: (array: []u32, pattern: []u32) -> (left: []u32, right: []u32, success: bool) {
    success: bool;
    left, right: []u32;
    for array {
        array_code_point := Strip_Markup(it);
        match := true;
        for pattern {
            if it != array_code_point {
                match = false;
                break;
            }
        }
        if match {
            success = true;
            left.count = it_index;
            left.data = array.data;
            right.count = array.count - (it_index + 1);
            right.data = array.data + (it_index + 1);
            break;
        }
    }
    return left, right, success;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

ColorCodePoint :: struct {
    utf32: u32;
    color: u8;
}

TextColorLocation :: struct {
    color: bRGB;
    location: s32;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

TEXT_SPACE_MASK : u32 : 0x00_1f_ff_ff;

// for marking spaces that can be removed when collapsing tabs, and can be skipped over by a cursor
TAB_EXPANDED_SPACE    : u32 : 0x80_00_00_00 | #char " ";
EXPANDED_TAB          : u32 : 0x40_00_00_00 | #char " ";
TAB_OR_EXPANDED_SPACE : u32 : TAB_EXPANDED_SPACE | EXPANDED_TAB;
TAB_SPACE_MASK : u32 : TAB_OR_EXPANDED_SPACE | TEXT_SPACE_MASK;
TAB_OR_EXPANDED_SPACE_MARK : u32 : 0x80_00_00_00 | 0x40_00_00_00;

COLOR_SPACE_MASK : u32 : 0x3f_c0_00_00; // 256 colors (including 0)

text_colors: [256]bRGB;