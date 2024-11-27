Get_Render_Dimensions :: (window: *Window) -> (width: s32, height: s32) {
    c: RECT;
    success := GetClientRect(window.handle, *c);
    if !success then return 0, 0;
    return cast(s32)(c.right - c.left), cast(s32)(c.bottom - c.top);   
}

Resize_Render_Target :: (window: *Window) {
    glViewport(0, 0, xx window.width, xx window.height);
}

#import "GL";