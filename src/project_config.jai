// All persistent Vai data is kept under the current user's AppData
// directory so an installed executable never needs write access to itself.

Project_Configuration :: struct {
    Initialize :: () -> bool {
        app_data := get_path_os_program_data();
        defer free(app_data);

        vai_config_directory = copy_string(tprint("%/Vai", app_data));
        Convert_To_Forward_Slashes(vai_config_directory);
        make_directory_if_it_does_not_exist(vai_config_directory, recursive=true);
        make_directory_if_it_does_not_exist(Project_Config_Root(), recursive=true);
        make_directory_if_it_does_not_exist(Main_Config_Directory(), recursive=true);

        Load_Struct_From_Text_File(Main_Settings_Path(), *main_settings_file_data);
        main_settings_file_data_path, has_main_settings := Read_Entire_File(Main_Settings_Path());
        if has_main_settings {
            free(main_settings_file_data_path.data);
        } else {
            Save_Struct_To_Text_File(Main_Settings_Path(), *main_settings_file_data);
        }
        settings_file_data = main_settings_file_data;
        window.info = *settings_file_data.window_info;

        Load_Struct_From_Text_File(Session_Path(), *session_file_data);
        default_main_directory := copy_string(get_working_directory());
        defer free(default_main_directory);

        // Project_Load updates session_file_data, so hold a temporary copy rather
        // than a pointer into the field it will replace.
        initial_project := Temp_Copy_String(session_file_data.last_project);
        if initial_project.count == 0 || !Project_Exists(initial_project) {
            if !Project_Exists("default") {
                Project_Create("default", default_main_directory);
            }
            initial_project = "default";
        }
        Project_Load(initial_project, restore_views=false);
        return true;
    }

    Shutdown :: () {
        // Window placement and the tool width are application-wide preferences,
        // even when a project supplied a settings overlay.
        main_settings_file_data.window_info = settings_file_data.window_info;
        main_settings_file_data.tool_view_screen_proportion = settings_file_data.tool_view_screen_proportion;
        Save_Struct_To_Text_File(Main_Settings_Path(), *main_settings_file_data);
        Save_Struct_To_Text_File(Session_Path(), *session_file_data);

        String_Reset(*project_state.name);
        String_Reset(*project_state.config_directory);
        String_Reset(*project_state.main_directory);
        String_Reset(*session_file_data.last_project);
        String_Reset(*vai_config_directory);
    }
}

ProjectFileData :: struct {
    main_directory: string;
}

SessionFileData :: struct {
    last_project: string;
}

ProjectState :: struct {
    name: string;
    config_directory: string;
    main_directory: string;
}

Main_Config_Directory :: () -> string {
    return tprint("%/main", vai_config_directory);
}

Project_Config_Root :: () -> string {
    return tprint("%/projects", vai_config_directory);
}

Main_Settings_Path :: () -> string {
    return tprint("%/settings.txt", Main_Config_Directory());
}

Session_Path :: () -> string {
    return tprint("%/session.txt", Main_Config_Directory());
}

Project_Config_Directory :: (name: string) -> string {
    return tprint("%/%", Project_Config_Root(), name);
}

Project_File_Path :: (name: string, file_name: string) -> string {
    return tprint("%/%", Project_Config_Directory(name), file_name);
}

Project_Exists :: (name: string) -> bool {
    if !Project_Name_Is_Valid(name) then return false;
    success, _ := Directory_List(Project_Config_Directory(name));
    return success;
}

Project_Name_Is_Valid :: (name: string) -> bool {
    if name.count == 0 then return false;
    for name {
        if it == #char "/" || it == #char "\\" || it == #char ":" {
            return false;
        }
    }
    return true;
}

Project_Create :: (name: string, main_directory: string) -> bool {
    if !Project_Name_Is_Valid(name) {
        Log_Warning("project names cannot be empty or contain path separators");
        return false;
    }

    config_directory := Project_Config_Directory(name);
    make_directory_if_it_does_not_exist(config_directory, recursive=true);

    project_file_data: ProjectFileData;
    project_file_data.main_directory = copy_string(main_directory);
    Convert_To_Forward_Slashes(project_file_data.main_directory);
    Save_Struct_To_Text_File(Project_File_Path(name, "project.txt"), *project_file_data);
    String_Reset(*project_file_data.main_directory);
    return true;
}

Project_Load :: (name: string, restore_views := true) -> bool {
    if !Project_Exists(name) {
        return false;
    }

    if project_state.name.count > 0 && project_state.name != name {
        Project_Save_View_Session();
    }

    project_file_data: ProjectFileData;
    Load_Struct_From_Text_File(Project_File_Path(name, "project.txt"), *project_file_data);
    if project_file_data.main_directory.count == 0 {
        String_Reset(*project_file_data.main_directory);
        project_file_data.main_directory = copy_string(get_working_directory());
        Project_Create(name, project_file_data.main_directory);
    }

    directory_success, _ := Directory_List(project_file_data.main_directory);
    if !directory_success {
        Log_Warning("project [%] has an invalid main_directory [%]", name, project_file_data.main_directory);
        String_Reset(*project_file_data.main_directory);
        return false;
    }

    String_Reset(*project_state.name);
    String_Reset(*project_state.config_directory);
    String_Reset(*project_state.main_directory);
    project_state.name = copy_string(name);
    project_state.config_directory = copy_string(Project_Config_Directory(name));
    project_state.main_directory = project_file_data.main_directory;

    String_Reset(*session_file_data.last_project);
    session_file_data.last_project = copy_string(name);

    set_working_directory(project_state.main_directory);
    settings_file_data = main_settings_file_data;
    Load_Struct_From_Text_File(Project_File_Path(name, "settings.txt"), *settings_file_data, reset=false);
    window.info = *settings_file_data.window_info;
    if !Is_Empty(*view_pool) {
        File_Explorer_Set_Directory(project_state.main_directory);
    }

    if restore_views {
        Project_Restore_View_Session();
    }
    return true;
}

Project_Save_View_Session :: () {
    if project_state.name.count == 0 || !Is_Item_In_Use(*view_pool, base_empty_view_id) {
        return;
    }

    paths: [..]string;
    paths.allocator = temp;
    Project_Collect_Open_Files(*paths, base_empty_view_id);

    builder: String_Builder;
    builder.allocator = temp;
    for paths {
        print_to_builder(*builder, "%\n", it);
    }
    write_entire_file(Project_File_Path(project_state.name, "views.txt"), builder_to_string(*builder));
}

Project_Collect_Open_Files :: (paths: *[..]string, view_id: s64) {
    view := *view_pool.items[view_id];
    if view.layers.count > 0 {
        layer := *view.layers[view.active_layer];
        if layer.type == .FILE_EDITOR {
            buffer := Layer_Text_Buffer(layer);
            if buffer != null && buffer.file_path.count > 0 {
                array_add(paths, buffer.file_path);
            }
        }
    }
    for view.children {
        Project_Collect_Open_Files(paths, it);
    }
}

Project_Restore_View_Session :: () {
    session_data, success := Read_Entire_File(Project_File_Path(project_state.name, "views.txt"));
    if !success || session_data.count == 0 {
        if session_data.data != null then free(session_data.data);
        return;
    }
    defer free(session_data.data);

    editor_view_ids: [..]s64;
    editor_view_ids.allocator = temp;
    Project_Collect_Editor_View_IDs(*editor_view_ids, base_empty_view_id);
    if editor_view_ids.count == 0 then return;

    // Keep one editor and remove the previous project's other editor views.
    editor_id_index := editor_view_ids.count - 1;
    while editor_id_index >= 1 {
        Close_View(editor_view_ids[editor_id_index]);
        editor_id_index -= 1;
    }
    editor_view_ids.count = 0;
    Project_Collect_Editor_View_IDs(*editor_view_ids, base_empty_view_id);
    first_editor := *view_pool.items[editor_view_ids[0]];

    file_count: s64;
    offset: s64;
    while offset < session_data.count {
        end := find_index_from_left(slice(session_data, offset, session_data.count-offset), "\n", 0);
        line_count := ifx end == -1 then session_data.count-offset else end;
        file_path := slice(session_data, offset, line_count);
        if file_path.count > 0 {
            target_editor := first_editor;
            if file_count > 0 {
                target_editor = Split_View(first_editor, .HORIZONTAL, false);
            }
            if Open_File_In_Editor(*target_editor.layers[0].file_editor, file_path, false) {
                file_count += 1;
            }
        }
        offset += line_count + 1;
    }
}

Project_Collect_Editor_View_IDs :: (ids: *[..]s64, view_id: s64) {
    view := *view_pool.items[view_id];
    if view.layers.count > 0 && view.layers[view.active_layer].type == .FILE_EDITOR {
        array_add(ids, view_id);
    }
    for view.children {
        Project_Collect_Editor_View_IDs(ids, it);
    }
}

vai_config_directory: string;
project_state: ProjectState;
session_file_data: SessionFileData;
