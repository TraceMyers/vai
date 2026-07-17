
SETTINGS_FILE_NAME :: "settings.txt";

// for use with Scoped_Construct
Runtime_Settings :: struct {

    Initialize :: () -> success: bool {
        return true;
    }

    Shutdown :: () {
    }

}

SettingsFileData :: struct {
    window_width: s32 = 512;
    window_height: s32 = 512;
    window_x: s32 = 1;
    window_y: s32 = 1;
    window_clear_r := 1.0;
    window_clear_g := 0.0;
    window_clear_b := 0.0;
    view_accel := 1000.0;
    view_max_speed := 600.0;
    key_repeat_delay := 0.3;
    key_repeat_rate := 40.0;
    change_history_count: s32 = 100;
    record_processed_input := false;
    arrow_key_scroll_speed := 60.0;
    relative_line_numbers := false;
    tool_view_screen_proportion := 0.3;
    
    #overlay (window_width) window_info: WindowInfo = ---;
}

settings_file_data: SettingsFileData;
main_settings_file_data: SettingsFileData;

file_editor_background_color: fRGB;
file_explorer_background_color: fRGB;
file_editor_line_numbers_sep_color: fRGBA;
file_editor_outline_color: fRGBA;
top_bar_background_color: fRGB;
vim_console_background_color: fRGBA;

debug_switch_1: bool;
debug_switch_2: bool;
debug_switch_3: bool;
