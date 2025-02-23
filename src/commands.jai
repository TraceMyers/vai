
// TODO: backslash escaping (... rethink?)

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
    if (tokens.count == 0) {
        return;
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
        Log("no procedure bound to command %", command);
    }
}

Parse_Command :: (str: []u32) -> Command {
    best_match := Command.NONE;
    best_match_ct := 0;
    num_matches := 0;
    for binding : COMPTIME_COMMAND_BINDINGS {
        match_ct := 0;
        for i : 0..binding.input.count-1 {
            if i >= str.count {
                break;
            } else if str[i] == binding.input[i]  {
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
        Close_View(background_view_id);
    case .BUFFER;
        Log_Warning("close buffer isn't yet implemented.");
    }
}

Get_File_Editor_Background_Layer :: () -> *View, *ViewLayer {
    if background_view_id < 0 {
        return null, null;
    }
    bg_view := View_From_ID(background_view_id);
    bg_layer := Active_Layer_Of_View(bg_view);
    if bg_layer == null {
        return null, null;
    }
    if bg_layer.type != .FILE_EDITOR {
        return null, null;
    }
    return bg_view, bg_layer;
}

Execute_Command_Open :: (args: [][]u32) {
    if args.count == 0 {
        return;
    }
    _, bg_layer := Get_File_Editor_Background_Layer();
    if bg_layer == null {
        return;
    }
    filename := Encode(As_String(args[0]), .UTF32, .UTF8);
    new_buffer_id := Get_File_Buffer_ID(filename);
    if new_buffer_id == -1 {
        return;
    }
    bg_layer.file_editor.file_buffer = new_buffer_id;
}

Execute_Command_Split :: (args: [][]u32, vertical: bool) {
    // note that 'horizontal' and 'vertical' are inverted compared to normal vim, because I don't think vim's version of these this is intuitive
    bg_view, bg_layer := Get_File_Editor_Background_Layer();
    if bg_layer == null {
        return;
    }
    new_view := Split_View(bg_view, ifx vertical then .VERTICAL else .HORIZONTAL, false);
    background_view_id = Get_Item_Index(*view_pool, new_view);
    file_editor_id := bg_layer.file_editor.file_buffer;
    if args.count != 0 {
        filename := Encode(As_String(args[0]), .UTF32, .UTF8);
        new_buffer_id := Get_File_Buffer_ID(filename);
        if new_buffer_id != -1 then file_editor_id = new_buffer_id;
    }
    new_view.layers[0].file_editor.file_buffer = file_editor_id;
}
Execute_Command_Split_Vertical :: #bake_arguments Execute_Command_Split(vertical=true);
Execute_Command_Split_Horizontal :: #bake_arguments Execute_Command_Split(vertical=false);