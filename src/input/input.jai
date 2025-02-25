
NO_OP : u32 : ~cast(u32)0; 

// for used with Scoped_Construct
Input :: struct {

    Initialize :: () -> success: bool {
        Platform_Initialize_Input();

        temp_action_bindings: [..]ActionBinding;
        temp_action_bindings.allocator = temp;
        array_reserve(*temp_action_bindings, 128);

        // TODO: get overrides from vimrc and combine into one array
        for DEFAULT_ACTION_BINDINGS {
            new_binding, success := Create_Action_Binding(it.input, As_Action(it_index), *it.extension);
            if success then array_add(*temp_action_bindings, new_binding);
        }

        // sort s.t. they are ordered by the first byte of each action binding input
        Action_Code_Point_Compare :: (a: ActionBinding, b: ActionBinding) -> s32 {
            action_input_a := Action_Code_Point_String(a);
            first_byte_a := tub(action_input_a[0]);
            action_input_b := Action_Code_Point_String(b);
            first_byte_b := tub(action_input_b[0]);
            return sdw(first_byte_a) - sdw(first_byte_b);
        }
        quick_sort(temp_action_bindings, Action_Code_Point_Compare);

        // find the groups of action bindings: they share the same first byte and are in order after the sort
        group_bindings: []ActionBinding;
        group_bindings.data = temp_action_bindings.data;
        group_bindings.count = 1;
        group_byte: u8 = tub(Action_Code_Point_String(temp_action_bindings[0])[0]);
        for temp_action_bindings {
            first_byte := tub(Action_Code_Point_String(it)[0]);
            if first_byte != group_byte {
                Set_Action_Bindings(group_byte, group_bindings);
                group_byte = first_byte;
                group_bindings.data = *it;
                group_bindings.count = 1;
            } else {
                group_bindings.count += 1;
            }
        }
        if group_bindings.count > 0 {
            Set_Action_Bindings(group_byte, group_bindings);
        }

        Set_Capacity(*key_pressed, 256);

        return true;
    }

    Shutdown :: () {
        Platform_Shutdown_Input();
        array_reset(*action_input_buffer);
        array_reset(*action_binding_buffer);
        array_reset(*action_code_point_strings);
        array_reset(*action_repeat_buffer);
        array_reset(*search_pattern);
        Reset(*key_pressed);
    }

}

Inject_Modified_Utf32_Into_Frame_Input :: (input: []u32) {
    if input.count == 0 {
        return;
    }
    old_count := frame_input_stream.count;
    new_count := frame_input_stream.count + input.count;
    array_resize(*frame_input_stream, new_count);
    next_stream_index := frame_input_stream_index + 1;
    if next_stream_index < old_count {
        for #v2 < next_stream_index..old_count-1 {
            frame_input_stream[it+input.count] = frame_input_stream[it];
        }
    }
    memcpy(frame_input_stream.data + next_stream_index, input.data, input.count * size_of(u32));
}

Translate_Inputs_To_Actions :: () -> any_input: bool {
    // TODO: use text buffer?
    auxiliary_input_buffer_prev_count = auxiliary_input_buffer.count;

    action_matches: [..]ActionMatch;
    action_matches.allocator = temp;

    // TODO: how macro works = pump string into input queue, so it automatically gets translated into actions
    skip := false;
    processed_input := Process_Raw_Input();
    if processed_input.count == 0 && action_input_buffer.count == 0 && action_repeat_buffer.count == 0 {
        return false;
    }

    frame_input_stream_index = -1;
    Array_Append(*frame_input_stream, processed_input);

    // initial_time := seconds_since_init();
    loop_early_exit := false;

    while frame_input_stream_index + 1 < frame_input_stream.count {
        // current_time := seconds_since_init();
        // time_spent := current_time - initial_time;
        // if time_spent > 0.01 {
        //     loop_early_exit = true;
        //     break;
        // }

        frame_input_stream_index += 1;
        modified_utf32 := frame_input_stream[frame_input_stream_index];

        action_input_timer = ACTION_BUFFER_MAX_TIME;
        
        // intercept digits meant for repeating actions n times
        is_zero := modified_utf32 == #char "0";
        is_num_one_to_nine := (modified_utf32 >= #char "1" && modified_utf32 <= #char "9");
        is_pushable_repeat_digit := is_num_one_to_nine || (action_repeat_buffer.count > 0 && is_zero);
        if (vi_mode == .NORMAL || vi_mode == .VISUAL) && action_input_buffer.count == 0 && is_pushable_repeat_digit {
            array_add(*action_repeat_buffer, ub(modified_utf32));
            continue;
        }

        array_add(*action_input_buffer, modified_utf32);
        
        // try execute action
        match_count, exact_match_count := Get_Input_Buffer_Action_Matches(*action_matches, vi_mode);
        if match_count > 0 {
            if exact_match_count == match_count {
                Dump_Action_Input_Buffer(*action_matches);
            }
        } else {
            Dump_Action_Input_Buffer();
        }
    }

    if !loop_early_exit {
        array_reset_keeping_memory(*frame_input_stream);
    }

    if action_input_buffer.count > 0 || action_repeat_buffer.count > 0 {
        action_input_timer -= Smoothed_Delta_Time();
        if action_input_timer <= 0 {
            push_matches : *[..]ActionMatch = ifx Get_Input_Buffer_Action_Matches(*action_matches, vi_mode) then *action_matches else null;
            Dump_Action_Input_Buffer(push_matches);
        }
    }
    return true;
}

Dump_Action_Input_Buffer :: (action_matches: *[..]ActionMatch = null) {
    any_exact_action_matches: bool;
    if action_matches {
        any_exact_action_matches = Push_Exact_Action_Matches(action_matches);
    } 
    if (vi_mode == .COMMAND || vi_mode == .INSERT) && !any_exact_action_matches {
        detected_change_ignore := false;
        for action_repeat_buffer {
            if mid_change then array_add(*last_change_input, it);
            detected_change_ignore |= (it & NOT_CHANGE) != 0;
            array_add(*auxiliary_input_buffer, it);
        }
        for action_input_buffer {
            if mid_change then array_add(*last_change_input, it);
            detected_change_ignore |= (it & NOT_CHANGE) != 0;
            array_add(*auxiliary_input_buffer, Remove_Modifier_Flags(it));
        }
        if Process_Text_Input(auxiliary_input_buffer) {
            array_reset_keeping_memory(*auxiliary_input_buffer);
        }
    }
    array_reset_keeping_memory(*action_repeat_buffer);
    array_reset_keeping_memory(*action_input_buffer);

}

Get_Input_Buffer_Action_Matches :: (matches: *[..]ActionMatch, mode: ViMode) -> s64, s64 {
    array_reset_keeping_memory(matches);
    if action_input_buffer.count == 0 then return 0, 0;

    exact_match_count := 0;
    first_byte := tub(action_input_buffer[0]);
    action_bindings_bin := Action_Bindings(first_byte);
    for action_bindings_bin {
        if (it.modes & mode) == 0 then continue;
        if it.code_point_string_count < action_input_buffer.count then continue;
        code_point_string := Action_Code_Point_String(it);
        match := true;
        for action_input_buffer {
            if Remove_Flags_For_Comparison(it) != code_point_string[it_index] {
                match = false;
                break;
            }
        }
        if match {
            exact_match := action_input_buffer.count == it.code_point_string_count;

            array_add(matches, .{it.action, code_point_string, exact_match});
            if exact_match {
                exact_match_count += 1;
            }
        }
    }

    return matches.count, exact_match_count;
}

Push_Exact_Action_Matches :: (actions: *[..]ActionMatch) -> bool {
    any_exact: bool;
    for actions.* {
        if it.exact_match {
            #if DEBUG_ECHO_ACTIONS {
                Log("action: %", it.action);
            }
            action_executor_proc := DEFAULT_ACTION_BINDINGS[it.action].extension.proc;
            if action_executor_proc != null {
                repeat_ct: s64;
                parse_repeat_ct_success: bool;
                if action_repeat_buffer.count > 0 {
                    repeat_ct, parse_repeat_ct_success = parse_int(*As_String(action_repeat_buffer));
                }
                if !parse_repeat_ct_success {
                    repeat_ct = 1;
                }
                if action_executor_proc == Repeat_Last_Change {
                    repeat_ct *= ifx last_executor_repeat_ct == 0 then 1 else last_executor_repeat_ct;
                }

                prev_vi_mode := vi_mode;

                repeating_action = false;
                for 0..repeat_ct-1 {
                    action_executor_proc();
                    repeating_action = true;
                }

                // mid_change is also set to true when stuff is added to a change, but not all actions that begin changes themselves make a change
                if prev_vi_mode != .INSERT && vi_mode == .INSERT {
                    mid_change = true;
                }
                if mid_change {
                    if !prev_action_was_mid_change {
                        array_reset_keeping_memory(*last_change_input);
                        prev_action_was_mid_change = true;
                    }
                    Array_Append(*last_change_input, it.input);
                }
                // this SHOULD catch all cases of a change needing to be ended. if it doesn't, that is a bug.
                if it.action != .REDO && it.action != .UNDO && it.action != .REPEAT_LAST_CHANGE {
                    if (vi_mode == .NORMAL || vi_mode == .VISUAL) && mid_change {
                        End_Current_Change();
                        mid_change = false;
                        prev_action_was_mid_change = false;
                    }
                }

                action_executor_data.entered_normal_mode_past_line_end = false;
            }
            any_exact = true;
        }
    }
    return any_exact;
}

Action_Code_Point_String :: (binding: ActionBinding) -> []u32 {
    array: []u32 = ---;
    array.data = xx *action_code_point_strings[binding.code_point_string_index];
    array.count = xx binding.code_point_string_count;
    return array;
}

Action_Bindings :: (first_byte: u8) -> []ActionBinding {
    binding_group: []ActionBinding;
    indexer := action_bindings[first_byte];
    if indexer.count != 0 {
        binding_group.data = *action_binding_buffer[indexer.offset];
        binding_group.count = indexer.count;
    }
    return binding_group;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// init / binding creation

Special_Sequence_Modified_Code_Point :: (modifier_sequences: *[MODIFIER_COUNT][]u32, code_point_sequence: []u32) -> [2]u32, bool {
    if code_point_sequence.count == 0 then return .[0,0], false;

    modifier_flags: ModifierKeysState;
    for modifier_sequences.* {
        if it.count == 0 then continue;
        if Arrays_Equal(it, MODIFIER_CONTROL) {
            modifier_flags |= .CONTROL;
        } else if Arrays_Equal(it, MODIFIER_ALT) {
            modifier_flags |= .ALT;
        } else if Arrays_Equal(it, MODIFIER_COMMAND_OR_META) {
            modifier_flags |= .META;
        } else if Arrays_Equal(it, MODIFIER_SHIFT) {
            modifier_flags |= .SHIFT;
        }
    }

    out_values: [2]u32;
    if Arrays_Equal(code_point_sequence, CARRIAGE_RETURN) {
        for PLATFORM_CARRIAGE_RETURN {
            out_values[it_index] = it;
        }
    } else if Arrays_Equal(code_point_sequence, ESCAPE) {
        out_values[0] = #char "\x1b"; // esc key
    } else if code_point_sequence.count == 1 {
        out_values[0] = code_point_sequence[0];
    }

    success := false;
    for *out_values {
        if it.* != 0 {
            success = true;
            it.* = Pack_Modified_Code_Point(it.*, modifier_flags);
        }
    }
    return out_values, success;
}

// take a string that includes stuff like <C-Q> (representing control-Q), and turn those sequence sections into
// the code point in question ('Q' in the example), with flags in the most significant bits (control flag in this example)
// there's plenty of room to do this, since utf32 has lots of empty room in the upper bits
Modified_Action_Binding_String :: (utf32_str: string) -> string, bool {
    utf32_array := As_Array(utf32_str, u32);
    out_array: [..]u32;
    out_array.allocator = temp;
    array_reserve(*out_array, utf32_array.count);

    for i: 0..utf32_array.count-1 {
        code_point := utf32_array[i];
        if code_point == SPECIAL_SEQUENCE_OPEN[0] {
            if i == utf32_array.count-1 {
                return .{}, false;
            }

            separator_indices: [MODIFIER_COUNT]s64;
            set_separator_index: s64;
            sequence_close_index := -1;

            for j: i+1..utf32_array.count-1 {
                forward_code_point := utf32_array[j];
                if forward_code_point == MODIFIER_SEQUENCE_SEPARATOR[0] {
                    if set_separator_index >= separator_indices.count {
                        return .{}, false;
                    }
                    separator_indices[set_separator_index] = j;
                    set_separator_index += 1;
                } else if forward_code_point == SPECIAL_SEQUENCE_CLOSE[0] {
                    sequence_close_index = j;
                    break;
                }
            }
            if sequence_close_index == -1 {
                return .{}, false;
            }

            modifiers: [MODIFIER_COUNT][]u32;
            code_point_sequence: []u32;

            if set_separator_index != 0 {
                modifier_start := i + 1;
                for j: 0..set_separator_index-1 {
                    modifier_end := separator_indices[j];
                    modifiers[j].data = *utf32_array[modifier_start];
                    modifiers[j].count = modifier_end - modifier_start;
                    modifier_start = modifier_end + 1;
                }
                code_point_sequence.data = *utf32_array[modifier_start];
                code_point_sequence.count = sequence_close_index - modifier_start;
            } else {
                code_point_sequence.data = *utf32_array[i + 1];
                code_point_sequence.count = sequence_close_index - (i + 1);
            }

            modified_code_point, success := Special_Sequence_Modified_Code_Point(*modifiers, code_point_sequence);
            if !success {
                return .{}, false;
            }
            for modified_code_point {
                if it != 0 {
                    array_add(*out_array, it);
                }
            }

            i = sequence_close_index;
        } else {
            array_add(*out_array, code_point);
        }
    }
    return string.{count=out_array.count * 4, data=xx out_array.data}, out_array.count > 0;
}

Create_Action_Binding :: (input: string, action: Action, data: *ActionDataContainer, input_encoding := TextEncoding.ANSI) -> ActionBinding, bool {
    assert(input.count > 0);

    if input == "__INTERNAL__" then return .{}, false;
    
    utf32_input: string = ifx input_encoding != .UTF32 then Encode(input, input_encoding, .UTF32) else input;
    // take into account special inputs, such as inputs modified by control, or the platform-specific carriage return
    modified_utf32_input, success := Modified_Action_Binding_String(utf32_input);

    if !success {
        Log_Warning("failed to generate action binding % for input %", action, input);
        return .{}, false;
    }

    binding := ActionBinding.{action=action, modes=data.modes};

    old_size := action_code_point_strings.count;
    code_point_count := modified_utf32_input.count / 4;
    // the input string must be in 4 byte (utf32) increments
    assert(code_point_count * 4 == modified_utf32_input.count);
    assert(code_point_count <= U16_MAX);
    array_resize(*action_code_point_strings, old_size + code_point_count);
    memcpy(*action_code_point_strings[old_size], modified_utf32_input.data, modified_utf32_input.count);
    binding.code_point_string_index = xx old_size;
    binding.code_point_string_count = xx code_point_count;

    return binding, true;
}

Set_Action_Bindings :: (first_byte: u8, bindings: []ActionBinding) {
    indexer := *action_bindings[first_byte];
    assert(indexer.max >= 0 && bindings.count >= 0);
    if indexer.max < bindings.count {
        old_size := action_binding_buffer.count;
        array_resize(*action_binding_buffer, old_size + bindings.count);
        indexer.offset = xx old_size;
    }
    if bindings.count > 0 {
        memcpy(*action_binding_buffer[indexer.offset], bindings.data, size_of(ActionBinding) * bindings.count);
    }
    indexer.count = xx bindings.count;
    indexer.max = max(indexer.max, xx bindings.count);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// modifier keys

NOT_CHANGE : u32: 0x08_00_00_00;

Get_Modifiers :: inline (code_point: u32) -> ModifierKeysState {
    return xx ((code_point & xx (ModifierKeysState.ALL << 28)) >> 28);
}

Remove_Flags_For_Comparison :: inline (code_point: u32) -> u32 {
    return code_point & ~NOT_CHANGE;
}

Remove_Modifier_Flags :: inline (code_point: u32) -> u32 {
    return code_point & ~((cast(u32)(ModifierKeysState.ALL << 28)) | NOT_CHANGE);
}

Pack_Modified_Code_Point :: inline (code_point: u32, modifiers: ModifierKeysState) -> u32 {
    return code_point | xx (modifiers << 28);
}

Unpack_Modified_Code_Point :: inline (code_point: u32) -> code_point: u32, modifiers: ModifierKeysState {
    return Remove_Modifier_Flags(code_point), Get_Modifiers(code_point);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Is_Virtual_Key_Pressed :: (key: VirtualKey) -> bool {
    return Is_Bit_Set(*key_pressed, xx key);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

ModifierKeysState :: enum_flags u32 {
    NONE :: 0x00;
    META :: 0x01; // or command
    CONTROL;
    SHIFT;
    ALT;
    ALL :: META | CONTROL | SHIFT | ALT;
}

ActionBinding :: struct {
    code_point_string_index: s32;
    code_point_string_count: u16;
    action: Action;
    modes: ViMode;
}

ActionBindingGroupIndexer :: struct {
    offset: s32;
    count: s32;
    max: s32;
}

ActionMatch :: struct {
    action: Action;
    input: []u32;
    exact_match: bool;
}

ViMode :: enum_flags u8{
    NONE;
    NORMAL;
    VISUAL;
    INSERT;
    COMMAND;
    ALL :: NORMAL | VISUAL | INSERT | COMMAND;
}

ActionDataContainer :: struct {
    modes: ViMode;
    proc: Action_Executor = null;
}

CommandDataContainer :: struct {
    proc: Command_Executor = null;
}

ActionExecutorData :: struct {
    entered_normal_mode_past_line_end: bool;
    move_cursor_to_position: IntVector2;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

ESCAPE_CODE_SEQUENCE :: u32.[#char "\x1b"]; // esc key
SPECIAL_SEQUENCE_OPEN :: u32.[xx #char "<"];
SPECIAL_SEQUENCE_CLOSE :: u32.[xx #char ">"];
MODIFIER_SEQUENCE_SEPARATOR :: u32.[xx #char "-"];
MODIFIER_CONTROL :: u32.[xx #char "C"];
MODIFIER_COMMAND_OR_META :: u32.[xx #char "D"];
MODIFIER_ALT :: u32.[xx #char "A"];
MODIFIER_SHIFT :: u32.[xx #char "S"];
MODIFIER_COUNT :: 4;
CARRIAGE_RETURN :: u32.[xx #char "C", xx #char "R"];
ESCAPE :: u32.[xx #char "E", xx #char "s", xx #char "c"];
PLATFORM_CARRIAGE_RETURN :: #run 
    #ifx OS == .WINDOWS then u32.[xx #char "\r" /*, xx #char "\n"*/]
    else #ifx OS == .MACOS then u32.[xx #char "\n"]
    else #ifx OS == .LINUX then u32.[xx #char "\n"]
    else u32.[];

modifier_keys: ModifierKeysState;
action_input_buffer: [..]u32;

// when input does not translate to action, it overflows into this buffer
action_repeat_buffer: [..]u8;
auxiliary_input_buffer: [..]u32;
auxiliary_input_buffer_prev_count: s64;
action_input_timer: float32;
ACTION_BUFFER_MAX_TIME :: 0.5; // todo: this should be a setting (prob is a vim setting)

action_bindings: [U8_MAX]ActionBindingGroupIndexer;
action_binding_buffer: [..]ActionBinding;
action_code_point_strings: [..]u32;

frame_input_stream: [..]u32;
frame_input_stream_index: s64;

vi_mode: ViMode = .NORMAL;

// TODO: dynamic
enter_insert_mode_sequence := u32.[#char "i"];
enter_insert_mode_append_sequence := u32.[#char "a"];
enter_normal_mode_sequence := ESCAPE_CODE_SEQUENCE;
prepend_new_line_sequence := u32.[#char "O"];
append_new_line_sequence := u32.[#char "o"];

action_executor_data: ActionExecutorData;

selected_register := DEFAULT_REGISTER;

play_input_record: bool;

mid_change: bool;
prev_action_was_mid_change: bool;
last_change_input: [..]u32;

search_pattern: [..]u32;

key_pressed: BitArray(1);

// temp stuff for paste; need generic data restoration system
register_lines: [][]u32;
start_with_newline: bool;
repeating_action: bool;

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

#if OS == .WINDOWS {
    #load "win32_input.jai";
}