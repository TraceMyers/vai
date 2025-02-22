
Action_Execution :: struct {

    Initialize :: () {}

    Shutdown :: () {}
}

Cursor_Scroll_Down :: () {
    Init_Cursor_Proc_Or_Return(true);
    cursor.y = min(cursor.y+1, sdw(max(text_buffer.lines.count-1, 0)));
    line := Line_View(text_buffer, cursor.y);
    cursor.x = Clamp_X_To_Line(cursor.target_x, line);
}

Cursor_Scroll_Up :: () {
    Init_Cursor_Proc_Or_Return(true);
    cursor.y = max(cursor.y-1, sdw(0));
    line := Line_View(text_buffer, cursor.y);
    cursor.x = Clamp_X_To_Line(cursor.target_x, line);
}

Cursor_Scroll_Right :: () {
    Init_Cursor_Proc_Or_Return(true);
    line := Line_View(text_buffer, cursor.y);
    cursor.x += 1;
    cursor.x = Clamp_X_To_Line(cursor.x, line, .FORWARD);
    cursor.target_x = cursor.x;
}

Cursor_Scroll_Left :: () {
    Init_Cursor_Proc_Or_Return(true);
    line := Line_View(text_buffer, cursor.y);
    cursor.x -= 1;
    cursor.x = Clamp_X_To_Line(cursor.x, line);
    cursor.target_x = cursor.x;
}

Cursor_Scroll_To_Top :: () {
    Init_Cursor_Proc_Or_Return(true);
    cursor.y = 0;
    line := Line_View(text_buffer, cursor.y);
    cursor.x = Clamp_X_To_Line(cursor.target_x, line);
}

Cursor_Scroll_To_Bottom :: () {
    Init_Cursor_Proc_Or_Return(true);
    cursor.y = xx (text_buffer.lines.count-1);
    line := Line_View(text_buffer, cursor.y);
    cursor.x = Clamp_X_To_Line(cursor.target_x, line);
}

Cursor_Scroll_To_Line_End :: () {
    Init_Cursor_Proc_Or_Return(true);
    line := Line_View(text_buffer, cursor.y);
    cursor.x = max(sdw(ifx vi_mode == .INSERT then line.count else line.count-1), 0);
    cursor.x = Clamp_X_To_Line(cursor.x, line);
    cursor.target_x = cursor.x;
}

Cursor_Scroll_To_Line_Begin :: () {
    Init_Cursor_Proc_Or_Return(true);
    cursor.x = 0;
    line := Line_View(text_buffer, cursor.y);
    if line.count == 0 then return;
    while cursor.x < line.count - 1{
        if Is_Whitespace(line[cursor.x]) {
            cursor.x += 1;
        } else {
            break;
        }
    }
    if Is_Whitespace(line[cursor.x]) {
        cursor.x = 0;
    }
    cursor.target_x = cursor.x;
}

Cursor_Scroll_To_Line_Zero :: () {
    Init_Cursor_Proc_Or_Return(true);
    cursor.x = 0;
    cursor.target_x = 0;
}

Scroll_To_Next_Editor :: () {
    EditorSortInfo :: struct {
        view_id: s32;
        rect_upper_left: IntVector2;
    }

    sort_info: [..]EditorSortInfo;
    sort_info.allocator = temp;

    Collect_Sort_Info :: (view: *View, view_id: s64, viewport_id: s64, sort_info: *[..]EditorSortInfo) {
        if view.layers.data == null then return;
        active_layer := view.layers[view.active_layer];
        if active_layer.type != .FILE_EDITOR then return;
        array_add(sort_info, .{xx view_id, Upper_Left()});
    }

    Walk_View_Tree(0, Collect_Sort_Info, *sort_info);

    View_Compare :: (a: EditorSortInfo, b: EditorSortInfo) -> s32 {
        if a.rect_upper_left.x < b.rect_upper_left.x {
            return a.rect_upper_left.x - b.rect_upper_left.x;
        } else {
            return a.rect_upper_left.y - b.rect_upper_left.y;
        }
    }

    quick_sort(sort_info, View_Compare);

    next_editor := -1;
    for sort_info {
        if it.view_id == active_view_id {
            next_editor = it_index + 1;
        }
    }
    if next_editor >= sort_info.count {
        next_editor = 0;
    }

    active_view_id = sort_info[next_editor].view_id;
}

Insert_New_Line :: () {
    Init_Cursor_Proc_Or_Return(true);
    Break_Line_At(text_buffer, cursor.y, cursor.x);
    cursor.y += 1;
    cursor.x = 0;
}

Enter_Insert_Mode :: (append: bool) {
    Init_Cursor_Proc_Or_Return(true);
    vi_mode = .INSERT;
    if append {
        Cursor_Scroll_Right();
    }
}
Enter_Insert_Mode_Prepend   :: #bake_arguments Enter_Insert_Mode(append=false);
Enter_Insert_Mode_Append    :: #bake_arguments Enter_Insert_Mode(append=true);

Enter_Normal_Mode :: () {
    if vi_mode == {
    case .INSERT;
        Init_Cursor_Proc_Or_Return(true);
        line_count := Line_Count(text_buffer, cursor.y);
        action_executor_data.entered_normal_mode_past_line_end = cursor.x >= line_count; 
        Cursor_Scroll_Left();
    case .VISUAL;
    case .COMMAND;
        Init_Cursor_Proc_Or_Return(true, false);
        layer := Active_View_Layer();
        assert(layer.type == .VIM_CONSOLE);
        do_search := false;
        if layer.vim_console.mode == {
        case .COMMAND;
        case .SEARCH;
            if auxiliary_input_buffer.count > 0 {
                Get_Unmarked_Utf32(auxiliary_input_buffer, *search_pattern);
                do_search = true;
            } else {
                array_reset_keeping_memory(*search_pattern);
            }
        }
        array_reset_keeping_memory(*auxiliary_input_buffer);
        assert(background_view_id != -1);
        active_view_id = background_view_id;
        background_view_id = -1;
        if do_search  {
            Text_Pattern_Search_Forward();
        }
    }
    vi_mode = .NORMAL;
}

Backspace :: () {
    Backspace_Impl();
}

Backspace_Impl :: inline (is_change := true) {
    if vi_mode == .COMMAND {
        Init_Cursor_Proc_Or_Return(true, false);
        auxiliary_input_buffer.count = max(0, auxiliary_input_buffer.count - 1);
        return;
    } else {
        Init_Cursor_Proc_Or_Return(true);
        if cursor.x > 0 {
            // search backward for valid character to delete
            line := Line_View(text_buffer, cursor.y);
            cursor.x -= 1;
            while cursor.x > 0 {
                if !Is_Tab_Expanded_Space(line[cursor.x]) {
                    break;
                }
                cursor.x -= 1;
            }
            Remove_Code_Point(text_buffer, cursor.y, cursor.x);
        } else if cursor.y != 0 {
            Cursor_Scroll_Up();
            Cursor_Scroll_To_Line_End();
            src_line := Line_View(text_buffer, cursor.y+1);
            Insert_Code_Points(text_buffer, cursor.y, cursor.x, src_line, true, true);
            Remove_Line(text_buffer, cursor.y+1, is_change);
        }
    }
}

Delete_Character :: () {
    Init_Cursor_Proc_Or_Return(true);
    line_count := Line_Count(text_buffer, cursor.y);
    if line_count > 0 {
        Remove_Code_Point(text_buffer, cursor.y, cursor.x);
        line := Line_View(text_buffer, cursor.y);
        cursor.x = Clamp_X_To_Line(cursor.x, line);
        cursor.target_x = cursor.x;
    }
}

Insert_Line_And_Enter_Insert_Mode :: (append: bool) {
    Init_Cursor_Proc_Or_Return(true);
    if append {
        // insert before moving cursor so the state is always valid (if cursor on final line)
        Insert_Line(text_buffer, cursor.y+1);
        cursor.y += 1;
    } else {
        Insert_Line(text_buffer, cursor.y);
    }
    cursor.x = 0;
    cursor.target_x = 0;
    Enter_Insert_Mode_Prepend();
}
Append_Line_And_Enter_Insert_Mode :: #bake_arguments Insert_Line_And_Enter_Insert_Mode(append=true);
Prepend_Line_And_Enter_Insert_Mode :: #bake_arguments Insert_Line_And_Enter_Insert_Mode(append=false);

Delete_Line :: () {
    Init_Cursor_Proc_Or_Return(true);
    Set_Selected_Register_Text_To_Current_Line(text_buffer, cursor);
    if cursor.y == 0 && text_buffer.lines.count == 1 {
        Clear_Line(text_buffer, 0);
        cursor.x = 0;
        cursor.target_x = 0;
    } else {
        if cursor.y == text_buffer.lines.count - 1 {
            cursor.y -= 1;
            Remove_Line(text_buffer, cursor.y+1);
        } else {
            Remove_Line(text_buffer, cursor.y);
        }
        Cursor_Scroll_To_Line_Begin();
    }
}

Word_Scroll :: (forward: bool, small_word: bool) {
    Init_Cursor_Proc_Or_Return(true);
    line := Line_View(text_buffer, cursor.y);

    reference_blob: TextBlobType = ---;
    init_x := ifx forward then cursor.x else cursor.x - 1;
    init_y := cursor.y;
    if cursor.x >= line.count {
        reference_blob = .WHITESPACE;
    } else if !forward && cursor.x == 0 {
        reference_blob = .WHITESPACE;
    } else reference_blob = Get_Marked_Utf32_Blob_Type(line[init_x]);

    if forward {
        Cursor_Scroll_Right();
        found_next_blob := false;
        for 0..1 {
            while cursor.x < line.count {
                if Is_Alphanumeric_Or_Underscore(line[cursor.x]) {
                    if (small_word && reference_blob != .KEYWORD) || reference_blob == .WHITESPACE {
                        found_next_blob = true;
                        break;
                    }
                } else if Is_Whitespace(line[cursor.x]) {
                    reference_blob = .WHITESPACE;
                } else {
                    if (small_word && reference_blob != .NON_KEYWORD) || reference_blob == .WHITESPACE {
                        found_next_blob = true;
                        break;
                    }
                }
                cursor.x += 1;
            }
            if !found_next_blob {
                Word_Scroll_Forward_Maybe_Go_To_Next_Line();
            } else break;
        }
    } else {
        initial_cursor_x := cursor.x;
        Cursor_Scroll_Left();
        found_begin_of_prev_blob := false;
        for 0..1 {
            while cursor.x > 0 {
                 if Is_Alphanumeric_Or_Underscore(line[cursor.x-1]) {
                    if reference_blob == .WHITESPACE {
                        reference_blob = .KEYWORD;
                    } else if (small_word && reference_blob != .KEYWORD) || reference_blob == .WHITESPACE {
                        found_begin_of_prev_blob = true;
                        break;
                    }
                } else if Is_Whitespace(line[cursor.x-1]) {
                    if reference_blob != .WHITESPACE {
                        found_begin_of_prev_blob = true;
                        break;
                    }
                } else {
                    if reference_blob == .WHITESPACE {
                        reference_blob = .NON_KEYWORD;
                    } else if (small_word && reference_blob != .NON_KEYWORD) || reference_blob == .WHITESPACE {
                        found_begin_of_prev_blob = true;
                        break;
                    }
                }
                cursor.x -= 1;               
            }
            if it == 1 || cursor.x < initial_cursor_x && reference_blob != .WHITESPACE {
                break;
            }
            if !found_begin_of_prev_blob {
                if cursor.y == 0 {
                    break;
                } else {
                    Cursor_Scroll_Up();
                    line = Line_View(text_buffer, cursor.y);
                    Cursor_Scroll_To_Line_End();
                    reference_blob = .WHITESPACE;
                    if line.count == 0 then break;
                }
            } else break;
        }
    }
}
Word_Scroll_Forward_Small :: #bake_arguments Word_Scroll(forward=true, small_word=true);
Word_Scroll_Forward_Large :: #bake_arguments Word_Scroll(forward=true, small_word=false);
Word_Scroll_Backward_Small :: #bake_arguments Word_Scroll(forward=false, small_word=true);
Word_Scroll_Backward_Large :: #bake_arguments Word_Scroll(forward=false, small_word=false);

Word_Scroll_To_End :: (small: bool) {
    Init_Cursor_Proc_Or_Return(true);
    line := Line_View(text_buffer, cursor.y);

    pre_scroll_x := cursor.x;
    Cursor_Scroll_Right();

    reference_blob: TextBlobType = ---;
    init_x := cursor.x;
    init_y := cursor.y;
    if cursor.x >= line.count {
        reference_blob = .WHITESPACE;
    } else reference_blob = Get_Marked_Utf32_Blob_Type(line[init_x]);

    if init_x == line.count - 1 && reference_blob != .WHITESPACE && pre_scroll_x != init_x {
        return;
    }

    found_next_blob := false;
    iter_ct := 0;
    for 0..1 {
        while cursor.x + 1 < line.count {
            if Is_Alphanumeric_Or_Underscore(line[cursor.x+1]) {
                if reference_blob != .KEYWORD {
                    if reference_blob == .WHITESPACE {
                        reference_blob = .KEYWORD;
                    } else {
                        found_next_blob = true;
                        break;
                    }
                }
            } else if Is_Whitespace(line[cursor.x+1]) {
                if reference_blob != .WHITESPACE {
                    found_next_blob = true;
                    break;
                }
            } else {
                if reference_blob != .NON_KEYWORD {
                    if reference_blob == .WHITESPACE {
                        reference_blob = .NON_KEYWORD;
                    } else {
                        found_next_blob = true;
                        break;
                    }
                }
            }
            cursor.x += 1;
            iter_ct += 1;

        }
        if !found_next_blob {
            quit_early := cursor.x > init_x && reference_blob != .WHITESPACE;
            allow_nextline := it == 0;
            Word_Scroll_Forward_Maybe_Go_To_Next_Line(quit_early, allow_nextline);
        } else break;
    }
}
Word_Scroll_To_End_Small :: #bake_arguments Word_Scroll_To_End(small=true);
Word_Scroll_To_End_Large :: #bake_arguments Word_Scroll_To_End(small=false);

Delete_Word :: (inside: bool, small: bool, delete_trailing_whitespace: bool) {
    Init_Cursor_Proc_Or_Return(true);
    // 'delete inside word' = delete word the cursor is inside
    if inside {
        inside_x := cursor.x;
        inside_y := cursor.y;
        // so that we don't go back to the previous word
        Cursor_Scroll_Right();
        Word_Scroll(false, small);
        if cursor.y != inside_y {
            cursor.x = 0;
            cursor.y = inside_y;
        }
    }

    save_x := cursor.x;
    save_y := cursor.y;
    if delete_trailing_whitespace {
        Word_Scroll(true, small);
    } else {
        Word_Scroll_To_End(small);
        Cursor_Scroll_Right();
    }
    if cursor.y != save_y {
        cursor.y = save_y;
        cursor.x = xx Line_Count(text_buffer, cursor.y);
    }

    remove_count := cursor.x - save_x;
    cursor.x = save_x;
    if remove_count > 0 {
        Remove_Code_Points(text_buffer, cursor.y, cursor.x, remove_count);
    }
    cursor.x = Clamp_X_To_Line(cursor.x, Line_View(text_buffer, cursor.y));
}
Delete_Word_Small :: #bake_arguments Delete_Word(inside=false, small=true, delete_trailing_whitespace=true);
Delete_Word_Inside_Small :: #bake_arguments Delete_Word(inside=true, small=true, delete_trailing_whitespace=true);

Delete_Selection :: (enter_normal_mode: bool) {
    Init_Cursor_Proc_Or_Return(true);

    selection_begin, selection_end := Cursor_Selection(cursor);
    do_concatenate := selection_end.y != selection_begin.y;
    edit_y_offset: s32 = 1;

    code_point_sum := 0;
    for selection_begin.y..selection_end.y {
        code_point_sum += Line_Count(text_buffer, it);
    }
    num_lines := selection_end.y - selection_begin.y + 1;
    register_buffer := Temp_Buffer(u32, code_point_sum + num_lines + 1);
    register_buffer.count = 0;

    for selection_begin.y..selection_end.y {
        edit_y: s32 = ---;
        begin_x, end_x: s32 = ---;
        if it == selection_begin.y {
            begin_x = selection_begin.x;
            edit_y = selection_begin.y;
        } else {
            begin_x = 0;
            edit_y = selection_begin.y + edit_y_offset;
        }

        line := Line_View(text_buffer, edit_y);
        line_count: s32 = xx line.count;

        if it == selection_end.y {
            end_x = ifx line_count == 0 then 0 else selection_end.x;
        } else {
            end_x = line_count;
        }

        remove_count := end_x - begin_x;
        if remove_count <= 0 || remove_count == line_count {
            if it == selection_end.y {
                do_concatenate = false;
            } else if it == selection_begin.y {
                do_concatenate = false;
                edit_y_offset = 0;
            }
            Remove_Line(text_buffer, edit_y);
        } else {
            Remove_Code_Points(text_buffer, edit_y, begin_x, remove_count);
        }
    }
    cursor.y = min(selection_begin.y, sdw(text_buffer.lines.count-1));
    cursor.x = Clamp_X_To_Line(selection_begin.x, Line_View(text_buffer, cursor.y));
    cursor.target_x = cursor.x;

    // if this is a multi-line delete and the first and last line both had remaining characters
    if do_concatenate {
        Enter_Insert_Mode(false);
        Cursor_Scroll_Down();
        Cursor_Scroll_To_Line_Zero();
        Backspace_Impl(true);
    }

    if enter_normal_mode {
        Enter_Normal_Mode();
        if do_concatenate {
            Cursor_Scroll_Right();
        }
    }
}
Delete_Selection_And_Enter_Normal_Mode :: #bake_arguments Delete_Selection(enter_normal_mode=true);

Toggle_Comment_Selection :: () {
    Init_Cursor_Proc_Or_Return(true);

    selection_begin, selection_end: IntVector2;
    if vi_mode == .VISUAL {
        selection_begin, selection_end = Cursor_Selection(cursor);
    } else {
        selection_begin = .{cursor.x, cursor.y};
        selection_end = .{cursor.x, cursor.y};
    }

    Y_Iterate_Maybe_Continue :: () #expand {
        `cursor.y = `it;
        Cursor_Scroll_To_Line_Begin();
        `line := Line_View(`text_buffer, `cursor.y);
        if `line.count == 0 then continue;
    }

    save_cursor_x := cursor.x;
    save_cursor_y := cursor.y;
    toggle_on := false;
    for selection_begin.y..selection_end.y {
        Y_Iterate_Maybe_Continue();
        if cursor.x >= line.count - 1 || !Code_Point_Equal_To(line[cursor.x], #char "/") || !Code_Point_Equal_To(line[cursor.x+1], #char "/") {
            toggle_on = true;
            break;
        }
    }

    COMMENT_CODE_POINTS :: u32.[#char "/", #char "/", #char " "];

    if toggle_on then for selection_begin.y..selection_end.y {
        Y_Iterate_Maybe_Continue();
        Insert_Code_Points(text_buffer, cursor.y, cursor.x, COMMENT_CODE_POINTS);
    } else for selection_begin.y..selection_end.y {
        Y_Iterate_Maybe_Continue();
        if cursor.x < line.count - 2 && Code_Point_Equal_To(line[cursor.x+2], #char " ") {
            Remove_Code_Points(text_buffer, cursor.y, cursor.x, 3);
        } else {
            Remove_Code_Points(text_buffer, cursor.y, cursor.x, 2);
        }
    }
    cursor.x = save_cursor_x;
    cursor.y = save_cursor_y;
}

Replace_Selection :: () {
    Delete_Selection(false);
    Enter_Insert_Mode(false);
}

Replace_Line :: () {
    Init_Cursor_Proc_Or_Return(true);
    Clear_Line(text_buffer, cursor.y);
    cursor.x = 0;
    Enter_Insert_Mode(false);
}

Replace_Word :: (inside: bool, small: bool) {
    Delete_Word(inside, small, false);
    Enter_Insert_Mode(false);
}
Replace_Word_Small :: #bake_arguments Replace_Word(inside=false, small=true);
Replace_Word_Inside_Small :: #bake_arguments Replace_Word(inside=true, small=true);

Enter_Visual_Mode :: () {
    Init_Cursor_Proc_Or_Return(true);
    vi_mode = .VISUAL;
    cursor.begin_selection = .{cursor.x, cursor.y};
}

Delete_Toward_Line_Zero :: () {
    Init_Cursor_Proc_Or_Return(true);
    line := Line_View(text_buffer, cursor.y);
    if line.count == 0 || cursor.x == 0 then return;
    end_x := cursor.x;
    cursor.x = 0;
    delete_ct := end_x - cursor.x;
    Remove_Code_Points(text_buffer, cursor.y, cursor.x, delete_ct);
}

Replace_Toward_Line_Zero :: () {
    Delete_Toward_Line_Zero();
    Enter_Insert_Mode(false);
}

Text_Pattern_Search :: (forward: bool) {
    if search_pattern.count == 0 then return; // TODO: feedback
    Init_Cursor_Proc_Or_Return(true);

    Search_Line_For_Pattern :: inline (pattern_utf8: string, text_buffer: *TextBuffer, row: s32, col: s32, line_to_lower: bool) -> col: s32 {
        out_col: s32 = -1;
        line_bytes := Get_Line_Bytes(text_buffer, row); 
        line_bytes.data += col;
        line_bytes.count -= col;
        if line_bytes.count >= pattern_utf8.count {
            i := Find_Index_From_Left(line_bytes, pattern_utf8, true);
            if i != -1 {
                out_col = Collapsed_To_Expanded_Column(text_buffer, row, xx (i + col));
            }
        }
        return out_col;
    }

    Loop_Body :: ($ITERATE_LINE: string) -> bool #expand {
        `match_col = Search_Line_For_Pattern(`pattern_utf8, `text_buffer, `row, `col, `search_lowercase);
        if `match_col != -1 {
            `match_row = `row;
            return true;
        }
        `col = 0;
        #insert ITERATE_LINE;
        return false;
    }

    // smartcase option = if the search pattern doesn't have uppercase letters, then it's assumed we want to match against any case.
    search_lowercase := Is_Bool_Option_Set(.PATTERN_SEARCH_SMART_CASE);
    if search_lowercase then for search_pattern {
        if it <= #char "Z" && it >= #char "A" {
            search_lowercase = false;
            break;
        }
    }
    pattern_utf8 := Encode(As_String(search_pattern), .UTF32, .UTF8);
    
    // need to find the position given collapsed tabs so we're searching from the right place in the line's raw utf8
    col: s32 = 1;
    if cursor.x != 0 {
        col = Expanded_To_Collapsed_Column(text_buffer, cursor.y, cursor.x) + 1;
    }
    row := cursor.y;
    iter_ct := text_buffer.lines.count + 1;
    match_row, match_col: s32 = -1;
    if forward for 0..iter_ct-1 {
        if Loop_Body("`row = Increment_Wrap(`row, 0, xx (`text_buffer.lines.count-1));") then break;
    } else for 0..iter_ct-1 {
        if Loop_Body("`row = Decrement_Wrap(`row, 0, xx (`text_buffer.lines.count-1));") then break;
    }

    if match_col != -1 {
        cursor.x = match_col;
        cursor.y = match_row;
    }
}
Text_Pattern_Search_Forward :: #bake_arguments Text_Pattern_Search(forward=true);
Text_Pattern_Search_Backward :: #bake_arguments Text_Pattern_Search(forward=false);

Toggle_Letter_Case :: () {
    Init_Cursor_Proc_Or_Return(true);
    line := Line_View(text_buffer, cursor.y);
    letter := line[cursor.x];
    if Is_Alpha_Upper(letter) {
        line[cursor.x] = To_Lower(letter, false);
    } else if Is_Alpha_Lower(letter) {
        line[cursor.x] = To_Upper(letter, false);
    }
}

Change_Selection_Case :: (to_upper: bool) {
    Init_Cursor_Proc_Or_Return(true);
    selection_begin, selection_end := Cursor_Selection(cursor);
    first_line_x_begin := selection_begin.x;
    last_line_x_end := max(selection_end.x - 1, sdw(0));

    Loop_Impl :: ($CONVERSION_LINE: string) #expand {
        x_begin := first_line_x_begin;
        for selection_begin.y..selection_end.y {
            line := Line_View(text_buffer, it);
            if line.count == 0 then continue;
            x_end := ifx it == selection_end.y then last_line_x_end else sdw(line.count-1);
            for x_begin..x_end {
                #insert CONVERSION_LINE;
            }
            x_begin = sdw(0);
        }
    }

    if to_upper 
        then Loop_Impl("line[it] = To_Upper(line[it]);");
        else Loop_Impl("line[it] = To_Lower(line[it]);");

    cursor.x = selection_begin.x;
    cursor.y = selection_begin.y;
    Enter_Normal_Mode();
}
Make_Selection_Uppercase :: #bake_arguments Change_Selection_Case(to_upper=true);
Make_Selection_Lowercase :: #bake_arguments Change_Selection_Case(to_upper=false);


// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Repeat_Last_Change :: () {
    Inject_Modified_Utf32_Into_Frame_Input(last_change_input);
}

Undo_Redo_Loop_Iteration :: (text_buffer: *TextBuffer, cursor: *Cursor, line_change: *LineChange, remove_flag: LineChangeFlags, insert_flag: LineChangeFlags, restore_tack: *BinTack, set_redo_tack: bool) {
    if set_redo_tack && line_change.redo_tack.bin_id.index == -1 && cursor.y < text_buffer.lines.count {
        changed_line := Get_Current_Utf8_For_Line(text_buffer, cursor.y);
        if changed_line.count > 0 {
            line_change.redo_tack.bin_id = Request_Bin(*undo_redo_text, changed_line.count);
            Set_Bin_Data(*undo_redo_text, *line_change.redo_tack.bin_id, As_Array(changed_line, u8));
            line_change.redo_tack.count = changed_line.count;
        }
    }

    if line_change.flags & remove_flag {
        assert(cursor.y < text_buffer.lines.count);
        Remove_Line(text_buffer, cursor.y, false);
        return;
    } else if line_change.flags & insert_flag {
        Insert_Line(text_buffer, cursor.y, false);
        assert(cursor.y < text_buffer.lines.count);
    } 

    restore_text: string;
    if restore_tack.bin_id.index != -1 {
        bin := Get_Bin(*undo_redo_text, restore_tack.bin_id);
        restore_text = As_String(bin);
        restore_text.count = restore_tack.count;
    }

    Clear_Line_Impl(text_buffer, cursor.y);
    utf32 := As_Array(Encode(restore_text, .UTF8, .UTF32), u32);
    Insert_Code_Points(text_buffer, cursor.y, 0, utf32, false);
    cursor.y = min(cursor.y+1, sdw(text_buffer.lines.count));
}

Set_Cursor_Position_After_Undo_Redo :: (cursor: *Cursor, buffer: *TextBuffer, change: *TextChange) {
    cursor.y = min(change.cursor_position.y, sdw(buffer.lines.count-1));
    line := Line_View(buffer, cursor.y);
    cursor.x = Clamp_X_To_Line(change.cursor_position.x, line);
}

Undo :: () {
    Init_Cursor_Proc_Or_Return(true);

    if text_buffer.change_history.count < 2 {
        // nothing to undo. when history count == 2, we have one undoable item and one current, uncommitted change (probably empty)
        return;
    }

    _ := Pop_Middle(*text_buffer.change_history); // ignore current change
    last_change := Peek_Middle(*text_buffer.change_history);
    last_change.need_overwrite = true;

    cursor.x = last_change.cursor_position.x;
    cursor.y = last_change.cursor_position.y;

    for *last_change.lines {
        Undo_Redo_Loop_Iteration(text_buffer, cursor, it, .INSERT_LINE, .DELETE_LINE, *it.undo_tack, true);
    }

    Set_Cursor_Position_After_Undo_Redo(cursor, text_buffer, last_change);
}

Redo :: () {
    Init_Cursor_Proc_Or_Return(true);
    
    if text_buffer.change_history.middle == text_buffer.change_history.end {
        // nothing to redo; at the end of changes
        return;
    }

    redo_change := Peek_Middle(*text_buffer.change_history);
    Push_Middle(*text_buffer.change_history);

    cursor.x = redo_change.cursor_position.x;
    cursor.y = redo_change.cursor_position.y;

    for *redo_change.lines {
        Undo_Redo_Loop_Iteration(text_buffer, cursor, it, .DELETE_LINE, .INSERT_LINE, *it.redo_tack, false);
    }

    Set_Cursor_Position_After_Undo_Redo(cursor, text_buffer, redo_change);
}

Internal_Move_Cursor_To_Position :: () {
    Init_Cursor_Proc_Or_Return(true);
    // cursor.x = move_cursor_to_position.x;
    // cursor.y = move_cursor_to_position.y;
}

Play_Input_Record :: () {
    play_input_record = true;
}

Enter_Search_Mode :: () {
    Init_Cursor_Proc_Or_Return();

    if Active_View_Layer().type == {
    case .FILE_EDITOR;
        vi_mode = .COMMAND;
        background_view_id = active_view_id;
        active_view_id = vim_console_id;
        array_reset_keeping_memory(*auxiliary_input_buffer);
        Active_View_Layer().vim_console.mode = .SEARCH;
    case;
    }
}

Yank_Line :: () {
    Init_Cursor_Proc_Or_Return(true);
    Set_Selected_Register_Text_To_Current_Line(text_buffer, cursor);
}

Set_Selected_Register_Text_To_Current_Line :: inline (text_buffer: *TextBuffer, cursor: *Cursor) {
    line := Line_View(text_buffer, cursor.y);
    line = Paste_Arrays(u32.[#char "\n"], line);
    Set_Register_Text(selected_register, line);
}

Paste :: (after: bool) {
    Init_Cursor_Proc_Or_Return(true);
    register_lines, start_with_newline := Get_Register_Lines(selected_register);
    paste_x := cursor.x;
    prev_count, line_added_count: s64;
    for register_lines {
        first_line := it_index == 0;
        if it_index == 0 {
            if start_with_newline {
                if after {
                    cursor.y += 1;
                }
                Insert_Line(text_buffer, cursor.y);
                paste_x = 0;
            }
        } else {
            Break_Line_At(text_buffer, cursor.y, paste_x);
            paste_x = 0;
        }
        prev_count = Line_Count(text_buffer, cursor.y);
        Insert_Code_Points(text_buffer, cursor.y, paste_x, it);
        new_count := Line_Count(text_buffer, cursor.y);
        line_added_count = new_count - prev_count;
        paste_x += xx line_added_count;
    }
}
Paste_After :: #bake_arguments Paste(after=true);
Paste_Before :: #bake_arguments Paste(after=false);

    
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Get_Register_Lines :: (register: u32) -> (lines: [][]u32, first_line_is_new_line: bool) {
    register_text := Get_Register_Text(selected_register);
    lines: [..][]u32;
    lines.allocator = temp;
    first_line_newline: bool;
    if register_text.count > 0 {
        cur_line := array_add(*lines);
        cur_line.data = register_text.data;
        for register_text {
            if it == #char "\n" {
                if it_index == 0 {
                    first_line_newline = true;
                    cur_line.data += 1;
                } else {
                    cur_line.count = (register_text.data + it_index) - cur_line.data;
                    cur_line = array_add(*lines);
                    cur_line.data = (register_text.data + it_index) + 1;
                }
            }
        }
        cur_line.count = (register_text.data + register_text.count) - cur_line.data;
    }
    return lines, first_line_newline;
}

Init_Cursor_Proc_Or_Return :: ($RESET_BLINK := false, $NEED_TEXT_BUFFER := true) #expand {
    `active_layer := Active_View_Layer();
    `cursor := Layer_Cursor(`active_layer);
    if `cursor == null then `return;
    #if NEED_TEXT_BUFFER {
        `text_buffer := Layer_Text_Buffer(`active_layer);
        if `text_buffer == null then `return;
    }
    #if RESET_BLINK {
        `cursor.reset_blink = true;
    }
}

Init_Cursor_Proc_Or_Return_Value :: (value: $T, $RESET_BLINK := false) -> T #expand {
    `active_layer := Active_View_Layer();
    `cursor := Layer_Cursor(`active_layer);
    if `cursor == null then `return value;
    `text_buffer := Layer_Text_Buffer(`active_layer);
    if `text_buffer == null then `return value;
    #if RESET_BLINK {
        `cursor.reset_blink = true;
    }
}

Clamp_X_To_Line :: (x: s32, line: []u32, $TAB_EXPANSION_SKIP: TabExpansionSkip = .BACKWARD) -> s32 {
    Scroll_Through_Tab_Expansion_Forward :: () #expand {
        while `x < `end_x && `line[`x] == TAB_EXPANDED_SPACE {
            `x += 1;
        }
    }
    Scroll_Through_Tab_Expansion_Backward :: () #expand {
        if `x == line.count then return;
        while `x > 0 && `line[`x] == TAB_EXPANDED_SPACE {
            `x -= 1;
        }
    }
    if line.count == 0 {
        x = 0;
    } else {
        end_x := ifx vi_mode == .INSERT then sdw(line.count) else sdw(line.count - 1);
        x = clamp(x, 0, end_x);
        #if TAB_EXPANSION_SKIP == .FORWARD {
            save_x := x;
            Scroll_Through_Tab_Expansion_Forward();
            if vi_mode != .INSERT && line[x] == TAB_EXPANDED_SPACE {
                x = save_x;
                Scroll_Through_Tab_Expansion_Backward();
            }
        } else #if TAB_EXPANSION_SKIP == .BACKWARD {
            Scroll_Through_Tab_Expansion_Backward();
        }
    }
    return x;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Action_Executor :: #type ();

TabExpansionSkip :: enum {
    NONE;
    FORWARD;
    BACKWARD;
}

TextBlobType :: enum {
    KEYWORD;
    NON_KEYWORD;
    WHITESPACE;
}

last_action_executor: Action_Executor;
last_executor_repeat_ct: s64;

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

Get_Marked_Utf32_Blob_Type :: inline (marked_utf32: u32) -> TextBlobType {
    if Is_Alphanumeric_Or_Underscore(marked_utf32) {
        return .KEYWORD;
    } else if Is_Whitespace(marked_utf32) {
        return .WHITESPACE;
    } else {
        return .NON_KEYWORD;
    }
}

Word_Scroll_Forward_Maybe_Go_To_Next_Line :: (force_exit := false, allow_newline := true) #expand {
    if `cursor.y == `text_buffer.lines.count - 1 || force_exit {
        `cursor.x = Clamp_X_To_Line(`cursor.x, `line);
        break;
    } else if allow_newline {
        `cursor.x = 0;
        `cursor.target_x = 0;
        Cursor_Scroll_Down();
        `reference_blob = .WHITESPACE;
        `line = Line_View(`text_buffer, `cursor.y);
        if `line.count == 0 then break;
    }
}