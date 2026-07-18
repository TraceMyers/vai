
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ------------------------------------------------------------------------------------------------------- build options
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// [heavy optimization=false] or [not + debug info=true]
debug_build := false; 
// packaging stuff into release folder
make_release := false;
// auto-places profiler hooks throughout program; profiling data is printed after a run
do_profiling := false; 

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#run {
    set_build_options_dc(.{do_output=false});

    make_directory_if_it_does_not_exist("bin");
    if !Build_Native_Preview_Provider() {
        return;
    }
    if !Build_Native_Language_Libs() {
        return;
    }

    w := compiler_create_workspace();
    build_options := get_build_options(w);
    build_options.entry_point_name = "Vai_Main";
    build_options.output_executable_name = "vai";
    build_options.output_path = "bin";
    build_options.output_type = .EXECUTABLE;
    if debug_build {
        set_optimization(*build_options, .VERY_DEBUG);
    } else {
        set_optimization(*build_options, .VERY_OPTIMIZED);
    }
    set_build_options(build_options, w);

    iprof := Iprof.get_plugin();
    if do_profiling {
        iprof_flags: Intercept_Flags;
        defer Iprof.finish(iprof);
        Iprof.before_intercept(iprof, *iprof_flags);
        iprof.workspace = w;
    }

    compiler_begin_intercept(w);

    if do_profiling {
        Iprof.add_source(iprof);
    }

    if !debug_build {
        // removes console/prints
        add_build_string("#run disable_runtime_console();", w);
    }
    add_build_file("src/main.jai", w);

    while true {
        message := compiler_wait_for_message();
        if do_profiling {
            Iprof.message(iprof, message);
        }
        if message.kind == {
        case .COMPLETE;
            break;
        case .ERROR;
            return;
        }
    }

    compiler_end_intercept(w);

    if make_release {
        make_directory_if_it_does_not_exist("release/bin", true);
        make_directory_if_it_does_not_exist("release/fonts");
        make_directory_if_it_does_not_exist("release/preview-sdk");
        copy_file("bin/vai.exe", "release/bin/vai.exe");
        copy_file("bin/vai_builtin_scene_preview.dll", "release/bin/vai_builtin_scene_preview.dll");
        copy_files_recursively("fonts", "release/fonts");
        copy_files_recursively("docs", "release/docs");
        copy_file("native_preview/vai_scene_preview_api.h", "release/preview-sdk/vai_scene_preview_api.h");
    }
}

Build_Native_Preview_Provider :: () -> bool {
    #if OS != .WINDOWS {
        return true;
    }

    // The provider keeps large C/C++ importers out of the editor executable.
    // It is rebuilt as part of every Vai build, while CMake/MSBuild make the
    // no-change path incremental.
    cmake_result, _, _ := run_command(
        "cmake",
        "-S", "native_preview",
        "-B", ".build/native_preview",
        "-G", "Visual Studio 16 2019",
        "-A", "x64",
        capture_and_return_output=true,
        print_captured_output=true,
    );
    if cmake_result.exit_code != 0 {
        compiler_report("Failed to configure the native scene preview provider.\n");
        return false;
    }

    provider_build_result, _, _ := run_command(
        "cmake",
        "--build", ".build/native_preview",
        "--config", "Release",
        "--target", "vai_builtin_scene_preview",
        "--", "/m:8",
        capture_and_return_output=true,
        print_captured_output=true,
    );
    if provider_build_result.exit_code != 0 {
        compiler_report("Failed to build the native scene preview provider.\n");
        return false;
    }

    if !copy_file(".build/native_preview/output/Release/vai_builtin_scene_preview.dll", "bin/vai_builtin_scene_preview.dll") {
        compiler_report("Failed to copy the native scene preview provider into bin. Close any running Vai instance and try again.\n");
        return false;
    }
    return true;
}

Build_Native_Language_Libs :: () -> bool {
    #if OS != .WINDOWS {
        return true;
    }

    // The tree-sitter runtime and per-language grammar parsers are C and are
    // statically linked into the editor.  src/tree_sitter.jai references them
    // from <project>/libs, so the built archives are copied there.
    config_result, _, _ := run_command(
        "cmake",
        "-S", "native_language",
        "-B", ".build/native_language",
        "-G", "Visual Studio 16 2019",
        "-A", "x64",
        capture_and_return_output=true,
        print_captured_output=true,
    );
    if config_result.exit_code != 0 {
        compiler_report("Failed to configure the native language libraries.\n");
        return false;
    }

    build_result, _, _ := run_command(
        "cmake",
        "--build", ".build/native_language",
        "--config", "Release",
        "--target", "tree-sitter",
        "--target", "jai-grammar",
        "--", "/m:8",
        capture_and_return_output=true,
        print_captured_output=true,
    );
    if build_result.exit_code != 0 {
        compiler_report("Failed to build the native language libraries.\n");
        return false;
    }

    make_directory_if_it_does_not_exist("libs");
    libs :: string.["tree-sitter", "jai-grammar"];
    for libs {
        source := tprint(".build/native_language/output/Release/%.lib", it);
        dest   := tprint("libs/%.lib", it);
        if !copy_file(source, dest) {
            compiler_report(tprint("Failed to copy % into libs. Close any running Vai instance and try again.\n", it));
            return false;
        }
    }
    return true;
}

// copied from MacOs_Bundler.jai module
copy_files_recursively :: (source: string, dest: string) {
    paths: [2] string;
    paths[0] = source;
    paths[1] = dest;

    visitor :: (info: *File_Visit_Info, paths: [2] string) {
        relative_path := info.full_name;
        advance(*relative_path, paths[0].count);
        out_path := join(paths[1], "/", relative_path);
        make_directory_if_it_does_not_exist(path_strip_filename(out_path), recursive = true);
        copy_file(info.full_name, out_path);
    }

    res := visit_files(paths[0], true, paths, visitor);
    assert(res);
}

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
Iprof :: #import "Iprof";
