
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
    cursor.x = max(sdw(line.count-1), 0);
    cursor.x = Clamp_X_To_Line(cursor.x, line);
    cursor.target_x = cursor.x;
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
        // append current line to end of line above, delete current line, put cursor at end of where the append happened
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