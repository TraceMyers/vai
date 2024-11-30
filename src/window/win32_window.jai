
WindowType :: HWND;

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Create_Window :: (window_name: string, msaa := DEFAULT_MSAA) -> WindowType {

    if !window_class_created && !Create_Window_Class() then return null;

    SPI_GETWORKAREA :: 0x30;
    // can use this function to query or change a bunch of stuff in Windows. we're using this to get the area on screen
    // not obscured by the taskbar, if the default window position was passed in.
    // http://www.jasinskionline.com/windowsapi/ref/s/systemparametersinfo.html
    SystemParametersInfoW :: (uiAction: u32, uiParam: u32, pvParam: *void, fWinIni: u32) -> BOOL #foreign user32;

    if window.x == -1 || window.y == -1 {
        work_area: RECT;
        work_area_get_success := SystemParametersInfoW(SPI_GETWORKAREA, 0, *work_area, 0); 
        if work_area_get_success {
            window.x = work_area.left;
            window.y = work_area.left;
        }
    }

    // apparently (?) window size in terms of pixels is kind of virtual; this converts our virtual (intended)
    // size to the true size, according to Windows
    window_rect: RECT;
    window_rect.right = window.width;
    window_rect.bottom = window.height;
    AdjustWindowRect(*window_rect, WINDOWED_STYLE, .FALSE);

    true_width := window_rect.right - window_rect.left;
    true_height := window_rect.bottom - window_rect.top;

    window.handle = CreateWindowExW(
        0, // extended window style
        xx Encode_Temp_C_String(WINDOW_CLASS, .UTF8, .UTF16),
        xx Encode_Temp_C_String(window_name, .UTF8, .UTF16),
        WINDOWED_STYLE,
        xx window.x,
        xx window.y,
        xx true_width,
        xx true_height,
        null,
        null,
        cast(HINSTANCE) 0,
        null
    );

    if window.handle == null {
        Log_Error("CreateWindowExW returned 0");
        return null;
    }

    UpdateWindow(window.handle);
    ShowWindow(window.handle, SW_SHOW);

    return window.handle;
}

Query_Window_Dimensions :: (window_handle: HWND) -> s32, s32 {
    window_rect: RECT;
    // 'client' rect is the drawable surface of the window (not including top bar and etc)
    GetClientRect(window_handle, *window_rect);
    x := window_rect.right - window_rect.left;
    y := window_rect.bottom - window_rect.top;
    return x, y;
}

Update_Window_Events :: () {
    while true {
        msg: MSG;
        result := PeekMessageW(*msg, null, 0, 0, PM_REMOVE);
        if !result then break;
        TranslateMessage(*msg);
        DispatchMessageW(*msg);
    }
}
    
Receive_Window_Message :: (hwnd: HWND, message: u32, wParam: WPARAM, lParam: LPARAM) -> s64 #c_call {
    new_context: Context;
    push_context new_context {
        if message == {
        case WM_SYSCOMMAND;
            return DefWindowProcW(hwnd, message, wParam, lParam);
        case WM_SYSKEYDOWN; #through;
        case WM_KEYDOWN;
        case WM_SYSKEYUP;   #through;
        case WM_KEYUP;
        // case WM_PAINT;
            // paint_struct: PAINTSTRUCT;
            // hdc := BeginPaint(hwnd, *paint_struct);
            // FillRect(hdc, *paint_struct.rcPaint, xx (COLOR_WINDOW + 1));
            // EndPaint(hwnd, *paint_struct);
            // Log("paint please");
            // return 0;
        case WM_SIZE;
            return 0;
        case WM_MOVE;
            return 0;
        case WM_CLOSE;      #through;
        case WM_QUIT;
            quit = true;
            return DefWindowProcW(hwnd, message, wParam, lParam);
        case;
            return DefWindowProcW(hwnd, message, wParam, lParam);
        }
    }
    return 0;
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

Create_Window_Class :: (bg_color := float.[0.0, 0.0, 0.0]) -> bool {
    assert(!window_class_created);

    this_program := GetModuleHandleW(null);

    // I guess icons are typically stored at byte offset 2 from the program...? dunno what else this could be
    icon := LoadIconW(this_program, cast(*u16)2);

    if icon == null {
        program_path: [MAX_PATH]u16;
        GetModuleFileNameW(null, program_path.data, MAX_PATH);
        icon = ExtractIconW(this_program, program_path.data, 0); // 0 = first icon
    }

    // converting normalized color to bytes for BGR color
    r := Clamp_Cast(bg_color[0], u8, true);
    g := Clamp_Cast(bg_color[1], u8, true);
    b := Clamp_Cast(bg_color[2], u8, true);

    // "A solid brush is a bitmap that the system uses to paint the interiors of filled shapes." -Bill Gates
    brush := CreateSolidBrush((udw(r) << 16) | (udw(g) << 8) | udw(r));

    window_class: WNDCLASSEXW;
    window_class.cbSize = size_of(WNDCLASSEXW);
    window_class.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC; // https://learn.microsoft.com/en-us/windows/win32/winmsg/window-class-styles
    window_class.lpfnWndProc = xx Receive_Window_Message; // the callback function where windows will send us data such as keyboard inputs, resizes, and many more things, and we will tell windows how the window should respond.
    window_class.cbClsExtra = 0; // extra bytes to allocate at the end of the class. 
    window_class.cbWndExtra = 0; // extra bytes to allocate at the end of an instance.
    window_class.hInstance = this_program;
    window_class.hIcon = icon;
    window_class.hCursor = LoadCursorW(null, IDC_ARROW);
    window_class.hbrBackground = brush;
    window_class.lpszMenuName = null;
    window_class.lpszClassName = xx Encode_Temp_C_String(WINDOW_CLASS, .UTF8, .UTF16);

    if RegisterClassExW(*window_class) == 0 {
        Log_Error("RegisterClassExW returned null");
        return false;
    }

    window_class_created = true;
    return true;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

WINDOW_CLASS :: "Window Class";
WINDOWED_STYLE : u32 : WS_OVERLAPPEDWINDOW;
SECONDARY_WINDOW_STYLE : u32 : WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME;
DEFAULT_MSAA : s32 : 1;
COLOR_WINDOW : u32 : 5;

user32 :: #system_library "user32";

BeginPaint :: (in: HWND, lpPaint: *PAINTSTRUCT) -> HDC #foreign user32;
EndPaint :: (hwnd: HWND, lpPaint: *PAINTSTRUCT) -> BOOL #foreign user32;
FillRect :: (hdc: HDC, lprc: *RECT, hbr: HBRUSH) -> s32 #foreign user32;

PAINTSTRUCT :: struct {
    hdc: HDC;
    fErase: BOOL;
    rcPaint: RECT;
    fRestore: BOOL;
    fIncUpdate: BOOL;
    rgbReserved: [32]u8;
}

window_class_created := false;