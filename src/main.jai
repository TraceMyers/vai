
// TODO: apparently, memory leak when pasting ~10 lines of text ~1k times. OR, absurd numbers
// of temp allocations are being made but not reset because we're still on the same frame.
// either way. it freezes up.
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
//      - if view is wide enough, preview directory expansion to the right
//      - path navigation stuff:
//          - scroll up to path and the bottom level directory will be selected
//          - if this directory has, during the session, been navigated to by going up one directory, then the source directory in that navigation will appear greyed out to the right of the cur directory, so that you can scroll to the right and go down into that directory
//          - backspace deletes the currently selected directory in the path, and allows you to type, with completion suggetions and one-tap complete for the top suggestion
//              - maybe also insert/append/cw/ciw?
//          - if possible, a preview of the file is shown at the bottom. you can press a key combo to expand the preview
//              and navigate it like a normal file buffer
//                 - loading of this needs to be async so it doesn't halt scrolling
// TODO: file buffer hotkeys, like control groups in an rts
// TODO: file buffer thread safety. disallow utf32 buffer usage outside main thread
// TODO: view scrolling is broken
// TODO: cursor target x broken (only soft wrap?)
// TODO: automated tester + write some tests
//      - should be its own program, have ability to set static and runtime params, build/run, and give inputs just like a user

quit: bool;
exe_path: string;

Vai_Main :: () {
    defer Log("Exiting");

    #if OS == .WINDOWS {
        SetProcessDPIAware();
        timeBeginPeriod(1);
    }
    main_thread_index = GetCurrentThreadId();

    exe_path = copy_string(path_strip_filename(get_path_of_running_executable()));
    defer free(exe_path);

    if Has_Command_Line_Argument("--scene-preview-smoke-test") {
        Run_Scene_Preview_Smoke_Test_Main();
        return;
    }
    if Has_Command_Line_Argument("--image-preview-smoke-test") {
        Run_Image_Preview_Smoke_Test_Main();
        return;
    }
    if Has_Command_Line_Argument("--crash-regression-tests") {
        Run_Crash_Regression_Tests();
        return;
    }
    if Has_Command_Line_Argument("--highlight-smoke-test") {
        Run_Highlight_Smoke_Test_Main();
        return;
    }

    if !Scoped_Construct(Text_Buffers)          then return;
    if !Scoped_Construct(Runtime_Settings)      then return;
    if !Scoped_Construct(Project_Configuration) then return;
    if !Scoped_Construct(Scene_Preview_Providers) then return;
    if !Create_Window("Vai")                    then return;
    if !Scoped_Construct(Graphics_Backend)      then return;
    // The worker shuts down before graphics/providers/text buffers, so an
    // in-flight preview can never outlive the shared upload context or its data.
    if !Scoped_Construct(Thread_Worker)         then return;
    if !Scoped_Construct(Input)                 then return;
    if !Scoped_Construct(Viewports)             then return;
    if !Scoped_Construct(Editor_Views)          then return;
    if !Scoped_Construct(Options)               then return;
    if !Scoped_Construct(Render_Text)           then return;
    if !Scoped_Construct(OS_Console)            then return;

    Initialize_Time();

    // TODO: syntax highlighting
    text_colors[0] = bRGB_WHITE;
    text_colors[1] = bRGB_RED;

    while !quit {
        async_ui_changed := Process_Async_Results();
        Update_Window_Events();
        window_ui_changed := Consume_Custom_Title_Bar_UI_Changed();

        if quit then break;
        // Window messages can synchronously minimize, maximize, or resize the
        // client area. Sample dimensions after dispatch so this frame never
        // renders with the pre-message size.
        resized := Update_Window_Dimensions();
        if resized && Window_Is_Renderable() {
            Post_Resize_Window();
        }
        if !Window_Is_Renderable() {
            reset_temporary_storage();
            Sample_Frame_Time();
            continue;
        }

        // Input actions mutate text buffers, so their per-frame UTF-32 storage must
        // exist before translating (and executing) those actions.  Initializing it
        // only for rendering left command/input execution using storage that had
        // already been shut down and reset at the end of the previous frame.
        Begin_Update_Text_Buffers();
        any_input := Translate_Inputs_To_Actions();
        do_full_update := any_input | resized | async_ui_changed | window_ui_changed | ALWAYS_FULL_UPDATE;

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

Has_Command_Line_Argument :: (wanted: string) -> bool {
    arguments := get_command_line_arguments();
    defer array_free(arguments);
    for arguments {
        if it == wanted return true;
    }
    return false;
}

// Kept in its own function because Scoped_Construct lifetime is lexical. This
// test intentionally skips project configuration and the worker thread so it
// cannot read or write a user's editor session.
Run_Image_Preview_Smoke_Test_Main :: () {
    if !Scoped_Construct(Runtime_Settings) then return;
    window.info = *settings_file_data.window_info;
    window.width = 256;
    window.height = 256;
    window.x = -1;
    window.y = -1;
    if !Create_Window("Vai") then return;
    if !Scoped_Construct(Graphics_Backend) then return;
    assert(Run_Production_Image_Preview_Smoke_Test());
}

Run_Scene_Preview_Smoke_Test_Main :: () {
    if !Scoped_Construct(Runtime_Settings) then return;
    window.info = *settings_file_data.window_info;
    window.width = 256;
    window.height = 256;
    window.x = -1;
    window.y = -1;
    if !Create_Window("Vai") then return;
    if !Scoped_Construct(Graphics_Backend) then return;
    if !Scoped_Construct(Thread_Worker) then return;

    provider_path := tprint("%/vai_builtin_scene_preview.dll", exe_path);
    if !Scene_Preview_Register_Provider(provider_path, required=true) {
        assert(false, "scene preview smoke test could not load the built-in provider");
        return;
    }
    defer {
        for *scene_preview_providers {
            String_Reset(*it.file_path);
        }
        array_reset(*scene_preview_providers);
        File_Explorer_Scene_Preview_Clear();
    }

    scene_path: string;
    arguments := get_command_line_arguments();
    for arguments {
        if it == "--scene-preview-smoke-test" && it_index+1 < arguments.count {
            scene_path = copy_string(arguments[it_index+1]);
            break;
        }
    }
    array_free(arguments);
    defer String_Reset(*scene_path);
    assert(Run_Production_Scene_Preview_Smoke_Test(scene_path));
}

// Headless verification of the tree-sitter highlighting integration: load Jai
// source into a real TextBuffer, run the reparse, and assert representative
// tokens receive the expected palette colors.  No window or graphics needed.
Run_Highlight_Smoke_Test_Main :: () {
    if !Scoped_Construct(Text_Buffers) then return;

    lines := string.[
        "greet :: () {",
        "    x := 42;",
        "    if true return; // done",
        "}",
    ];

    buffer: TextBuffer;
    Initialize_Text_Buffer(*buffer, copy_string("smoke.jai"), lines.count, 64, true);
    for lines  Append_Line(*buffer, it, false, false, false);
    buffer.highlight.enabled = true;
    buffer.highlight.dirty   = true;
    Highlight_Reparse_If_Dirty(*buffer);

    builder: String_Builder;
    for lines { if it_index > 0 then append(*builder, "\n"); append(*builder, it); }
    doc := builder_to_string(*builder);

    ok := true;
    Check :: (needle: string, expected: SyntaxColor) #expand {
        idx := find_index_from_left(doc, needle, 0);
        if idx < 0 {
            print("  MISSING '%'\n", needle);
            `ok = false;
            return;
        }
        got := ifx idx < buffer.highlight.byte_color.count then buffer.highlight.byte_color[idx] else cast(u8) 0xff;
        pass := got == cast(u8) expected;
        if !pass then `ok = false;
        print("  '%' @% color=% expected=% %\n", needle, idx, got, cast(u8) expected, ifx pass then "OK" else "FAIL");
    }
    Check("greet",  .DEFAULT);
    Check("42",     .NUMBER);
    Check("if",     .KEYWORD);
    Check("true",   .CONSTANT);
    Check("return", .KEYWORD);
    Check("//",     .COMMENT);

    print(ifx ok then "HIGHLIGHT SMOKE TEST PASSED\n" else "HIGHLIGHT SMOKE TEST FAILED\n");
    Shutdown_Text_Buffer(*buffer);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// whatever you got
#import "Basic"()(MEMORY_DEBUGGER=DEBUG_MEMORY);
#import "Math";
#import "File";
#import "String";
#import "Thread";
#import "Atomics";
#import "System";
#import "Sort";
#import "Bit_Operations";
#import "Hash_Table";
#import "File_Utilities";
#import "stb_image";
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
#load "tree_sitter.jai";
#load "syntax_highlight.jai";
#load "text_buffer.jai";
#load "number_interpretation.jai";
#load "dynamic_pool.jai";
#load "struct_file.jai";
#load "runtime_params.jai";
#load "project_config.jai";
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
#load "scene_preview.jai";
#load "explorer_preview.jai";
#load "view_layers/file_explorer.jai";
#load "view_layers/project_explorer.jai";
#load "view_layers/debug.jai";
#load "view_layers/os_console.jai";
#load "editor_view.jai";
#load "text_processing.jai";
#load "action_execution.jai";
#load "circular_buffer.jai";
#load "bit_array.jai";
#load "thread_worker.jai";
#load "commands.jai";
#load "draw_icon.jai";
#load "osutil/win32_utils.jai";
#load "crash_regression_tests.jai";
