
// TODO: apparently, memory leak when pasting ~10 lines of text ~1k times. OR, absurd numbers
// of temp allocations are being made but not reset because we're still on the same frame.
// either way. it freezes up.
// TODO: font scaling in a not ugly way - how to use scale + loaded font sizes effectively
// NOTE: put off options implementations for a while, because there are a lot of non-vim and vim options that could be brought together in a nice way, but it's probably hard to see until having gone without it for a bit.
// TODO: cursor.just_moved isn't handled right
// TODO: backslash escaping (... rethink?)
// TODO: when trying to do autocomplete suggestions, the command paerser can be used to determine
// what kind of thing we're generating suggestions for, which determines the suggestion pool :)
// TODO: need to be able to open buffers without creating files
// TODO: file explorer with file/folder creation/deletion/renaming
//      - mark ctrl s f search directories
//      - mark and color-code favorite directories
//      - show file information at the bottom
//      - scroll across current path greying out the end parts o the path as we scroll left
//      - path text edit with suggestions dropdown + highlight + one press complete
//      - lines so it looks nice
//      - font size variation
//      - hotkey key at the top

quit: bool;
exe_path: string;

Vai_Main :: () {
    #if OS == .WINDOWS {
        SetProcessDPIAware();
        timeBeginPeriod(1);
    }

    exe_path = path_strip_filename(get_path_of_running_executable());

    if !Scoped_Construct(Text_Buffers)          then return;
    if !Scoped_Construct(Runtime_Settings)      then return;
    if !Create_Window("Vai")                    then return;
    if !Scoped_Construct(Graphics_Backend)      then return;
    if !Scoped_Construct(Input)                 then return;
    if !Scoped_Construct(Viewports)             then return;
    if !Scoped_Construct(Editor_Views)          then return;
    if !Scoped_Construct(Options)               then return;

    Initialize_Render_Text();
    Initialize_Time();

    // TODO: syntax highlighting
    text_colors[0] = bRGB_WHITE;
    text_colors[1] = bRGB_RED;

    // ShowWindow(GetConsoleWindow(), SW_HIDE);

    while !quit {
        resized := Update_Window_Dimensions();
        if resized {
            Post_Resize_Window();
        }
        Update_Window_Events();
        if quit then break;
        any_input := Translate_Inputs_To_Actions();
        do_full_update := any_input | resized | ALWAYS_FULL_UPDATE;

        Begin_Update_Text_Buffers();
        Render_Views(do_full_update);
        Render_Text_End_Frame();
        End_Update_Text_Buffers();

        reset_temporary_storage();
        Sample_Frame_Time();
    }

    #if DEBUG_MEMORY {
        report_memory_leaks();
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// whatever you got
#import "Basic"()(MEMORY_DEBUGGER=DEBUG_MEMORY);
#import "Math";
#import "File";
#import "String";
#import "Thread";
#import "System";
#import "Sort";
#import "Bit_Operations";
#import "Hash_Table";
#import "File_Utilities";
#if OS == .WINDOWS {
    #import "Windows";
    #import "Windows_Resources";
}
Compiler :: #import "Compiler";
Program_Print :: #import "Program_Print";

kernel32 :: #library,system "kernel32";
GetConsoleWindow :: () -> HWND #foreign kernel32;

// modified local
#import "Simp"; // for fonts

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#load "math.jai";
#load "static_params.jai";
#load "logging.jai";
#load "utility.jai";
#load "time.jai";
#load "encoding.jai";
#load "text_buffer.jai";
#load "number_interpretation.jai";
#load "dynamic_pool.jai";
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
#load "view_layers/file_explorer.jai";
#load "view_layers/debug.jai";
#load "editor_view.jai";
#load "text_processing.jai";
#load "action_execution.jai";
#load "circular_buffer.jai";
#load "bit_array.jai";
#load "thread_worker.jai";
#load "commands.jai";