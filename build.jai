
#run {
    set_build_options_dc(.{do_output=false});

    make_directory_if_it_does_not_exist("bin");

    w := compiler_create_workspace();
    build_options := get_build_options(w);
    build_options.entry_point_name = "Vai_Main";
    build_options.output_executable_name = "vai";
    build_options.output_path = "bin";
    build_options.output_type = .EXECUTABLE;
    #if DEBUG {
        set_optimization(*build_options, .VERY_DEBUG);
    } else {
        set_optimization(*build_options, .VERY_OPTIMIZED);
    }
    set_build_options(build_options, w);

    #if DO_PROFILING {
        iprof_flags: Intercept_Flags;
        iprof := Iprof.get_plugin();
        defer Iprof.finish(iprof);
        Iprof.before_intercept(iprof, *iprof_flags);
        iprof.workspace = w;
    }

    compiler_begin_intercept(w);

    #if DO_PROFILING {
        Iprof.add_source(iprof);
    }

    #if !DEBUG {
        // removes console/prints
        add_build_string("#run disable_runtime_console();", w);
    }
    add_build_file("src/main.jai", w);

    while true {
        message := compiler_wait_for_message();
        #if DO_PROFILING {
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

    #if MAKE_RELEASE {
        make_directory_if_it_does_not_exist("release/bin", true);
        make_directory_if_it_does_not_exist("release/fonts");
        copy_file("bin/vai.exe", "release/bin/vai.exe");
        copy_files_recursively("fonts", "release/fonts");
    }
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

DEBUG :: false;
MAKE_RELEASE :: true;
DO_PROFILING :: false;

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "String";
#if DO_PROFILING {
    Iprof :: #import "Iprof";
}