
SETTINGS_FILE_NAME :: "settings.txt";

// for use with Scoped_Construct
Runtime_Settings :: struct {

    Initialize :: () -> success: bool {
        window.info = *settings_file_data.window_info;
        Load_Struct_From_Text_File(SETTINGS_FILE_NAME, *settings_file_data);
        return true;
    }

    Shutdown :: () {
        // compensation for extending rect into client area in window. TODO: is this actually constant? it's in the win32 docs
        // (seet Input's windows.jai: 8 left 8 right, blah blah)
        // window.width = max(window.width - 16, Window.MIN_WIDTH);
        // window.height = max(window.height - 39, Window.MIN_HEIGHT);
        Save_Struct_To_Text_File(SETTINGS_FILE_NAME, *settings_file_data);
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
    
    #place window_width;
        window_info: WindowInfo = ---;
}

settings_file_data: SettingsFileData;

file_editor_background_color: fRGB;
file_editor_outline_color: fRGBA;
top_bar_background_color: fRGB;
vim_console_background_color: fRGBA;