
// TODO: replace simp with win32 minimum necessities
// TODO: replace input with win32 minimum necessities
// TODO: continue refactor after that...

Main :: () {
    #if OS == .WINDOWS {
        SetProcessDPIAware();
        timeBeginPeriod(1);
    }

    path := path_strip_filename(get_path_of_running_executable());
    set_working_directory(path);

    Scoped_Construct(Text_Buffers);
    Scoped_Construct(Runtime_Settings);

    window.handle = Create_Window(window.width, window.height, "vai editor", window.x, window.y);
    Prepare_Window(1);

    while !quit {
        Update_Window_Events();
        Update_Window();
    }
}

quit: bool;

#import "Basic";
#import "Math";
#import "File";
#import "String";
#import "Thread";
#import "System";
#if OS == .WINDOWS {
    #import "Windows";
}

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