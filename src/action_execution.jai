
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
    cursor.x = Clamp_X_To_Line(cursor.target_x, line, .BACKWARD);
}

Cursor_Scroll_Up :: () {
    Init_Cursor_Proc_Or_Return();
    cursor.y = max(cursor.y-1, sdw(0));
    line := Line_View(text_buffer, cursor.y);
    cursor.x = Clamp_X_To_Line(cursor.target_x, line, .BACKWARD);
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
    cursor.x = Clamp_X_To_Line(cursor.x, line, .BACKWARD);
    cursor.target_x = cursor.x;
}

Cursor_Scroll_To_Top :: () {
    Init_Cursor_Proc_Or_Return();
    cursor.y = 0;
    line := Line_View(text_buffer, cursor.y);
    cursor.x = Clamp_X_To_Line(cursor.target_x, line, .BACKWARD);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Init_Cursor_Proc_Or_Return :: () #expand {
    `active_layer := Active_View_Layer();
    `cursor := Layer_Cursor(`active_layer);
    if `cursor == null then `return;
    `text_buffer := Layer_Text_Buffer(`active_layer);
    if `text_buffer == null then `return;
    `cursor.reset_blink = true;
}

Clamp_X_To_Line :: (x: s32, line: []u32, $TAB_EXPANSION_SKIP: TabExpansionSkip) -> s32 {
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
        end_x := ifx vim_mode == .INSERT then sdw(line.count) else sdw(line.count - 1);
        x = min(x, end_x);
        #if TAB_EXPANSION_SKIP == .FORWARD {
            save_x := x;
            Scroll_Through_Tab_Expansion_Forward();
            if line[x] == TAB_EXPANDED_SPACE {
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

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

