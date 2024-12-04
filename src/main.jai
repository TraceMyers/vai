
// TODO: big_code.jai bug: line 3 is begin rendered as a copy of line 2 + weird visual jitter when moving to line 3. maybe bug with long line allocation?
// TODO: font scaling in a not ugly way - how to use scale + loaded font sizes effectively

quit: bool;

Vai_Main :: () {
    #if OS == .WINDOWS {
        SetProcessDPIAware();
        timeBeginPeriod(1);
    }

    path := path_strip_filename(get_path_of_running_executable());
    set_working_directory(path);

    if !Scoped_Construct(Text_Buffers)          then return;
    if !Scoped_Construct(Runtime_Settings)      then return;
    if !Create_Window("vai")                    then return;
    if !Scoped_Construct(Graphics_Backend)      then return;
    if !Scoped_Construct(Input)                 then return;
    if !Scoped_Construct(Viewports)             then return;
    if !Scoped_Construct(Editor_Views)          then return;

    Initialize_Render_Text();
    Initialize_Time();

    // TODO: syntax highlighting
    text_colors[0] = bRGB_WHITE;
    text_colors[1] = bRGB_RED;

    while !quit {
        resized := Update_Window_Dimensions();
        if resized {
            Post_Resize_Window();
        }

        Begin_Update_Text_Buffers();
        Translate_Inputs_To_Actions();
        Render_Views();
        Render_Text_End_Frame();
        End_Update_Text_Buffers();

        reset_temporary_storage();
        Sample_Frame_Time();

        // put this at the end so we can exit the loop immediately when the window has been closed by the user
        Update_Window_Events();
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// std
#import "Basic";
#import "Math";
#import "File";
#import "String";
#import "Thread";
#import "System";
#import "Sort";
#if OS == .WINDOWS {
    #import "Windows";
}
Compiler :: #import "Compiler";
Program_Print :: #import "Program_Print";

// modified local
#import "Simp"; // for fonts

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#load "static_params.jai";
#load "logging.jai";
#load "utility.jai";
#load "time.jai";
#load "encoding.jai";
#load "text_buffer.jai";
#load "number_interpretation.jai";
#load "dynamic_pool.jai";
#load "math.jai";
#load "struct_file.jai";
#load "runtime_params.jai";
#load "window/window.jai";
#load "graphics/graphics.jai";
#load "meta.jai";
#load "render_text.jai";
#load "viewport.jai";
#load "enum_mapping.jai";
#load "options.jai";
#load "mappings.jai";
#load "input/input.jai";
#load "cursor.jai";
#load "view_layers/file_editor.jai";
#load "view_layers/top_bar.jai";
#load "view_layers/vim_console.jai";
#load "editor_view.jai";
#load "text_processing.jai";
#load "action_execution.jai";