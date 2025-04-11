
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Encode

Encode :: (in: string, from: TextEncoding, to: TextEncoding, assert_no_failure := true, append_null := false, allocator := temp) -> string, bool {
    text_bytes := Temp_Resize_Array(u8, in.count);
    string_index: s64;
    success := true;
    while string_index < in.count {
        max_bytes := min(in.count-string_index, 4);
        c := Encode(*in.data[string_index], from, to, max_bytes);
        if !c.encode_success {
            if assert_no_failure {
                assert(false, "failed to encode from % to %", from, to);
            }
            array_reset(*text_bytes);
            success = false;
            break;
        }
        Encode_Append(*text_bytes, c); 
        string_index += c.read_count;
    }

    subtract_null_byte_ct := 0;
    if append_null {
        if to == {
        case .UTF8; #through;
        case .ANSI;
            subtract_null_byte_ct = 1;
            Encode_Repeat(*text_bytes, 0, 1);
        case .UTF16;
            subtract_null_byte_ct = 2;
            Encode_Repeat(*text_bytes, 0, 2);
        case .UTF32;
            subtract_null_byte_ct = 4;
            Encode_Repeat(*text_bytes, 0, 4);
        }
    }
    
    str: string = ---;
    if allocator.data == temp.data {
        str = As_String(text_bytes);
    } else {
        str = copy_string(As_String(text_bytes));
    }
    str.count -= subtract_null_byte_ct;
    return str, success;
}

Encode_Temp_C_String :: inline (in: string, from: TextEncoding, to: TextEncoding) -> *u8 {
    return Encode(in, from, to, append_null=true).data;
}

Encode :: inline (in: CodePoint, to: TextEncoding) -> CodePoint {
    return Encode(cast,force(*u8)(*in.double_word), in.encoding, to);
}

Encode :: (in: *u8, from: TextEncoding, to: TextEncoding, max_read_count := 4) -> CodePoint {
    if #complete from == {
    case .ANSI;
        if #complete to == {
        case .UTF8;
            return Ansi_To_Utf8(in, max_read_count);
        case .UTF16;
            return Ansi_To_Utf16(in, max_read_count);
        case .UTF32;
            return Ansi_To_Utf32(in, max_read_count);
        case .ANSI;
            return As_Ansi(in, max_read_count);
        }
    case .UTF8;
        if #complete to == {
        case .UTF8;
            return As_Utf8(in, max_read_count);
        case .UTF16;
            return Utf8_To_Utf16(in, max_read_count);
        case .UTF32;
            return Utf8_To_Utf32(in, max_read_count);
        case .ANSI;
            return Utf8_To_Ansi(in, max_read_count);
        }
    case .UTF16;
        if #complete to == {
        case .UTF8;
            return Utf16_To_Utf8(in, max_read_count);
        case .UTF16;
            return As_Utf16(in, max_read_count);
        case .UTF32;
            return Utf16_To_Utf32(in, max_read_count);
        case .ANSI;
            return Utf16_To_Ansi(in, max_read_count);
        }
    case .UTF32;
        if #complete to == {
        case .UTF8;
            return Utf32_To_Utf8(in, max_read_count);
        case .UTF16;
            return Utf32_To_Utf16(in, max_read_count);
        case .UTF32;
            return As_Utf32(in, max_read_count);
        case .ANSI;
            return Utf32_To_Ansi(in, max_read_count);
        }
    }
    return .{};
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// helpers

Encode_Append :: inline (bytes: *[..]u8, code_point: CodePoint) {
    new_count := bytes.count + code_point.count;
    if new_count > bytes.allocated {
        array_reserve(bytes, max(bytes.count * 2, new_count));
    }
    memcpy(bytes.data + bytes.count, code_point.bytes.data, code_point.count);
    bytes.count = new_count;
}

Encode_Repeat :: inline (bytes: *[..]u8, code_point: u8, repeat_ct: s32) {
    if repeat_ct < 1 then return;
    new_count := bytes.count + repeat_ct;
    if new_count > bytes.allocated {
        array_reserve(bytes, max(bytes.count * 2, new_count));
    }
    for 0..repeat_ct-1 {
        bytes.count += 1;
        bytes.*[bytes.count-1] = code_point;
    }
}

As_String :: (c: CodePoint) -> string {
    return .{count=c.count, data=c.bytes.data};
}

// returns the byte index of the code point, given a code point index
Find_Byte_Index :: (str: string, code_point_index: s64, $ENCODING: TextEncoding) -> s64 {
    if code_point_index <= 0 {
        return 0;
    }
    byte_read_count := 0;
    code_read_count := 0;
    while byte_read_count < str.count {
        if code_read_count == i {
            break;
        }
        code_point := To_Utf32(*str[byte_read_count], str.count - byte_read_count, ENCODING);
        byte_read_count += code_point.read_count;
        code_read_count += 1;
    }
    return byte_read_count;   
}

Code_Point_Count :: (str: string, $ENCODING: TextEncoding) -> s64 {
    code_read_count := 0;
    byte_read_count := 0;
    while byte_read_count < str.count {
        code_point := To_Utf32(*str[byte_read_count], str.count - byte_read_count, ENCODING);
        byte_read_count += code_point.read_count;
        code_read_count += 1;
    }
    return code_read_count;
}

To_Utf32 :: (b: *u8, max_read_count: s64, $FROM_ENCODING: TextEncoding) -> CodePoint {
    #if #complete FROM_ENCODING == {
    case .UTF8;
        return Utf8_To_Utf32(in, max_read_count);
    case .UTF16;
        return Utf16_To_Utf32(in, max_read_count);
    case .UTF32;
        return As_Utf32(in, max_read_count);
    case .ANSI;       
        return Ansi_To_Utf32(in, max_read_count);
    }
}

Is_Ansi :: inline (in: u32) -> bool {
    return (in & 0xff) == in;
}

Is_Ascii :: inline (in: u32) -> bool {
    return (in & 0x7f) == in;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// conversions

Maybe_Return_Encode_Failure :: (condition: bool) #expand {
    if condition {
        `cs.encode_success = false;
        `return `cs;
    }
}

Utf8_To_Utf16 :: inline (b: *u8, max_read_count := 4) -> CodePoint {
    utf32 := Utf8_To_Utf32(b, max_read_count);
    cs := Utf32_To_Utf16(xx *utf32.double_word, 4);
    cs.read_count = utf32.read_count;
    return cs;
}

Utf16_To_Utf8 :: inline (b: *u8, max_read_count := 4) -> CodePoint {
    utf32 := Utf16_To_Utf32(b, max_read_count);
    cs :=  Utf32_To_Utf8(xx *utf32.double_word, 4);
    cs.read_count = utf32.read_count;
    return cs;
}

Ansi_To_Utf8 :: (b: *u8, max_read_count := 4) -> CodePoint {
    cs: CodePoint;
    Maybe_Return_Encode_Failure(max_read_count < 1);
    if Is_Ascii(b.*) {
        cs.double_word = b.*;
        cs.count = 1;
    } else {
        cs.bytes[0] = ub(0xc0) | ((b.* & 0xc0) >> 6);
        cs.bytes[1] = ub(0x80) |  (b.* & 0x3f);
        cs.count = 2;
    }
    cs.read_count = 1;
    cs.encoding = .UTF8;
    cs.encode_success = true;
    return cs;
}

Utf8_To_Ansi :: (b: *u8, max_read_count := 4) -> CodePoint {
    utf8_cs := As_Utf8(b);
    cs: CodePoint = ---;
    Maybe_Return_Encode_Failure(utf8_cs.count > 2);
    if utf8_cs.count == 1 {
        Maybe_Return_Encode_Failure(max_read_count < 1);
        cs.double_word = b.*;
        cs.read_count = 1;
    } else {
        Maybe_Return_Encode_Failure(max_read_count < 2);
        cs.double_word = ub((utf8_cs.bytes[0] & 0x03) << 6) | ub(utf8_cs.bytes[1] & 0x3f);
        cs.read_count = 2;
    }
    cs.count = 1;
    cs.encoding = .ANSI;
    cs.encode_success = true;
    return cs;
}

Utf32_To_Utf8 :: (b: *u8, max_read_count := 4) -> CodePoint {
    cs: CodePoint = ---;
    Maybe_Return_Encode_Failure(max_read_count < 4);
    c := (cast,force(*u32)(b)).*;
    Maybe_Return_Encode_Failure((c & 0xff_e0_00_00) != 0);
    if (c & 0x7f) == c {
        cs.double_word = c;
        cs.count = 1;
    } else if (c & 0x07_ff) == c {
        cs.bytes[0] = ub(0xc0) | ub((c & 0x07_c0) >> 6);
        cs.bytes[1] = ub(0x80) | ub( c & 0x00_3f);
        cs.count = 2;
    } else if (c & 0xff_ff) == c {
        cs.bytes[0] = ub(0xe0) | ub((c & 0xf0_00) >> 12);
        cs.bytes[1] = ub(0x80) | ub((c & 0x0f_c0) >> 6);
        cs.bytes[2] = ub(0x80) | ub( c & 0x00_3f);
        cs.count = 3;
    } else {
        cs.bytes[0] = ub(0xf0) | ub((c & 0x1c_00_00) >> 18);
        cs.bytes[1] = ub(0x80) | ub((c & 0x03_f0_00) >> 12);
        cs.bytes[2] = ub(0x80) | ub((c & 0x00_0f_c0) >> 6);
        cs.bytes[3] = ub(0x80) | ub( c & 0x00_00_3f);
        cs.count = 4;
    }
    cs.read_count = 4;
    cs.encoding = .UTF8;
    cs.encode_success = true;
    return cs;
}

Utf8_To_Utf32 :: inline (b: *u8, max_read_count := 4) -> CodePoint {
    cs: CodePoint;
    if (b[0] & 0x80) == 0 {
        Maybe_Return_Encode_Failure(max_read_count < 1);
        cs.double_word = b[0];
        cs.read_count = 1;
    } else if (b[0] & 0xf8) == 0xf0 {
        Maybe_Return_Encode_Failure(max_read_count < 4);
        cs.double_word = (udw(b[0] & 0x07) << 18) | (udw(b[1] & 0x3f) << 12) | (udw(b[2] & 0x3f) << 6) | udw(b[3] & 0x3f);
        cs.read_count = 4;
    } else if (b[0] & 0xf0) == 0xe0 {
        Maybe_Return_Encode_Failure(max_read_count < 3);
        cs.double_word = (udw(b[0] & 0x0f) << 12) | (udw(b[1] & 0x3f) << 6) | udw(b[2] & 0x3f);
        cs.read_count = 3;
    } else {
        Maybe_Return_Encode_Failure(max_read_count < 2);
        cs.double_word = (udw(b[0] & 0x1f) << 6) | udw(b[1] & 0x3f);
        cs.read_count = 2;
    }
    cs.count = 4;
    cs.encoding = .UTF32;
    cs.encode_success = true;
    return cs;
}

Utf32_To_Utf16 :: (b: *u8, max_read_count := 4) -> CodePoint {
    c := (cast,force(*u32)(b)).*;
    cs: CodePoint = ---;
    if c > U16_MAX {
        Maybe_Return_Encode_Failure(max_read_count < 4);
        c_20_bit := c - 0x1_00_00;
        cs.words[0] = uw(((c_20_bit & UTF16_HIGH_MASK) >> 10) + UTF16_HIGH_SURROGATE_MIN); // high surrogate
        cs.words[1] = uw((c_20_bit & UTF16_LOW_MASK) + UTF16_LOW_SURROGATE_MIN); // low surrogate
        cs.count = 4;
    } else {
        Maybe_Return_Encode_Failure(max_read_count < 2);
        Maybe_Return_Encode_Failure(c > UTF16_HIGH_SURROGATE_MIN && c < UTF16_LOW_SURROGATE_MAX);
        cs.double_word = c;
        cs.count = 2;
    }
    cs.read_count = 4;
    cs.encoding = .UTF16;
    cs.encode_success = true;
    return cs;
}

Utf16_To_Utf32 :: (b: *u8, max_read_count := 4) -> CodePoint {
    cs: CodePoint = ---;
    high_surrogate := (cast,force(*u16)b).*;
    if high_surrogate < UTF16_HIGH_SURROGATE_MIN || high_surrogate > UTF16_HIGH_SURROGATE_MAX {
        Maybe_Return_Encode_Failure(max_read_count < 2);
        cs.double_word = high_surrogate;
        cs.read_count = 2;
    } else {
        Maybe_Return_Encode_Failure(max_read_count < 4);
        low_surrogate := (cast,force(*u16)*(b[2])).*;
        Maybe_Return_Encode_Failure(low_surrogate < UTF16_LOW_SURROGATE_MIN || low_surrogate > UTF16_LOW_SURROGATE_MAX);
        _20_bit_high := (udw(high_surrogate) - UTF16_HIGH_SURROGATE_MIN) << 10;
        _20_bit_low := udw(low_surrogate) - UTF16_LOW_SURROGATE_MIN;
        cs.double_word = (_20_bit_high | _20_bit_low) + 0x1_00_00;
        cs.read_count = 4;
    }
    cs.count = 4;
    cs.encoding = .UTF32;
    cs.encode_success = true;
    return cs;
}

As_Ansi :: inline (b: *u8, max_read_count := 4) -> CodePoint {
    assert(max_read_count >= 1);
    cs: CodePoint = ---;
    cs.double_word = b.*;
    cs.count = 1;
    cs.read_count = 1;
    cs.encoding = .ANSI;
    cs.encode_success = true;
    return cs;
}

As_Utf8 :: (b: *u8, max_read_count := 4) -> CodePoint {
    cs: CodePoint;
    if (b[0] & 0x80) == 0 {
        Maybe_Return_Encode_Failure(max_read_count < 1);
        #if DEBUG_ENCODING then assert(Is_Ascii(b.*));
        cs.bytes[0] = b[0];
        cs.count = 1;
        cs.read_count = 1;
    } else if (b[0] & 0xf8) == 0xf0 {
        Maybe_Return_Encode_Failure(max_read_count < 4);
        cs.bytes[0] = b[0];
        cs.bytes[1] = b[1];
        cs.bytes[2] = b[2];
        cs.bytes[3] = b[3];
        cs.count = 4;
        cs.read_count = 4;
    } else if (b[0] & 0xf0) == 0xe0 {
        Maybe_Return_Encode_Failure(max_read_count < 3);
        cs.bytes[0] = b[0];
        cs.bytes[1] = b[1];
        cs.bytes[2] = b[2];
        cs.count = 3;
        cs.read_count = 3;
    } else {
        #if DEBUG_ENCODING then assert((b[0] & 0xe0) == 0xc0);
        Maybe_Return_Encode_Failure(max_read_count < 2);
        cs.bytes[0] = b[0];
        cs.bytes[1] = b[1];
        cs.count = 2;
        cs.read_count = 2;
    }
    cs.encoding = .UTF8;
    cs.encode_success = true;
    return cs;
}

Ansi_To_Utf16 :: inline (b: *u8, max_read_count := 4) -> CodePoint {
    cs: CodePoint = ---;
    Maybe_Return_Encode_Failure(max_read_count < 1);
    cs.words[0] = b[0];
    cs.words[1] = 0;
    cs.count = 2;
    cs.read_count = 1;
    cs.encoding = .UTF16;
    cs.encode_success = true;
    return cs;
}

As_Utf16 :: inline (b: *u8, max_read_count := 4) -> CodePoint {
    cs: CodePoint = ---;
    cs.words[0] = (cast,force(*u16)b).*;
    if cs.words[0] >= UTF16_HIGH_SURROGATE_MIN && cs.words[0] <= UTF16_HIGH_SURROGATE_MAX {
        Maybe_Return_Encode_Failure(max_read_count < 2);
        cs.words[1] = (cast,force(*u16)(*b[2])).*;
        cs.count = 4;
        cs.read_count = 4;
    } else {
        Maybe_Return_Encode_Failure(max_read_count < 4);
        cs.words[1] = 0;
        cs.count = 2;
        cs.read_count = 2;
    }
    cs.encoding = .UTF16;
    cs.encode_success = true;
    return cs;
}

Ansi_To_Utf32 :: inline (b: *u8, max_read_count := 4) -> CodePoint {
    cs: CodePoint = ---;
    Maybe_Return_Encode_Failure(max_read_count < 1);
    cs.double_word = b[0];
    cs.count = 4;
    cs.read_count = 1;
    cs.encoding = .UTF32;
    cs.encode_success = true;
    return cs;
}

As_Utf32 :: inline (b: *u8, max_read_count := 4) -> CodePoint {
    cs: CodePoint = ---;
    Maybe_Return_Encode_Failure(max_read_count < 4);
    cs.double_word = (cast,force(*u32)b).*;
    cs.count = 4;
    cs.read_count = 4;
    cs.encoding = .UTF32;
    cs.encode_success = true;
    return cs;
}

Utf16_To_Ansi :: inline (b: *u8, max_read_count := 4) -> CodePoint {
    cs: CodePoint = ---;
    Maybe_Return_Encode_Failure(max_read_count < 2);
    utf16 := (cast,force(*u16)b).*;
    Maybe_Return_Encode_Failure(!Is_Ansi(cast(u32)utf16));
    cs = As_Ansi(b, max_read_count);
    cs.read_count = 2;
    cs.encode_success = true;
    return cs;
}

Utf32_To_Ansi :: inline (b: *u8, max_read_count := 4) -> CodePoint {
    cs: CodePoint = ---;
    Maybe_Return_Encode_Failure(max_read_count < 4);
    utf32 := (cast,force(*u32)b).*;
    Maybe_Return_Encode_Failure(!Is_Ansi(utf32));
    cs = As_Ansi(b, max_read_count);
    cs.read_count = 4;
    cs.encode_success = true;
    return cs;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// types

TextEncoding :: enum u8 {
    UTF8;
    UTF16;
    UTF32;
    ANSI;
}

CodePoint :: struct {
    bytes: [4]u8 #align 4;
    // how many bytes are in the bytes array
    count: s8;
    // how many bytes were read when encoding this code point
    read_count: s8; 
    encoding: TextEncoding;
    encode_success: bool;

    #place bytes;
        words: [2]u16 = ---;
    #place bytes;
        double_word: u32 = ---;
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

UTF16_HIGH_SURROGATE_MIN : u32 : 0xd800;
UTF16_HIGH_SURROGATE_MAX : u32 : 0xdbff;
UTF16_LOW_SURROGATE_MIN : u32 : 0xdc00;
UTF16_LOW_SURROGATE_MAX : u32 : 0xdfff;
UTF16_HIGH_MASK : u32 : #run udw(0x3ff << 10);
UTF16_LOW_MASK : u32 : #run udw(0x3ff);

Utf16Word :: enum u8 {
    BASIC_MULTILINGUAL_PLANE;
    HIGH_SURROGATE;
    LOW_SURROGATE;
}
