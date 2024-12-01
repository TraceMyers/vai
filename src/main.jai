
// TODO: replace input with win32 minimum necessities
// TODO: continue refactor after that...
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
    if !Scoped_Construct(Editor_Views)          then return;

    Initialize_Render_Text();
    Initialize_Time();

    while !quit {
        resized := Update_Window_Dimensions();
        if resized {
            Post_Resize_Window();
        }

        Translate_Inputs_To_Actions();

        // Begin_Draw_Frame();

        // Set_Shader_For_Blended_Color();
        // Render_Quad(.{200, 200}, .{300, 300}, .{b=0.9});
        // Set_Shader_For_Color_Inversion();
        // Render_Quad(.{250, 250}, .{350, 350});

        // Set_Shader_For_Lines();
        // Render_Quad_Lines(.{200, 200}, .{300, 300}, .{rgb=RGB_WHITE, a=0.5});
        // Render_Quad_Lines(.{250, 250}, .{350, 350}, .{rgb=RGB_WHITE, a=0.5});

        // Set_Shader_For_Text();
        // Prepare_Text("hello, sailor!");
        // Generate_Quads_For_Prepared_Text(600, 100);
        // Render_Quads_Generated_For_Text();

        // End_Draw_Frame();
        Render_Views();
        Render_Text_End_Frame();

        // utf32_str := As_String(auxiliary_input_buffer);
        // ansi_str := Encode(utf32_str, .UTF32, .ANSI);
        // Log("auxiliary input buffer: %", ansi_str);

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