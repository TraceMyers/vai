
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
    // The rendered column to retain while moving through soft-wrapped rows.
    soft_wrap_target_x: s32 = -1;
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

Cursor_Latest_Move_Action :: (cursor: *Cursor) -> Action {
    using cursor.move_history;
    latest_index := ifx current_index == 0 then CursorMoveHistory.TIMESTAMP_COUNT-1 else current_index-1;
    return actions[latest_index];
}

Cursor_Latest_Move_Was_Repeated :: (cursor: *Cursor, action: Action) -> bool {
    using cursor.move_history;
    REPEAT_PRESS_MAX_INTERVAL :: 1.5;
    latest_index := ifx current_index == 0 then CursorMoveHistory.TIMESTAMP_COUNT-1 else current_index-1;
    previous_index := ifx latest_index == 0 then CursorMoveHistory.TIMESTAMP_COUNT-1 else latest_index-1;
    repeat_interval := timestamps[latest_index] - timestamps[previous_index];
    return actions[latest_index] == action
        && actions[previous_index] == action
        && timestamps[previous_index] > 0
        && repeat_interval >= 0
        && repeat_interval <= REPEAT_PRESS_MAX_INTERVAL;
}

Cursor_Scroll_Repeat_Rate :: (cursor: *Cursor, action: Action, fallback_rate: float32) -> float32 {
    using cursor.move_history;
    MIN_VALID_REPEAT_INTERVAL :: 1.0 / 240.0;
    MAX_VALID_REPEAT_INTERVAL :: 0.5;

    valid_intervals: [CursorMoveHistory.TIMESTAMP_COUNT-1]float64;
    valid_interval_count: s32;
    newer_index := ifx current_index == 0 then CursorMoveHistory.TIMESTAMP_COUNT-1 else current_index-1;
    if actions[newer_index] != action {
        return fallback_rate;
    }

    for 1..CursorMoveHistory.TIMESTAMP_COUNT-1 {
        older_index := ifx newer_index == 0 then CursorMoveHistory.TIMESTAMP_COUNT-1 else newer_index-1;
        if actions[older_index] != action || timestamps[older_index] <= 0 {
            break;
        }
        interval := timestamps[newer_index] - timestamps[older_index];
        if interval >= MIN_VALID_REPEAT_INTERVAL && interval <= MAX_VALID_REPEAT_INTERVAL {
            insert_index := valid_interval_count;
            while insert_index > 0 && valid_intervals[insert_index-1] > interval {
                valid_intervals[insert_index] = valid_intervals[insert_index-1];
                insert_index -= 1;
            }
            valid_intervals[insert_index] = interval;
            valid_interval_count += 1;
        }
        newer_index = older_index;
    }

    // The first repeat includes the OS repeat delay, and Win32 can later
    // deliver several queued repeats almost together. Wait for enough samples
    // to distinguish both outliers, then use the median cadence.
    if valid_interval_count < 3 {
        return fallback_rate;
    }
    middle_index := valid_interval_count / 2;
    median_interval := valid_intervals[middle_index];
    if valid_interval_count % 2 == 0 {
        median_interval = (median_interval + valid_intervals[middle_index-1]) * 0.5;
    }
    return clamp(cast(float32)(1.0 / median_interval), 1.0, 120.0);
}
