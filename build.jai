
#run {
    set_build_options_dc(.{do_output=false});
    w := compiler_create_workspace();
    build_options := get_build_options(w);
    build_options.entry_point_name = "Main";
    build_options.output_executable_name = "vai";
    build_options.output_path = "bin";
    build_options.output_type = .EXECUTABLE;
    // set_optimization(*build_options, .VERY_OPTIMIZED);
    // set_optimization(*build_options, .OPTIMIZED_VERY_SMALL);
    set_build_options(build_options, w);
    add_build_file("src/main.jai", w);
}

#import "Basic";
#import "Compiler";