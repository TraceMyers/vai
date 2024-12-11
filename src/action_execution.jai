
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
    Insert_Line(text_buffer, cursor.y);
    cursor.y += 1;
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
    vi_mode = .NORMAL;
    Cursor_Scroll_Left();
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