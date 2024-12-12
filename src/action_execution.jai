
Action_Execution :: struct {

    Initialize :: () {
        // view_layer_action_execution_vtable[Action.SCROLL_DOWN] = Cursor_Scroll_Down;
    }

    Shutdown :: () {

    }
}

Cursor_Scroll_Down :: () {
    Init_Cursor_Proc_Or_Return();
    cursor.y = min(cursor.y+1, sdw(max(text_buffer.lines.count-1, 0)));
    line := Line_View(text_buffer, cursor.y);
    cursor.x = Clamp_X_To_Line(cursor.target_x, line);
}

Cursor_Scroll_Up :: () {
    Init_Cursor_Proc_Or_Return();
    cursor.y = max(cursor.y-1, sdw(0));
    line := Line_View(text_buffer, cursor.y);
    cursor.x = Clamp_X_To_Line(cursor.target_x, line);
}

Cursor_Scroll_Right :: () {
    Init_Cursor_Proc_Or_Return();
    line := Line_View(text_buffer, cursor.y);
    cursor.x += 1;
    cursor.x = Clamp_X_To_Line(cursor.x, line, .FORWARD);
    cursor.target_x = cursor.x;
}

Cursor_Scroll_Left :: () {
    Init_Cursor_Proc_Or_Return();
    line := Line_View(text_buffer, cursor.y);
    cursor.x -= 1;
    cursor.x = Clamp_X_To_Line(cursor.x, line);
    cursor.target_x = cursor.x;
}

Cursor_Scroll_To_Top :: () {
    Init_Cursor_Proc_Or_Return();
    cursor.y = 0;
    line := Line_View(text_buffer, cursor.y);
    cursor.x = Clamp_X_To_Line(cursor.target_x, line);
}

Cursor_Scroll_To_Bottom :: () {
    Init_Cursor_Proc_Or_Return();
    cursor.y = xx (text_buffer.lines.count-1);
    line := Line_View(text_buffer, cursor.y);
    cursor.x = Clamp_X_To_Line(cursor.target_x, line);
}

Cursor_Scroll_To_Line_End :: () {
    Init_Cursor_Proc_Or_Return();
    line := Line_View(text_buffer, cursor.y);
    cursor.x = max(sdw(ifx vi_mode == .INSERT then line.count else line.count-1), 0);
    cursor.x = Clamp_X_To_Line(cursor.x, line);
    cursor.target_x = cursor.x;
}

Cursor_Scroll_To_Line_Begin :: () {
    Init_Cursor_Proc_Or_Return();
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
    Init_Cursor_Proc_Or_Return();
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
    Init_Cursor_Proc_Or_Return();
    // Insert_Line(text_buffer, cursor.y);
    Break_Line_At(text_buffer, cursor.y, cursor.x);
    cursor.y += 1;
    cursor.x = 0;
}

Enter_Insert_Mode :: (append: bool) {
    Init_Cursor_Proc_Or_Return();
    vi_mode = .INSERT;
    if append {
        Cursor_Scroll_Right();
    }
}
Enter_Insert_Mode_Prepend   :: #bake_arguments Enter_Insert_Mode(append=false);
Enter_Insert_Mode_Append    :: #bake_arguments Enter_Insert_Mode(append=true);

Enter_Normal_Mode :: () {
    Init_Cursor_Proc_Or_Return();
    if vi_mode == {
    case .INSERT;
        Cursor_Scroll_Left();
    case .VISUAL;
    }
    cursor.begin_selection = IntVector2.{-1,-1};
    vi_mode = .NORMAL;
}

Backspace :: () {
    Init_Cursor_Proc_Or_Return();
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
        Insert_Code_Points(text_buffer, cursor.y, cursor.x, src_line);
        Remove_Line(text_buffer, cursor.y+1);
    }
}

Delete_Character :: () {
    Init_Cursor_Proc_Or_Return();
    line_count := Line_Count(text_buffer, cursor.y);
    if line_count > 0 {
        Remove_Code_Point(text_buffer, cursor.y, cursor.x);
        line := Line_View(text_buffer, cursor.y);
        cursor.x = Clamp_X_To_Line(cursor.x, line);
        cursor.target_x = cursor.x;
    }
}

Insert_Line_And_Enter_Insert_Mode :: (append: bool) {
    Init_Cursor_Proc_Or_Return();
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
    Init_Cursor_Proc_Or_Return();
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
    Init_Cursor_Proc_Or_Return();
    line := Line_View(text_buffer, cursor.y);

    TextBlobType :: enum {
        KEYWORD;
        NON_KEYWORD;
        WHITESPACE;
    }

    reference_blob: TextBlobType = ---;
    use_x := ifx forward then cursor.x else cursor.x - 1;
    if cursor.x >= line.count {
        reference_blob = .WHITESPACE;
    } else if !forward && cursor.x == 0 {
        reference_blob = .WHITESPACE;
    } else if Is_Alphanumeric_Or_Underscore(line[use_x]) {
        reference_blob = .KEYWORD;
    } else if Is_Whitespace(line[use_x]) {
        reference_blob = .WHITESPACE;
    } else {
        reference_blob = .NON_KEYWORD;
    }

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
                if cursor.y == text_buffer.lines.count - 1 {
                    cursor.x = Clamp_X_To_Line(cursor.x, line);
                    break;
                } else {
                    cursor.x = 0;
                    cursor.target_x = 0;
                    Cursor_Scroll_Down();
                    reference_blob = .WHITESPACE;
                    line = Line_View(text_buffer, cursor.y);
                    if line.count == 0 then break;
                }
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

Delete_Word :: (inside: bool, small: bool) {
    Init_Cursor_Proc_Or_Return();
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
    Word_Scroll(true, small);
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
Delete_Word_Small :: #bake_arguments Delete_Word(inside=false, small=true);
Delete_Word_Inside_Small :: #bake_arguments Delete_Word(inside=true, small=true);

Delete_Selection :: () {
    Init_Cursor_Proc_Or_Return();

    selection_begin, selection_end := Cursor_Selection(cursor);
    do_concatenate := selection_end.y != selection_begin.y;
    edit_y_offset: s32 = 1;

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

        line_count: s32 = xx Line_Count(text_buffer, edit_y);
        if it == selection_end.y {
            end_x = selection_end.x;
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
    cursor.y = selection_begin.y;
    cursor.x = Clamp_X_To_Line(selection_begin.x, Line_View(text_buffer, cursor.y));
    cursor.target_x = cursor.x;

    // if this is a multi-line delete and the first and last line both
    if do_concatenate {
        Enter_Insert_Mode(false);
        Cursor_Scroll_Down();
        Cursor_Scroll_To_Line_Zero();
        Backspace();
    }

    Enter_Normal_Mode();
}

Enter_Visual_Mode :: () {
    Init_Cursor_Proc_Or_Return();
    vi_mode = .VISUAL;
    cursor.begin_selection = .{cursor.x, cursor.y};
}

Repeat_Last_Change :: () {
    if last_action_executor && last_action_executor != #this {
        last_action_executor();
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Init_Cursor_Proc_Or_Return :: ($RESET_BLINK := true) #expand {
    `active_layer := Active_View_Layer();
    `cursor := Layer_Cursor(`active_layer);
    if `cursor == null then `return;
    `text_buffer := Layer_Text_Buffer(`active_layer);
    if `text_buffer == null then `return;
    #if RESET_BLINK {
        `cursor.reset_blink = true;
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Action_Executor :: #type ();

TabExpansionSkip :: enum {
    NONE;
    FORWARD;
    BACKWARD;
}

last_action_executor: Action_Executor;

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

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