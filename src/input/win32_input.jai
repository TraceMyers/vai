
Platform_Initialize_Input :: () {
    raw_input.allocator = temp;
    if settings_file_data.record_processed_input {
        write_entire_file("input_record.txt", "");
    }
}

Platform_Shutdown_Input :: () {
    array_reset(*raw_input);
}

Take_Raw_Input :: inline (input: u32) {
    assert(input <= U16_MAX);
    array_add(*raw_input, xx input);
}

Update_Modifier_Keys :: () {
    HELD_DOWN : s16 : 0x8000;
    alt_state := GetAsyncKeyState(VK_MENU);
    if (alt_state & HELD_DOWN) != 0 {
        modifier_keys |= .ALT;
    } else {
        modifier_keys &= ~.ALT;
    }
    shift_state := GetAsyncKeyState(VK_SHIFT);
    if (shift_state & HELD_DOWN) != 0 {
        modifier_keys |= .SHIFT;
    } else {
        modifier_keys &= ~.SHIFT;
    }
    control_state := GetAsyncKeyState(VK_CONTROL);
    if (control_state & HELD_DOWN) != 0 {
        modifier_keys |= .CONTROL;
    } else {
        modifier_keys &= ~.CONTROL;
    }
}

// returns utf32 code points flagged with modifier keys
Process_Raw_Input :: () -> []u32 {
    if raw_input.count == 0 {
        arr: []u32;
        if play_input_record {
            file_data, success := read_entire_file("input_record.txt");
            if success {
                arr.data = talloc(file_data.count);
                arr.count = file_data.count / 4;
                memcpy(arr.data, file_data.data, file_data.count);
                free(file_data);
            }
            play_input_record = false;
        }
        return arr;
    }
    
    utf16_str := As_String(raw_input);
    utf32_str := Encode(utf16_str, .UTF16, .UTF32);
    utf32_array := As_Array(utf32_str, u32);

    use_modifier_keys := modifier_keys;
    use_modifier_keys &= ~.SHIFT;

    for *utf32_array {
        it.* = Pack_Modified_Code_Point(it.*, use_modifier_keys);
    }

    array_reset(*raw_input);

    if settings_file_data.record_processed_input && utf32_array.count > 0 {
        f := file_open("input_record.txt", true, true);
        defer file_close(*f);
        file_len, success := file_length(f);
        if success {
            file_set_position(f, file_len);
            file_write(*f, utf32_array.data, utf32_array.count * size_of(u32));
        }
    }

    return utf32_array;
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

raw_input: [..]u16;