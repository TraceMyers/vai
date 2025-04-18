
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
#place r;
    channels: [3]float32;
}

fRGBA :: struct {
    r, g, b: float32;
    a := 1.0;

    #place r;
        rgb: fRGB = ---;
}

operator * :: (rgb: fRGB, x: float) -> fRGB {
    return .{rgb.r * x, rgb.g * x, rgb.b * x};
}

Channel_Max :: (rgb: fRGB) -> s32 {
    if rgb.r > rgb.g {
        return ifx rgb.r > rgb.b then sdw(0) else sdw(2);
    } else {
        return ifx rgb.g > rgb.b then sdw(1) else sdw(2);
    }
}

Channel_Average :: (rgb: fRGB) -> float {
    return (rgb.r + rgb.g + rgb.b) * (1.0 / 3.0);
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
    Log("initializing %", T);
    init_success := T.Initialize();
    `defer {
        Log("shutting down %", T);
        T.Shutdown();
    }
    return init_success;
}

String_Reset :: inline (s: *string) {
    if s.data != null {
        free(s.data);
        s.data = null;
    }
    s.count = 0;
}

Array_Delete :: inline (arr: *[]$T) {
    if arr.data != null {
        free(arr.data);
        arr.data = null;
    }
    arr.count = 0;
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

Temp_Copy_String :: inline (str: string) -> string {
    out_str := talloc_string(str.count);
    memcpy(out_str.data, str.data, out_str.count);
    return out_str;
}

Temp_Copy_Array :: inline (array: []$T) -> []T {
    out_array := Temp_Buffer(T, array.count);
    memcpy(out_array.data, array.data, out_array.count * size_of(T));
    return out_array;
}

To_Lower_Temp :: inline (str: string) -> string {
    out_str := talloc_string(str.count);
    to_lower_diff: u8 = #char "a" - #char "A";
    for 0..out_str.count-1 {
        c := str[it];
        if c <= #char "Z" && c >= #char "A" {
            out_str[it] = c + to_lower_diff;
        }  else {
            out_str[it] = c;
        }
    }
    return out_str;
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
Inline_Buffer_Append :: inline (buf: *[]$T, item: T) {
    buf.count += 1;
    buf.*[buf.count-1] = item;
}

Inline_Buffer_Append :: inline (buf: *[]$T, items: []T)  {
    for items {
        Inline_Buffer_Append(buf, it);
    }
}

Arrays_Equal :: inline (a: []$T, b: []T) -> bool {
    if a.count != b.count return false;
    for a { if it != b[it_index] then return false; }
    return true;
}

Array_Append :: inline (a: *[]$T, b: []T) {
    if b.count == 0 then return;
    prev_count := a.count;
    array_resize(a, a.count + b.count);
    memcpy(a.data + prev_count, b.data, (a.count - prev_count) * size_of(T));
}

Prefix_String :: inline (str: string, prefix: string) -> string {
    new_str := talloc_string(prefix.count + str.count);
    memcpy(new_str.data, prefix.data, prefix.count);
    memcpy(new_str.data + prefix.count, str.data, str.count);
    return new_str;
}

Prefix_Postfix_String :: inline (str: string, prefix: string, postfix: string) -> string {
    new_str := talloc_string(prefix.count + str.count + postfix.count);
    if prefix.count > 0 {
        memcpy(new_str.data, prefix.data, prefix.count);
    }
    memcpy(new_str.data + prefix.count, str.data, str.count);
    if postfix.count > 0 {
        memcpy(new_str.data + prefix.count + str.count, postfix.data, postfix.count);
    }
    return new_str;
}

Temp_Array_Prepend_Append :: inline (arr: []$T, prefix: []T, suffix: []T) -> []T {
    t := Temp_Buffer(T, prefix.count + arr.count + suffix.count);
    if prefix.count > 0 {
        memcpy(t.data, prefix.data, prefix.count * size_of(T));
    }
    memcpy(t.data + prefix.count, arr.data, arr.count * size_of(T));
    if suffix.count > 0 {
        memcpy(t.data + prefix.count + arr.count, suffix.data, suffix.count * size_of(T));
    }
    return t;
}

Reverse_String :: inline (str: string) {
    b: s64;
    half_count := str.count >> 1;
    while b <= half_count {
        e := str.count - 1 - b;
        str[b], str[e] = str[e], str[b];
        b += 1;
    }
}

TO_LOWER_DIFFERENCE :: #char "a" - #char "A";

Find_Index_From_Left :: inline (str: string, pattern: string, $STR_TO_LOWER := false) -> s64 {
    match_count := 0;
    for 0..str.count-1 {
        c := str[it];
        #if STR_TO_LOWER {
            c = To_Lower(c);
        }
        if c == pattern[match_count] {
            match_count += 1;
            if match_count == pattern.count {
                return it - match_count + 1;
            }
        } else {
            remain_ct := str.count - it - 1;
            if remain_ct < pattern.count {
                break;
            }
            match_count = 0;
        }
    }
    return -1;
}

Is_Alpha_Upper :: inline (c: $T) -> bool {
    return c <= #char "Z" && c >= #char "A";
}

Is_Alpha_Lower :: inline (c: $T) -> bool {
    return c <= #char "z" && c >= #char "a";
}

To_Upper :: inline (c: $T, $CHECKED := true) -> T 
#modify {
    return (cast(*Type_Info)T).type == .INTEGER;
} {
    #if CHECKED {
        if !Is_Alpha_Lower(c) {
            return c;
        }
    }
    return c - TO_LOWER_DIFFERENCE;
}

To_Lower :: inline (c: $T, $CHECKED := true) -> T 
#modify {
    return (cast(*Type_Info)T).type == .INTEGER;
} {
    #if CHECKED {
        if !Is_Alpha_Upper(c) {
            return c;
        }
    }
    return c + TO_LOWER_DIFFERENCE;
}

Paste_Arrays :: (a: []$T, b: []T) -> []T {
    arr := Temp_Buffer(T, a.count + b.count);
    Memcpy(arr.data, a.data, a.count);
    Memcpy(arr.data + a.count, b.data, b.count);
    return arr;
}

Memcpy :: (dest: *$T, src: *T, count: s64) #expand {
    memcpy(dest, src, count * size_of(T));
}

Tokenize_By_Whitespace :: (in_str: []u32, tokens: *[..][]u32) {
    cur_token := array_add(tokens);
    for in_str {
        if Is_Unmarked_Whitespace(it) {
            if cur_token.data != null {
                cur_token = array_add(tokens);
            }
        } else {
            if cur_token.data == null {
                cur_token.data = in_str.data + it_index;
            }
            cur_token.count += 1;
        }
    }
    if cur_token.count == 0 {
        array_unordered_remove_by_index(tokens, tokens.count-1);
    }
}

Is_Slash :: inline (c: $T) -> bool {
    return c == #char "/" || c == #char "\\";
}

SerialBuffer :: struct {
    bytes: [..]u8;
    deserialize_offset: s32;
    mode_switch: enum u32 {
        SERIALIZE;
        DESERIALIZE;
    }
}

// TODO: serialize specializations for arrays and strings, but optional
// TODO: serialize bits

Clear :: (buf: *SerialBuffer, keep_allocation := true) {
    if keep_allocation {
        array_reset_keeping_memory(*buf.bytes);
    } else {
        array_reset(*buf.bytes);
    }
    buf.deserialize_offset = 0;
    buf.mode_switch = .SERIALIZE;
}

Serialize :: (buffer: *SerialBuffer, item: *$T) {
    write_offset := buffer.bytes.count;
    write_size := size_of(T);
    #if SERIALIZE_DEBUG {
        info := cast(*Type_Info)T;
        type_tag := info.type;
        write_size += size_of(Type_Info_Tag);
    }
    array_resize(*buffer.bytes, write_offset + write_size, false);
    #if SERIALIZE_DEBUG {
        memcpy(buffer.bytes.data + write_offset, *type_tag, size_of(Type_Info_Tag));
        write_offset += size_of(Type_Info_Tag);
    }
    memcpy(buffer.bytes.data + write_offset, xx item, size_of(T));
}

Deserialize :: (buffer: *SerialBuffer, item: *$T) {
    #if SERIALIZE_DEBUG {
        unpacking_type_tag: Type_Info_Tag = ---;
        memcpy(*unpacking_type_tag, buffer.bytes.data + buffer.deserialize_offset, size_of(Type_Info_Tag));
        buffer.deserialize_offset += size_of(Type_Info_Tag);
        info := cast(*Type_Info)T;
        assert(info.type == unpacking_type_tag);
    }
    memcpy(xx item, buffer.bytes.data + buffer.deserialize_offset, size_of(T));
    buffer.deserialize_offset += size_of(T);
}

Serialize_Or_Deserialize :: (buffer: *SerialBuffer, item: *$T) {
    if buffer.mode_switch == .SERIALIZE {
        Serialize(buffer, item);
    } else {
        Deserialize(buffer, item);
    }
}

DirectoryListItem :: struct {
    name:   string;
    is_symlink:   bool;
    is_directory: bool;
}

Directory_List :: (path: string) -> bool, []DirectoryListItem #must {
    items: [..]DirectoryListItem;
    items.allocator = temp;
    Visitor :: (info: *File_Visit_Info, user_data: *[..]DirectoryListItem) {
        array_add(user_data, .{Temp_Copy_String(info.short_name), info.is_symlink, info.is_directory});
    }

    success := visit_files(path, false, *items, Visitor, visit_directories=true);
    return success, items;
}

Convert_To_Forward_Slashes :: (str: string) {
    for 0..str.count-1 {
        if str[it] == #char "\\" {
            str[it] = #char "/";
        }
    }
}

Is_Basic_Text_File_Extension :: (ext: string) -> bool {
    return ext == "txt"
        || ext == "gitignore";
}

// TODO: probably map or just linear lookup hash table
Is_Code_File_Extension :: (ext: string) -> bool {
    return ext == "c"
        || ext == "cpp"
        || ext == "jai"
        || ext == "py"
        || ext == "h"
        || ext == "hpp"
        || ext == "cs"
        || ext == "java"
        || ext == "php"
        || ext == "sh"
        || ext == "swift"
        || ext == "vb"
        || ext == "bas"
        || ext == "r"
        || ext == "asm"
        || ext == "a51"
        || ext == "inc"
        || ext == "nasm"
        || ext == "ahk"
        || ext == "ahkl"
        || ext == "bat"
        || ext == "cmd"
        || ext == "md";
}

Is_Binary_File_Extension :: (ext: string) -> bool {
    return ext == "exe"
        || ext == "lib"
        || ext == "dll"
        || ext == "a"
        || ext == "o";
}

Print_Hex_Dump :: (data: []u8, width := 16) {
    assert(width > 0);
    builder: String_Builder;
    builder.allocator = temp;
    print_to_builder(*builder, "\n");
    line_byte_ct := 0;
    for i : 0..data.count-1 {
        if line_byte_ct == 0 {
            print_to_builder(*builder, "0x% | ", FormatInt.{value=i, base=16, minimum_digits=8});
        }
        print_to_builder(*builder, "% ", FormatInt.{value=data[i], base=16, minimum_digits=2});
        line_byte_ct += 1;
        if line_byte_ct == width || (line_byte_ct > 0 && i == data.count-1) {
            str := Temp_Copy_String(string.{line_byte_ct, *data[i-line_byte_ct+1]});
            // ansi dump
            while line_byte_ct < width {
                print_to_builder(*builder, "   ");
                line_byte_ct += 1;
            }
            for 0..str.count-1 {
                c := *str[it];
                if c.* == #char "\x1b" {
                    c.* = #char "^";
                } else if c.* == #char "\n" {
                    c.* = #char "`";
                } else if c.* < 32 || c.* > 126 {
                    c.* = #char ".";
                }
            }
            print_to_builder(*builder, "| %\n", str);
            line_byte_ct = 0;
        }
    }
    print(builder_to_string(*builder));
}

Pair :: struct($T1: Type, $T2: Type) {
    a: T1;
    b: T2;
}

Generate_Enumerated_Array_CT :: (enum_type_name: string, enum_backing_type: string, array_name: string, proc_name: string, $PairValueType: Type, enum_array_item_pairs: ..Pair(string, PairValueType)) -> string {
    builder: String_Builder;
    print_to_builder(*builder, "% :: enum % {\n", enum_type_name, enum_backing_type);
    for enum_array_item_pairs {
        print_to_builder(*builder, "\t%;\n", it.a);
    }
    print_to_builder(*builder, "}\n% := %.[\n", array_name, PairValueType);
    for enum_array_item_pairs {
        if it_index == enum_array_item_pairs.count - 1 {
            print_to_builder(*builder, "\t%\n];\n", it.b);
        } else {
            print_to_builder(*builder, "\t%,\n", it.b);
        }
    }
    print_to_builder(*builder, "% :: inline (key: %) -> % { return %[key]; }", proc_name, enum_type_name, PairValueType, array_name);
    return builder_to_string(*builder);
}
