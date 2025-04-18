

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
            Execute_Command_Toggle_Tool_View(.[]);
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
        split.layers[0].debug = .{type=.TEXT_BUFFER};
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
    tool_view := *view_pool.items[tool_view_id];
    base_empty_view := *view_pool.items[base_empty_view_id];
    screen_proportion := *settings_file_data.tool_view_screen_proportion;
    screen_proportion.* = clamp(screen_proportion.*, 0.05, 1.0);
    if tool_view_is_active {
        tool_view_is_active = false;
        tool_view.viewport.left = 0.0;
        base_empty_view.viewport.right = 1.0;
        Pop_Active_View_ID();
    } else {
        tool_view_is_active = true;
        tool_view.viewport.left = screen_proportion.*;
        base_empty_view.viewport.right = 1.0 - screen_proportion.*;
        tool_view.layers[tool_view.active_layer].need_reinit = true;
        Push_Active_View_ID(tool_view_id);
    }
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

