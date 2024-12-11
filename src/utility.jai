
bRGB :: struct {
    r, g, b: u8;
}

bRGBA :: struct {
    r, g, b: u8;
    a: u8 = 255;

    #place r;
        rgb: bRGB = ---;
}

fRGB :: struct {
    r, g, b: float32;
}

fRGBA :: struct {
    r, g, b: float32;
    a := 1.0;

    #place r;
        rgb: fRGB = ---;
}

fRGBA_WHITE :: fRGBA.{1,1,1,1};
fRGB_WHITE :: fRGB.{1,1,1};

bRGBA_WHITE :: bRGBA.{255,255,255,255};
bRGB_WHITE :: bRGB.{255,255,255};
bRGB_RED :: bRGB.{255, 0, 0};

To_fRGBA :: (in: bRGB) -> fRGBA {
    return .{xx in.r / 255.0, in.g / 255.0, in.b / 255.0, 1.0};
}

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

Element_Index :: inline (item: *$T, array: []T) -> s64 {
    index := item - array.data;
    assert(index >= 0 && index < array.count);
    return index;
}

Expand_Tabs :: inline (str: string, indent_width: s64) -> string {
    expanded := Expand_Tabs(As_Array(str, u8), indent_width);
    return string.{expanded.count, expanded.data};
}

Offset_Of :: inline ($T: Type, $FIELD: string) -> s64 {
    // place a constant pointer of this type at address 0. so, if you get a pointer to a field in the type, the
    // address will be the offset to that field.
    offset_of: *T: null;
    #insert -> string {
        return tprint("return xx *offset_of.%;", FIELD);
    }
}

Inline_Buffer :: inline (from_data: string, $T: Type) ->  []T {
    assert((from_data.count / size_of(T)) * size_of(T) == from_data.count);
    buf: []T = ---;
    buf.data = xx from_data.data;
    buf.count = 0;
    return buf;
}

Inline_Buffer :: inline (from_data: []$T) -> []T {
    buf: []T = ---;
    buf.data = from_data.data;
    buf.count = 0;
    return buf;
}

// appending for when you know how much space you have. manual dynamic array.
Inline_Buffer_Append :: inline (buf: *[]$T, item: T) #expand {
    buf.count += 1;
    buf.*[buf.count-1] = item;
}

Arrays_Equal :: (a: []$T, b: []T) -> bool {
    if a.count != b.count return false;
    for a { if it != b[it_index] then return false; }
    return true;
}