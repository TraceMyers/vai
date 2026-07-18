
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

CustomTitleBarButton :: enum u8 {
    NONE;
    MINIMIZE;
    MAXIMIZE;
    CLOSE;
}

CUSTOM_TITLE_BAR_HEIGHT_96 :: 28;
CUSTOM_TITLE_BAR_BUTTON_WIDTH_96 :: 36;

Scale_Custom_Title_Bar_Metric :: (metric_at_96_dpi: s32, dpi: u32) -> s32 {
    safe_dpi := max(dpi, 96);
    return max((metric_at_96_dpi * cast(s32)safe_dpi + 48) / 96, 1);
}

Custom_Title_Bar_Height :: () -> s32 {
    return Scale_Custom_Title_Bar_Metric(CUSTOM_TITLE_BAR_HEIGHT_96, Platform_Window_Dpi());
}

Custom_Title_Bar_Button_Width :: () -> s32 {
    return Scale_Custom_Title_Bar_Metric(CUSTOM_TITLE_BAR_BUTTON_WIDTH_96, Platform_Window_Dpi());
}

Custom_Title_Bar_Button_Rect :: (button: CustomTitleBarButton, window_width: s32, title_bar_height: s32, button_width: s32) -> IntVector2, IntVector2 {
    button_from_right: s32;
    if button == {
    case .CLOSE;
        button_from_right = 1;
    case .MAXIMIZE;
        button_from_right = 2;
    case .MINIMIZE;
        button_from_right = 3;
    case;
        return .{}, .{};
    }
    lr_x := max(window_width - button_width * (button_from_right-1), 0);
    ul_x := max(lr_x - button_width, 0);
    return .{ul_x, 0}, .{lr_x, max(title_bar_height, 0)};
}

Custom_Title_Bar_Button_At :: (position: IntVector2, window_width: s32, title_bar_height: s32, button_width: s32) -> CustomTitleBarButton {
    if position.y < 0 || position.y >= title_bar_height {
        return .NONE;
    }
    for button: CustomTitleBarButton.MINIMIZE..CustomTitleBarButton.CLOSE {
        ul, lr := Custom_Title_Bar_Button_Rect(button, window_width, title_bar_height, button_width);
        if position.x >= ul.x && position.x < lr.x {
            return button;
        }
    }
    return .NONE;
}

Set_Custom_Title_Bar_Hovered_Button :: (button: CustomTitleBarButton) {
    if custom_title_bar_hovered_button != button {
        custom_title_bar_hovered_button = button;
        custom_title_bar_ui_changed = true;
    }
}

Set_Custom_Title_Bar_Pressed_Button :: (button: CustomTitleBarButton) {
    if custom_title_bar_pressed_button != button {
        custom_title_bar_pressed_button = button;
        custom_title_bar_ui_changed = true;
    }
}

Custom_Title_Bar_Hovered_Button :: () -> CustomTitleBarButton {
    return custom_title_bar_hovered_button;
}

Custom_Title_Bar_Pressed_Button :: () -> CustomTitleBarButton {
    return custom_title_bar_pressed_button;
}

Mark_Custom_Title_Bar_UI_Changed :: () {
    custom_title_bar_ui_changed = true;
}

Consume_Custom_Title_Bar_UI_Changed :: () -> bool {
    changed := custom_title_bar_ui_changed;
    custom_title_bar_ui_changed = false;
    return changed;
}

Query_Window_Dimensions :: inline () -> (s32, s32) {
    w, h := Query_Window_Dimensions(window.handle);
    return w, h;
}

Window_Dimensions_Are_Renderable :: (width: s32, height: s32) -> bool {
    return width > 0 && height > 0;
}

Window_Is_Renderable :: () -> bool {
    return Window_Dimensions_Are_Renderable(window.width, window.height);
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
custom_title_bar_hovered_button: CustomTitleBarButton;
custom_title_bar_pressed_button: CustomTitleBarButton;
custom_title_bar_ui_changed: bool;
