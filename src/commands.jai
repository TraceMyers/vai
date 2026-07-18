
CommandAutocompleteMatch :: struct {
    input: string;
    description: string;
}

CommandAutocompleteState :: struct {
    open: bool;
    initial_input: [..]u32;
    matches: [..]CommandAutocompleteMatch;
    selected_index: s64 = -1;
    replacement_start: s64;
}

command_autocomplete: CommandAutocompleteState;

Command_Autocomplete_Is_Open :: () -> bool {
    return command_autocomplete.open;
}

Command_Autocomplete_Input_Matches :: (candidate: string, prefix: []u32) -> bool {
    if candidate.count == 0 || prefix.count > candidate.count {
        return false;
    }
    for prefix {
        if Remove_Modifier_Flags(it) != candidate[it_index] {
            return false;
        }
    }
    return true;
}

Command_Autocomplete_Input_Is_Whitespace :: (code_point: u32) -> bool {
    return Is_Unmarked_Whitespace(Remove_Modifier_Flags(code_point));
}

Command_Autocomplete_Input_Range_Equals :: (input: []u32, begin: s64, end: s64, candidate: string) -> bool {
    if begin < 0 || end < begin || end > input.count || end-begin != candidate.count {
        return false;
    }
    for candidate {
        if Remove_Modifier_Flags(input[begin+it_index]) != cast(u32)it {
            return false;
        }
    }
    return true;
}

Command_Autocomplete_Build_Command_Matches :: (prefix: []u32) {
    array_reset_keeping_memory(*command_autocomplete.matches);
    for binding: COMPTIME_COMMAND_BINDINGS {
        if it_index == cast(s64)Command.NONE then continue;
        matched := false;
        for binding.input {
            if Command_Autocomplete_Input_Matches(it, prefix) {
                matched = true;
                break;
            }
        }
        if matched {
            array_add(*command_autocomplete.matches, .{
                binding.input[0],
                binding.extension.description,
            });
        }
    }
}

Command_Autocomplete_Option_Context :: (input: []u32) -> s64, []u32, bool {
    replacement_start: s64;
    option_prefix: []u32;
    valid: bool;
    command_end: s64;
    while command_end < input.count && !Command_Autocomplete_Input_Is_Whitespace(input[command_end]) {
        command_end += 1;
    }
    if command_end == input.count {
        return replacement_start, option_prefix, valid;
    }
    if !Command_Autocomplete_Input_Range_Equals(input, 0, command_end, "set")
    && !Command_Autocomplete_Input_Range_Equals(input, 0, command_end, "s") {
        return replacement_start, option_prefix, valid;
    }

    replacement_start = command_end;
    while replacement_start < input.count && Command_Autocomplete_Input_Is_Whitespace(input[replacement_start]) {
        replacement_start += 1;
    }
    for replacement_start..input.count-1 {
        if Command_Autocomplete_Input_Is_Whitespace(input[it]) {
            return 0, .{}, false;
        }
    }

    option_prefix.data = input.data + replacement_start;
    option_prefix.count = input.count - replacement_start;
    valid = true;
    return replacement_start, option_prefix, valid;
}

Command_Autocomplete_Build_Option_Matches :: (prefix: []u32) {
    array_reset_keeping_memory(*command_autocomplete.matches);
    for option_mappings {
        if Command_Autocomplete_Input_Matches(it.input, prefix) {
            array_add(*command_autocomplete.matches, .{
                it.input,
                it.extension.description,
            });
        }
    }
}

Command_Autocomplete_Apply_Selected :: () {
    if !command_autocomplete.open
    || command_autocomplete.selected_index < 0
    || command_autocomplete.selected_index >= command_autocomplete.matches.count {
        return;
    }
    selected := command_autocomplete.matches[command_autocomplete.selected_index];
    array_reset_keeping_memory(*auxiliary_input_buffer);
    if command_autocomplete.replacement_start > 0 {
        for 0..command_autocomplete.replacement_start-1 {
            array_add(*auxiliary_input_buffer, command_autocomplete.initial_input[it]);
        }
    }
    for selected.input {
        array_add(*auxiliary_input_buffer, cast(u32)it);
    }
}

Command_Autocomplete_Close :: (restore_initial: bool) {
    if restore_initial && command_autocomplete.open {
        array_reset_keeping_memory(*auxiliary_input_buffer);
        Array_Append(*auxiliary_input_buffer, command_autocomplete.initial_input);
    }
    command_autocomplete.open = false;
    command_autocomplete.selected_index = -1;
    command_autocomplete.replacement_start = 0;
    array_reset_keeping_memory(*command_autocomplete.initial_input);
    array_reset_keeping_memory(*command_autocomplete.matches);
}

Command_Autocomplete_Advance :: () {
    if command_autocomplete.open {
        command_autocomplete.selected_index = Increment_Wrap(
            command_autocomplete.selected_index,
            0,
            command_autocomplete.matches.count-1,
        );
        Command_Autocomplete_Apply_Selected();
        return;
    }

    array_reset_keeping_memory(*command_autocomplete.initial_input);
    Array_Append(*command_autocomplete.initial_input, auxiliary_input_buffer);

    has_whitespace := false;
    for command_autocomplete.initial_input {
        if Command_Autocomplete_Input_Is_Whitespace(it) {
            has_whitespace = true;
            break;
        }
    }
    if !has_whitespace {
        command_autocomplete.replacement_start = 0;
        Command_Autocomplete_Build_Command_Matches(command_autocomplete.initial_input);
    } else {
        replacement_start, option_prefix, valid_option_context :=
            Command_Autocomplete_Option_Context(command_autocomplete.initial_input);
        if !valid_option_context {
            array_reset_keeping_memory(*command_autocomplete.initial_input);
            return;
        }
        command_autocomplete.replacement_start = replacement_start;
        Command_Autocomplete_Build_Option_Matches(option_prefix);
    }
    if command_autocomplete.matches.count == 0 {
        command_autocomplete.replacement_start = 0;
        array_reset_keeping_memory(*command_autocomplete.initial_input);
        return;
    }

    command_autocomplete.open = true;
    command_autocomplete.selected_index = 0;
    Command_Autocomplete_Apply_Selected();
}

Command_Autocomplete_Accept :: () -> bool {
    if !command_autocomplete.open {
        return false;
    }
    Command_Autocomplete_Close(false);
    return true;
}

Command_Autocomplete_Cancel :: () -> bool {
    if !command_autocomplete.open {
        return false;
    }
    Command_Autocomplete_Close(true);
    return true;
}

Command_Autocomplete_Cancel_For_Typed_Input :: () {
    if command_autocomplete.open {
        Command_Autocomplete_Close(true);
    }
}


Parse_And_Execute_Commands :: (in_utf32: []u32) {
    if in_utf32.count == 0 {
        return;
    }

    cur_str: []u32;
    cur_str.data = in_utf32.data;

    for in_utf32 {
        if it == #char "|" {
            if cur_str.count > 0 {
                Parse_And_Execute_Command(cur_str);
            }
            cur_str.data = in_utf32.data + (it_index + 1);
            cur_str.count = 0;
        } else {
            cur_str.count += 1;
        }
    }
    if cur_str.count > 0 {
        Parse_And_Execute_Command(cur_str);
    }
}

Parse_And_Execute_Command :: (command_str: []u32) {
    tokens: [..][]u32;
    tokens.allocator = temp;
    Tokenize_By_Whitespace(command_str, *tokens);
    if tokens.count == 0 {
        return;
    }
    if tokens.count == 1 {
        ansi_str := Encode(As_String(tokens[0]), .UTF32, .ANSI, false);
        s32_val, success := parse_int(*ansi_str, s32);
        if success {
            Execute_Command_Go_To_Line(s32_val);
            return;
        }
    }

    command := Parse_Command(tokens[0]);
    if command == .NONE {
        return;
    }

    tokens.data += 1;
    tokens.count -= 1;
    executor := COMPTIME_COMMAND_BINDINGS[cast(s64)command].extension.proc;
    if executor {
        executor(tokens);
    } else {
        Log_Warning("no procedure bound to command %", command);
    }
}

Parse_Command :: (str: []u32) -> Command {
    best_match := Command.NONE;
    best_match_ct := 0;
    num_matches := 0;
    for binding : COMPTIME_COMMAND_BINDINGS {
        for 0..binding.input.count-1 {
            match_ct := 0;
            binding_input := binding.input[it];
            if binding_input.count == 0 then continue;
            for i: 0..binding_input.count-1 {
                if i >= str.count {
                    break;
                } else if str[i] == binding_input[i]  {
                    match_ct += 1;
                } else {
                    break;
                }
            }
            // An explicit shorthand (for example, :p) takes precedence over
            // a longer command that merely shares its prefix.
            if match_ct == str.count && binding_input.count == str.count {
                return As_Command(it_index);
            }
            if match_ct > 0 {
                if match_ct == best_match_ct {
                    num_matches += 1;
                } else if match_ct > best_match_ct {
                    best_match = As_Command(it_index);
                    best_match_ct = match_ct;
                    num_matches = 1;
                }
                break;
            }
        }
    }
    if best_match != .NONE && num_matches == 1 {
        return best_match;
    }
    // TODO: inform when ambiguous
    return .NONE; // no match or ambiguous match
}

Execute_Command_Quit :: (args: [][]u32) {
    quit = true;
}

Execute_Command_Go_To_Line :: (line_number: s32) {
    editor_view, editor_layer := Get_Active_Layer_Of_Type(.FILE_EDITOR);
    if editor_layer == null {
        return;
    }
    text_buffer := Layer_Text_Buffer(editor_layer);
    if text_buffer == null {
        return;
    }
    cursor := Layer_Cursor(editor_layer);
    if cursor == null {
        return;
    }
    cursor.y = clamp(line_number-1, sdw(0), sdw(text_buffer.lines.count-1));
    line := Line_View(text_buffer, cursor.y);
    cursor.x = Clamp_X_To_Line(cursor.target_x, line);
    cursor.just_moved = true;
    Center_View_On_Cursor(editor_layer, xx (text_buffer.lines.count-1));
}

Execute_Command_Close :: (args: [][]u32) {
    close_object : enum {
        NONE;
        VIEW;
        BUFFER;
    }

    if args.count == 0 || args[0].count <= 0 {
        close_object = .VIEW;
    } else {
        objects := string.["view", "buffer"];
        arg := args[0];
        for object: objects {
            if arg.count > object.count {
                continue;
            }
            match := true;
            for 0..arg.count-1 {
                if object[it] != arg[it] {
                    match = false;
                    break;
                }
            }               
            if match {
                close_object = cast(type_of(close_object))(it_index + 1);
                break;
            }
        }
    }

    if close_object == {
    case .NONE;
    case .VIEW;
        if Active_View_ID() == tool_view_id {
            Execute_Command_Hide_Tool_View();
        } else {
            Close_View(Active_View_ID());
        }
    case .BUFFER;
        _, layer := Get_Active_Layer_Of_Type(.FILE_EDITOR);
        if layer != null {
            Close_Text_Buffer(layer.file_editor.file_buffer);
        }
    }
}

Execute_Command_Open :: (args: [][]u32) {
    if args.count == 0 {
        return;
    }
    bg_view, bg_layer := Get_Active_Layer_Of_Type(.FILE_EDITOR);
    if bg_layer == null {
        return;
    }
    filename := Encode(As_String(args[0]), .UTF32, .UTF8);
    if filename.count == 0 {
        return;
    }
    if filename == "dbg" || filename == "debug" {
        split := Split_View(bg_view, .HORIZONTAL, false);
        split.layers[0].type = .DEBUG;
        split.layers[0].debug = .{type=.GENERAL_DEBUG};
        return;
    }
    Open_File_In_Editor(*bg_layer.file_editor, filename, true);
}

Execute_Command_Split :: (args: [][]u32, vertical: bool) {
    // note that 'horizontal' and 'vertical' are inverted compared to normal vim, because I don't think vim's version of these this is intuitive
    bg_view, bg_layer := Get_Active_Layer_Of_Type(.FILE_EDITOR);
    if bg_layer == null {
        return;
    }
    new_view := Split_View(bg_view, ifx vertical then .VERTICAL else .HORIZONTAL, false);
    Replace_Active_View_ID(Get_Item_Index(*view_pool, new_view));
    file_editor_id := bg_layer.file_editor.file_buffer;
    if args.count != 0 {
        filename := Encode(As_String(args[0]), .UTF32, .UTF8);
        Open_File_In_Editor(*new_view.layers[0].file_editor, filename, true);
    } else {
        new_view.layers[0].file_editor.file_buffer = file_editor_id;
    }
}
Execute_Command_Split_Vertical :: #bake_arguments Execute_Command_Split(vertical=true);
Execute_Command_Split_Horizontal :: #bake_arguments Execute_Command_Split(vertical=false);

Execute_Command_Save :: (args: [][]u32) {
    // TODO: save to new file using args
    bg_view, bg_layer := Get_Active_Layer_Of_Type(.FILE_EDITOR);
    if bg_layer == null {
        return;
    }
    file_editor_id := bg_layer.file_editor.file_buffer;
    if args.count == 0 {
        Save_Buffer_To_File(file_editor_id);
    } else {
        // TODO need to copy the file buffer rather than overwriting which file it points to
        filename := Encode(As_String(args[0]), .UTF32, .UTF8, append_null=false, allocator=context.allocator);
        if filename.count != 0 {
            free(file_buffers.items[file_editor_id].file_path);
            file_buffers.items[file_editor_id].file_path = filename;
            Save_Buffer_To_File(file_editor_id);
        }
    }
}

Execute_Command_Toggle_Tool_View :: (args: [][]u32) {
    // Hide only when the tool is already the focused view; otherwise Show, which
    // opens it if closed and moves the cursor into it if open-but-unfocused.
    if tool_view_is_active && Active_View_ID() == tool_view_id {
        Execute_Command_Hide_Tool_View();
        return;
    }
    Execute_Command_Show_Tool_View(last_tool_view_layer);
}

Execute_Command_Toggle_File_Explorer :: (args: [][]u32) {
    showing_explorer := tool_view_is_active && view_pool.items[tool_view_id].active_layer == cast(s8)ToolViewLayer.FILE_EXPLORER;
    if showing_explorer && Active_View_ID() == tool_view_id {
        Execute_Command_Hide_Tool_View();
        return;
    }
    Execute_Command_Show_Tool_View(.FILE_EXPLORER);
}

Execute_Command_Hide_Tool_View :: () {
    if !tool_view_is_active {
        return;
    }
    Hide_View(tool_view_id);
}

Execute_Command_Show_Tool_View :: (layer: ToolViewLayer) {
    tool_view := *view_pool.items[tool_view_id];
    base_empty_view := *view_pool.items[base_empty_view_id];
    screen_proportion := *settings_file_data.tool_view_screen_proportion;
    screen_proportion.* = clamp(screen_proportion.*, 0.05, 1.0);
    tool_view.active_layer = cast(s8)layer;
    last_tool_view_layer = layer;
    tool_view.layers[tool_view.active_layer].need_reinit = true;
    if tool_view.hidden {
        Show_View(tool_view_id);
    } else if !tool_view_is_active {
        tool_view_is_active = true;
        tool_view.viewport.left = screen_proportion.*;
        base_empty_view.viewport.right = 1.0 - screen_proportion.*;
    }
    // Always focus: showing an already-visible tool (e.g. from :t/:e/:p while the
    // cursor is in the editor, or switching layers) must move the cursor into it.
    Focus_Overlay_View_ID(tool_view_id);
}

Execute_Command_Toggle_Project_View :: (args: [][]u32) {
    showing_projects := tool_view_is_active && view_pool.items[tool_view_id].active_layer == cast(s8)ToolViewLayer.PROJECT_EXPLORER;
    if showing_projects && Active_View_ID() == tool_view_id {
        Execute_Command_Hide_Tool_View();
        return;
    }
    Project_Explorer_Show_Current_Project();
    Execute_Command_Show_Tool_View(.PROJECT_EXPLORER);
}

Execute_Command_Create_Project :: (args: [][]u32) {
    if args.count == 0 {
        return;
    }
    name := Encode(As_String(args[0]), .UTF32, .UTF8);
    main_directory := ifx args.count > 1
        then Encode(As_String(args[1]), .UTF32, .UTF8)
        else get_working_directory();
    Project_Create(name, main_directory);
    Project_Explorer_Show_All_Projects();
    Execute_Command_Show_Tool_View(.PROJECT_EXPLORER);
}

Execute_Command_Scroll_Buffer :: (args: [][]u32, next: bool) {
    view, layer := Get_Active_Layer_Of_Type(.FILE_EDITOR);
    if layer == null {
        return;
    }
    Scroll_File_Buffer(layer, next);
}
Execute_Command_Scroll_Buffer_Next :: #bake_arguments Execute_Command_Scroll_Buffer(next=true);
Execute_Command_Scroll_Buffer_Previous :: #bake_arguments Execute_Command_Scroll_Buffer(next=false);

Execute_Command_Set_Options :: (args: [][]u32) {
    for i : 0..args.count-2 {
        arg := args[i];
        for option_mappings {
            option_input := it.input;
            if option_input.count != arg.count {
                continue;
            }
            match := true;
            for 0..option_input.count-1 {
                if arg[it] != option_input[it] {
                    match = false;
                    break;
                }
            }
            if match {
                option_value_str := Encode(As_String(args[i+1]), .UTF32, .UTF8);
                option_enum := cast(Option)it_index;
                if it.extension.type == {
                case .INTEGER;
                    value, success := parse_int(*option_value_str, s32);
                    if success {
                        Set_Option(option_enum, value);
                    } else {
                        Log_Warning("failed to parse int option value from %", option_value_str);
                    }
                case .BOOL;
                    value, success: bool;
                    if option_value_str.count == 1 {
                        if option_value_str[0] == #char "0" {
                            value = false;
                            success = true;
                        } else if option_value_str[0] == #char "1" {
                            value = true; 
                            success = true;
                        } else {
                            success = false;
                        }
                    } else {
                        value, success = parse_bool(*option_value_str);
                    }
                    if success {
                        Set_Option(option_enum, value);
                    } else {
                        Log_Warning("failed to parse bool option value from %", option_value_str);
                    }
                case .STRING;
                    Set_Option(option_enum, copy_string(option_value_str));
                }
                i += 1;
                break;
            }
        }
    }
}

