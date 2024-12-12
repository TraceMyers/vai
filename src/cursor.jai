
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
    style: CursorStyle;
    reset_blink: bool;
    move_history: CursorMoveHistory;
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