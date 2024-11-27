
window: Window;

WindowInfo :: struct {
    width: s32;
    height: s32;
    x: s32;
    y: s32;
}

Window :: struct {
    handle: WindowType;
    using info: *WindowInfo;
    MIN_WIDTH :: 256;
    MIN_HEIGHT :: 256;
}

Query_Window_Dimensions :: inline () -> (s32, s32) {
    w, h := Query_Window_Dimensions(window.handle);
    return w, h;
}

Update_Window_Dimensions :: () {
    new_width, new_height := Query_Window_Dimensions();
    // window.resized = new_width != window.width || new_height != window.height;
    window.width = new_width;
    window.height = new_height;
}

Window_Dimensions :: ($T1: Type) -> T1, T1
#modify {
    t := (cast(*Type_Info)T1).type;
    return t == .INTEGER || t == .FLOAT;
} {
    return cast(T1) window.width, cast(T1) window.height;
}

// Window_Just_Resized :: inline () -> bool {
//     return window.resized;
// }

#if OS == .WINDOWS {
    #load "win32_window.jai";
}
