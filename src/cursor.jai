
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

CursorStyle :: enum u8 {
    BLOCK;
    VERTICAL_LINE;
}

CursorMoveHistory :: struct {
    timestamps: [TIMESTAMP_COUNT]float64;
    actions: [TIMESTAMP_COUNT]Action;
    current_index: u8;
    TIMESTAMP_COUNT :: 8;
}

Cursor :: struct {
    x: s32;
    y: s32;
    // in vim, when the cursor scrolls vertically it has a target x it tries to go to that is set by moving the cursor horizontally
    target_x: s32; 
    blink_timer: float32;
    scroll_timer: float32;
    begin_selection: IntVector2 = .{-1, -1};
    move_history: CursorMoveHistory;
    active_scroll_action := Action.NONE;
    style: CursorStyle;
    reset_blink: bool;
    just_moved: bool;
}

TextSelection :: struct {
    begin: IntVector2;
    end: IntVector2;
    cursor_at_end: bool;
}

Cursor_Selection :: (cursor: *Cursor) -> (begin: IntVector2, end: IntVector2) {
    begin, end: IntVector2 = ---;
    cursor_at_end := cursor.y > cursor.begin_selection.y || (cursor.y == cursor.begin_selection.y && cursor.x >= cursor.begin_selection.x);
    if cursor_at_end {
        begin.x = cursor.begin_selection.x;
        begin.y = cursor.begin_selection.y;
        end.x = cursor.x + 1;
        end.y = cursor.y;
    } else {
        begin.x = cursor.x;
        begin.y = cursor.y;
        end.x = cursor.begin_selection.x + 1;
        end.y = cursor.begin_selection.y;
    }
    return begin, end;
}

Add_Cursor_Move_Artifact :: (cursor: *Cursor, action: Action) {
    using cursor.move_history;
    timestamps[current_index] = seconds_since_init();
    actions[current_index] = action;
    current_index = Increment_Wrap(current_index, 0, CursorMoveHistory.TIMESTAMP_COUNT-1);
}

MAX_KEY_REPEAT_TIME :: 0.09;

Get_Action_Repeat_Rate :: (cursor: *Cursor, action: Action) -> bool, float32 {
    using cursor.move_history;
    t := seconds_since_init();
    i := current_index;
    dt_sum := 0.0;
    repeat_ct := 0;
    for iter_ct : 0..CursorMoveHistory.TIMESTAMP_COUNT-1 {
        i = ifx i == 0 then CursorMoveHistory.TIMESTAMP_COUNT-1 else i - 1;
        repeat_window := MAX_KEY_REPEAT_TIME * cast(float)iter_ct;
        if actions[i] != action {
            break;
        }
        time_delta := cast(float32)(t - timestamps[i]);
        if time_delta > MAX_KEY_REPEAT_TIME {
            break;
        }
        t = timestamps[i];
        if iter_ct > 0 {
            dt_sum += time_delta;
        }
        repeat_ct += 1;
    }
    is_repeat := repeat_ct >= 2;
    return is_repeat, cast(float)(repeat_ct-1) / dt_sum;
}