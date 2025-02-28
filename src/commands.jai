

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
        Close_View(active_view_id);
    case .BUFFER;
        _, layer := Get_File_Editor_Background_Layer();
        if layer != null {
            Close_Text_Buffer(layer.file_editor.file_buffer);
        }
    }
}

Get_File_Editor_Background_Layer :: () -> *View, *ViewLayer {
    if active_view_id < 0 {
        return null, null;
    }
    bg_view := View_From_ID(active_view_id);
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
    if filename.count == 0 {
        return;
    }
    new_buffer_id := Get_File_Buffer_ID(filename);
    if new_buffer_id == -1 {
        write_entire_file(filename, "");
        new_buffer_id = Get_File_Buffer_ID(filename);
        View_Layer_Soft_Reset(bg_layer);    
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
    active_view_id = Get_Item_Index(*view_pool, new_view);
    file_editor_id := bg_layer.file_editor.file_buffer;
    if args.count != 0 {
        filename := Encode(As_String(args[0]), .UTF32, .UTF8);
        new_buffer_id := Get_File_Buffer_ID(filename);
        if new_buffer_id != -1 {
            file_editor_id = new_buffer_id;
        } else {
            write_entire_file(filename, "");
            file_editor_id = Get_File_Buffer_ID(filename);
        }
        View_Layer_Soft_Reset(*new_view.layers[0]);    
    }
    new_view.layers[0].file_editor.file_buffer = file_editor_id;
}
Execute_Command_Split_Vertical :: #bake_arguments Execute_Command_Split(vertical=true);
Execute_Command_Split_Horizontal :: #bake_arguments Execute_Command_Split(vertical=false);

Execute_Command_Save :: (args: [][]u32) {
    // TODO: save to new file using args
    bg_view, bg_layer := Get_File_Editor_Background_Layer();
    if bg_layer == null {
        return;
    }
    file_editor_id := bg_layer.file_editor.file_buffer;
    if args.count == 0 {
        Save_Buffer_To_File(file_editor_id);
    } else {
        // TODO need to copy the file buffer rather than overwriting which file it points to
        filename := Encode(As_String(args[0]), .UTF32, .UTF8, false, context.allocator);
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
        tool_view.viewport.left = 0.0;
        base_empty_view.viewport.right = 1.0;
        tool_view_is_active = false;
        active_view_id = background_view_id;
        background_view_id = -1;
    } else {
        tool_view.viewport.left = screen_proportion.*;
        base_empty_view.viewport.right = 1.0 - screen_proportion.*;
        tool_view_is_active = true;
        background_view_id = background_view_id;
        active_view_id = tool_view_id;
        tool_view.layers[tool_view.active_layer].need_reinit = true;
    }
}
