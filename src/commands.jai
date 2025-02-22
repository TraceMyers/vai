
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
