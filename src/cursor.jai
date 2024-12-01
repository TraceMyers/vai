
CursorActionHistory :: struct {
    timestamps: [ARTIFACT_COUNT]float64;
    actions: [ARTIFACT_COUNT]Action;
    index: u8;
    ARTIFACT_COUNT :: 8;
}

Cursor :: struct {
    x: s32;
    y: s32;
    // in vim, when the cursor scrolls vertically it has a target x it tries to go to that is set by moving the cursor horizontally
    target_x: s32; 
    blink_timer: float32;
    scroll_timer: float32;
    history: CursorActionHistory;
}