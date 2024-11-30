
// TODO: replace simp with win32 minimum necessities
// TODO: replace input with win32 minimum necessities
// TODO: continue refactor after that...
// TODO: font scaling in a not ugly way - how to use scale + loaded font sizes effectively

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
    // Prepare_Window(1);

    Initialize_Fonts();

    while !quit {
        resized := Update_Window_Dimensions();
        if resized {
            Post_Resize_Window();
        }

        Begin_Draw_Frame();
        // Post_Resize_Window();

        Set_Shader_For_Blended_Color();
        Render_Quad(.{200, 200}, .{300, 300}, .{b=0.9});

        Set_Shader_For_Color_Inversion();
        Render_Quad(.{250, 250}, .{350, 350});

        Prepare_Text("hello, sailor!");
        Generate_Quads_For_Prepared_Text(600, 100);
        Render_Quads_Generated_For_Text();

        End_Draw_Frame();
        Text_End_Frame();

        // put this at the end so we can exit the loop immediately when the window has been closed by the user
        Update_Window_Events();

        frame_counter += 1;
        reset_temporary_storage();
    }
}

quit: bool;

#import "Basic";
#import "Math";
#import "File";
#import "String";
#import "Thread";
#import "System";
// for fonts
#import "Simp";

#if OS == .WINDOWS {
    #import "Windows";
}
Compiler :: #import "Compiler";
Program_Print :: #import "Program_Print";

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
#load "text.jai";
// #load "../modules/Simp/font.jai";