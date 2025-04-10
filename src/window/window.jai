
window: Window;

WindowInfo :: struct {
    width: s32;
    height: s32;
    x: s32;
    y: s32;
    clear_color: fRGB;
}

Window :: struct {
    handle: WindowType;
    using info: *WindowInfo;
    just_resized: bool;
    MIN_WIDTH :: 256;
    MIN_HEIGHT :: 256;
}

Query_Window_Dimensions :: inline () -> (s32, s32) {
    w, h := Query_Window_Dimensions(window.handle);
    return w, h;
}

Update_Window_Dimensions :: () -> resized: bool {
    new_width, new_height := Query_Window_Dimensions();
    window.just_resized = new_width != window.width || new_height != window.height;
    window.width = new_width;
    window.height = new_height;
    updated_once_prev := updated_once;
    updated_once = true;
    return window.just_resized | !updated_once_prev;
}

Window_Dimensions :: ($T1: Type) -> T1, T1
#modify {
    t := (cast(*Type_Info)T1).type;
    return t == .INTEGER || t == .FLOAT;
} {
    return cast(T1) window.width, cast(T1) window.height;
}

#if OS == .WINDOWS {
    #load "win32_window.jai";
}


#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

updated_once: bool;