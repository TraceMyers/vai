
WindowType :: HWND;
VirtualKey :: enum u8 {
    UP :: VK_UP;
    DOWN :: VK_DOWN;
    LEFT :: VK_LEFT;
    RIGHT :: VK_RIGHT;
    H :: #char "H";
    J :: #char "J";
    K :: #char "K";
    L :: #char "L";
}


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
            window.y = work_area.top;
        }
    }

    window.handle = CreateWindowExW(
        WS_EX_APPWINDOW,
        xx Encode_Temp_C_String(WINDOW_CLASS, .UTF8, .UTF16),
        xx Encode_Temp_C_String(window_name, .UTF8, .UTF16),
        WINDOWED_STYLE,
        xx window.x,
        xx window.y,
        xx window.width,
        xx window.height,
        null,
        null,
        cast(HINSTANCE) 0,
        null
    );

    if window.handle == null {
        Log_Error("CreateWindowExW returned 0");
        return null;
    }

    corner_preference: s32 = DWMWCP_DONOTROUND;
    DwmSetWindowAttribute(
        window.handle,
        DWMWA_WINDOW_CORNER_PREFERENCE,
        *corner_preference,
        size_of(s32),
    );

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
    Update_Modifier_Keys();
    while true {
        msg: MSG;
        result := PeekMessageW(*msg, null, 0, 0, PM_REMOVE);
        if !result then break;
        TranslateMessage(*msg);
        DispatchMessageW(*msg);
    }
}

Platform_Window_Dpi :: () -> u32 {
    if window.handle == null {
        return 96;
    }
    dpi := GetDpiForWindow(window.handle);
    return ifx dpi > 0 then dpi else 96;
}

Win32_Resize_Border_Thickness :: (hwnd: HWND) -> s32 {
    dpi := GetDpiForWindow(hwnd);
    if dpi == 0 {
        dpi = 96;
    }
    return max(
        GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi),
        1,
    );
}

Win32_Custom_Frame_Hit_Test :: (
    position: IntVector2,
    client_width: s32,
    client_height: s32,
    title_bar_height: s32,
    button_width: s32,
    resize_border: s32,
    maximized: bool,
) -> s64 {
    if !maximized {
        on_left := position.x >= 0 && position.x < resize_border;
        on_right := position.x < client_width && position.x >= client_width-resize_border;
        on_top := position.y >= 0 && position.y < resize_border;
        on_bottom := position.y < client_height && position.y >= client_height-resize_border;

        if on_top && on_left then return HTTOPLEFT;
        if on_top && on_right then return HTTOPRIGHT;
        if on_bottom && on_left then return HTBOTTOMLEFT;
        if on_bottom && on_right then return HTBOTTOMRIGHT;
        if on_left then return HTLEFT;
        if on_right then return HTRIGHT;
        if on_top then return HTTOP;
        if on_bottom then return HTBOTTOM;
    }

    button := Custom_Title_Bar_Button_At(position, client_width, title_bar_height, button_width);
    if button != .NONE {
        return HTCLIENT;
    }
    if position.y >= 0 && position.y < title_bar_height {
        return HTCAPTION;
    }
    return HTCLIENT;
}

Win32_Custom_Title_Bar_Button_At :: (hwnd: HWND, position: IntVector2) -> CustomTitleBarButton {
    client_rect: RECT;
    GetClientRect(hwnd, *client_rect);
    dpi := GetDpiForWindow(hwnd);
    if dpi == 0 then dpi = 96;
    title_bar_height := Scale_Custom_Title_Bar_Metric(CUSTOM_TITLE_BAR_HEIGHT_96, dpi);
    button_width := Scale_Custom_Title_Bar_Metric(CUSTOM_TITLE_BAR_BUTTON_WIDTH_96, dpi);
    return Custom_Title_Bar_Button_At(position, client_rect.right-client_rect.left, title_bar_height, button_width);
}

Perform_Custom_Title_Bar_Button_Action :: (hwnd: HWND, button: CustomTitleBarButton) {
    if button == {
    case .MINIMIZE;
        ShowWindow(hwnd, SW_MINIMIZE);
    case .MAXIMIZE;
        show_command := ifx IsZoomed(hwnd)
            then cast(s32)SW_RESTORE
            else cast(s32)SW_MAXIMIZE;
        ShowWindow(hwnd, show_command);
    case .CLOSE;
        quit = true;
    case;
    }
}
    
Receive_Window_Message :: (hwnd: HWND, message: u32, wParam: WPARAM, lParam: LPARAM) -> s64 #c_call {

    // defs just for here
    WM_ACTIVATE : u32 : 0x0006;
    MARGINS :: struct {
        cxLeftWidth, cxRightWidth, cyTopHeight, cyBottomHeight: int;
    }
    WM_CANCELMODE :: 0x001f;
    WM_CAPTURECHANGED :: 0x0215;
    WM_KILLFOCUS :: 0x0008;
    WM_MOUSELEAVE :: 0x02a3;
    dwmapi   :: #system_library "Dwmapi";
    DwmExtendFrameIntoClientArea :: (window: HWND, margins: *MARGINS) -> HRESULT #foreign dwmapi;

    push_context {
        if message == {
        case WM_NCCALCSIZE;
            if wParam != 0 && IsZoomed(hwnd) {
                params := cast(*NCCALCSIZE_PARAMS)lParam;
                border := Win32_Resize_Border_Thickness(hwnd);
                params.rgrc[0].left += border;
                params.rgrc[0].top += border;
                params.rgrc[0].right -= border;
                params.rgrc[0].bottom -= border;
            }
            return 0;
        case WM_NCHITTEST;
            screen_position := Mouse_Position_From_LParam(lParam);
            client_position := POINT.{screen_position.x, screen_position.y};
            ScreenToClient(hwnd, *client_position);
            client_rect: RECT;
            GetClientRect(hwnd, *client_rect);
            dpi := GetDpiForWindow(hwnd);
            if dpi == 0 then dpi = 96;
            return Win32_Custom_Frame_Hit_Test(
                .{client_position.x, client_position.y},
                client_rect.right-client_rect.left,
                client_rect.bottom-client_rect.top,
                Scale_Custom_Title_Bar_Metric(CUSTOM_TITLE_BAR_HEIGHT_96, dpi),
                Scale_Custom_Title_Bar_Metric(CUSTOM_TITLE_BAR_BUTTON_WIDTH_96, dpi),
                Win32_Resize_Border_Thickness(hwnd),
                IsZoomed(hwnd) != 0,
            );
        case WM_DPICHANGED;
            suggested_rect := cast(*RECT)lParam;
            SetWindowPos(
                hwnd,
                null,
                suggested_rect.left,
                suggested_rect.top,
                suggested_rect.right-suggested_rect.left,
                suggested_rect.bottom-suggested_rect.top,
                SWP_NOZORDER | SWP_NOACTIVATE,
            );
            Mark_Custom_Title_Bar_UI_Changed();
            return 0;
        case WM_NCMOUSEMOVE;
            Set_Custom_Title_Bar_Hovered_Button(.NONE);
            mouse_hover_position_is_known = false;
        //   case WM_CREATE;
            // push the window that we draw to into the upper left of the Windows window, so we're drawing to the whole window I guess -Trace
            // rect: RECT;
            // GetWindowRect(hwnd, *rect);
            // success := SetWindowPos(hwnd, null, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top, SWP_FRAMECHANGED);
            // if !success {
            //     log("failed to set window pos during window creation");
            // } else {
            //     log("set window pos during window creation");
            // }
        //   case WM_ACTIVATE;
            // when create/maximize. by pushing the margins inward before removing the default microsoft border, we keep its pretty rounded edges -Trace
            // margins: MARGINS;
            // margins.cxLeftWidth = 8;
            // margins.cxRightWidth = 8;
            // margins.cyBottomHeight = 20;
            // margins.cyTopHeight = 27;
            // result := DwmExtendFrameIntoClientArea(hwnd, *margins);
            // if FAILED(result) {
            //     log("failed to extend frame into client area");
            // } else {
            //     log ("extended frame into client area");
            // }
        case WM_SYSKEYDOWN; #through;
        case WM_KEYDOWN;
            if wParam == VK_F9 {
                quit = true;
            } else if !Mouse_Input_Locks_Keyboard() && wParam <= 255 {
                Set_Bit(*key_pressed, xx wParam);
            }
            last_vkey = xx wParam;
            last_vkey_modified_by_control = (modifier_keys & .CONTROL) != 0;
            last_vkey_modified_by_shift = (modifier_keys & .SHIFT) != 0;
            // TODO:... eh something
            if wParam == 191 && last_vkey_modified_by_control { // otherwise ctrl + / doesn't come through text input
                Take_Raw_Input(xx #char "/");
            }
        case WM_SYSKEYUP;
        case WM_KEYUP;
            if wParam <= 255 {
                Unset_Bit(*key_pressed, xx wParam);
            }
        case WM_KILLFOCUS;
            Clear(*key_pressed);
        case WM_SYSCHAR;
              // This is here to prevent beeps when a Alt key combo is pressed. If we don't return 0, windows helpfully emits a beep sound to indicate the user that the key wasn't handled.
        case WM_CHAR;

            // Control characters generate key codes < 32, and this program wants to know which code points would
            // have been generated if control were not pressed. currently this only gets the vkey rather than
            // the unicode. there appears to be a way to translate it w/ windows but it looks awful so I'm avoiding it.
            code_point := U32_MAX;
            if !last_vkey_modified_by_control || (wParam >= 32 && wParam != 127) {
                code_point = xx wParam;
            } else if (last_vkey >= 32 && last_vkey <= 126) || (last_vkey >= 128) {
                code_point = last_vkey;
                if code_point >= #char "A" && code_point <= #char "Z" && !last_vkey_modified_by_shift {
                    // because the vkey was pressed without shift, uncapitalize the letter
                    code_point += 32;
                }
            }
            if code_point != U32_MAX {
                Take_Raw_Input(code_point);
            }
        case WM_MOUSEMOVE;
            if !tracking_mouse_leave {
                track_mouse_event := TRACKMOUSEEVENT.{
                    cbSize=size_of(TRACKMOUSEEVENT),
                    dwFlags=TME_LEAVE,
                    hwndTrack=hwnd,
                };
                tracking_mouse_leave = TrackMouseEvent(*track_mouse_event) != 0;
            }
            mouse_position := Mouse_Position_From_LParam(lParam);
            title_bar_button := Win32_Custom_Title_Bar_Button_At(hwnd, mouse_position);
            Set_Custom_Title_Bar_Hovered_Button(title_bar_button);
            if title_bar_button != .NONE
            || Custom_Title_Bar_Pressed_Button() != .NONE
            || mouse_position.y < Custom_Title_Bar_Height() {
                mouse_hover_position_is_known = false;
                return 0;
            }
            Take_Mouse_Event(.MOVE, mouse_position);
        case WM_MOUSELEAVE;
            tracking_mouse_leave = false;
            Set_Custom_Title_Bar_Hovered_Button(.NONE);
            Take_Mouse_Event(.LEAVE, .{});
        case WM_LBUTTONDOWN;
            mouse_position := Mouse_Position_From_LParam(lParam);
            title_bar_button := Win32_Custom_Title_Bar_Button_At(hwnd, mouse_position);
            if title_bar_button != .NONE {
                Set_Custom_Title_Bar_Hovered_Button(title_bar_button);
                Set_Custom_Title_Bar_Pressed_Button(title_bar_button);
                SetCapture(hwnd);
                return 0;
            }
            mouse_left_button_down = true;
            SetCapture(hwnd);
            Take_Mouse_Event(.LEFT_DOWN, mouse_position);
        case WM_LBUTTONDBLCLK;
            mouse_position := Mouse_Position_From_LParam(lParam);
            title_bar_button := Win32_Custom_Title_Bar_Button_At(hwnd, mouse_position);
            if title_bar_button != .NONE {
                Set_Custom_Title_Bar_Hovered_Button(title_bar_button);
                Set_Custom_Title_Bar_Pressed_Button(title_bar_button);
                SetCapture(hwnd);
                return 0;
            }
            mouse_left_button_down = true;
            SetCapture(hwnd);
            Take_Mouse_Event(.LEFT_DOUBLE_CLICK, mouse_position);
        case WM_LBUTTONUP;
            mouse_position := Mouse_Position_From_LParam(lParam);
            if Custom_Title_Bar_Pressed_Button() != .NONE {
                pressed_button := Custom_Title_Bar_Pressed_Button();
                hovered_button := Win32_Custom_Title_Bar_Button_At(hwnd, mouse_position);
                Set_Custom_Title_Bar_Hovered_Button(hovered_button);
                Set_Custom_Title_Bar_Pressed_Button(.NONE);
                ReleaseCapture();
                if hovered_button == pressed_button {
                    Perform_Custom_Title_Bar_Button_Action(hwnd, pressed_button);
                }
                return 0;
            }
            Take_Mouse_Event(.LEFT_UP, mouse_position);
            mouse_left_button_down = false;
            ReleaseCapture();
        case WM_CANCELMODE; #through;
        case WM_CAPTURECHANGED;
            Set_Custom_Title_Bar_Pressed_Button(.NONE);
            // ReleaseCapture() sends WM_CAPTURECHANGED too; preserve the
            // queued button-up event in that normal completion path.
            if mouse_left_button_down {
                Cancel_Mouse_Interaction();
            }
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
    window_class.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC | CS_DBLCLKS; // https://learn.microsoft.com/en-us/windows/win32/winmsg/window-class-styles
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
// Keep the standard state-management bits, including WS_CAPTION, so Windows
// preserves minimize/taskbar semantics. WM_NCCALCSIZE removes the actual
// non-client caption and gives the full surface to Vai's custom frame.
WINDOWED_STYLE : u32 : WS_OVERLAPPEDWINDOW;
SECONDARY_WINDOW_STYLE : u32 : WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME;
CS_DBLCLKS :: 0x0008;
TME_LEAVE :: 0x0000_0002;
HTCLIENT :: 1;
HTCAPTION :: 2;
HTLEFT :: 10;
HTRIGHT :: 11;
HTTOP :: 12;
HTTOPLEFT :: 13;
HTTOPRIGHT :: 14;
HTBOTTOM :: 15;
HTBOTTOMLEFT :: 16;
HTBOTTOMRIGHT :: 17;
DWMWA_WINDOW_CORNER_PREFERENCE :: 33;
DWMWCP_DONOTROUND :: 1;
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

TRACKMOUSEEVENT :: struct {
    cbSize: u32;
    dwFlags: u32;
    hwndTrack: HWND;
    dwHoverTime: u32;
}

TrackMouseEvent :: (event: *TRACKMOUSEEVENT) -> BOOL #foreign user32;
GetDpiForWindow :: (hwnd: HWND) -> u32 #foreign user32;
GetSystemMetricsForDpi :: (index: s32, dpi: u32) -> s32 #foreign user32;
IsZoomed :: (hwnd: HWND) -> BOOL #foreign user32;
dwmapi :: #system_library "Dwmapi";
DwmSetWindowAttribute :: (hwnd: HWND, attribute: u32, value: *void, value_size: u32) -> HRESULT #foreign dwmapi;

NCCALCSIZE_PARAMS :: struct {
    rgrc: [3]RECT;
    lppos: *void;
}

window_class_created := false;
last_vkey: u32;
last_vkey_modified_by_control: bool;
last_vkey_modified_by_shift: bool;
tracking_mouse_leave: bool;
