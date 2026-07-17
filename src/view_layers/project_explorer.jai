Render_Layer :: (using project_explorer: *ProjectExplorer, is_active: bool, render_pass: ViewRenderPass) {
    view := *view_pool.items[tool_view_id];
    if view.viewport.left <= 0.0 {
        return;
    }
    if render_pass == {
    case .BACKGROUND;
        Render_Quad(rendering_scissor_ul, rendering_scissor_lr, .{rgb=file_explorer_background_color, a=1.0});
    case .TEXT;
        Render_Project_Explorer_Text(project_explorer, is_active);
    case .LINES;
        Render_Quad_Lines(Upper_Left(), Lower_Right(), .{rgb=fRGB_WHITE, a=0.35});
    }
}

Render_Project_Explorer_Text :: (project_explorer: *ProjectExplorer, is_active: bool) {
    view_layer := View_Layer_From_Data(xx project_explorer);
    text_buffer := Layer_Text_Buffer(view_layer);
    if text_buffer == null then return;

    ul := Upper_Left();
    lr := Lower_Right();
    ul.x += 9;
    ul.y += 9;
    lr.x -= 9;
    lr.y -= 9;
    Set_View_Scissor(ul, lr);

    renderer: TextRenderer;
    Initialize_Text_Renderer(*renderer, view_layer, 0);

    listing_directory := ifx project_explorer.directory.count > 0
        then project_explorer.directory
        else Project_Config_Root();
    is_project_config := project_explorer.directory.count > 0;
    recreate_list := text_buffer.file_path != listing_directory;
    success, directory_list := Directory_List(listing_directory);
    if !success {
        return;
    }

    if recreate_list {
        Clear_Text_Buffer(text_buffer, true);
        Initialize_Text_Buffer(text_buffer, copy_string(listing_directory), 64, 64, false);
        if is_project_config {
            Append_Line(text_buffer, tprint("Project config: %", listing_directory), false);
        } else {
            Append_Line(text_buffer, "Projects", false);
        }
        if is_project_config {
            // The action row is drawn separately so it can remain visually
            // distinct from editable project configuration files.
            Append_Line(text_buffer, "", false);
        }
        for directory_list {
            if is_project_config {
                if it.is_directory || it.is_symlink {
                    continue;
                }
            } else if !it.is_directory && !it.is_symlink {
                continue;
            }
            Append_Line(text_buffer, tprint("   %", it.name), false);
        }
        project_explorer.cursor.x = 0;
        project_explorer.cursor.target_x = 0;
        project_explorer.cursor.y = sdw(1);
        view_layer.view_position = .{};
    }

    // The directory may have changed since the last input event. Clamp here,
    // immediately before rendering, so the cursor never draws at a stale row.
    Project_Explorer_Clamp_Cursor(*project_explorer.cursor, text_buffer);

    Set_Shader_For_Blended_Color();
    line_y : s32 = 1;
    if is_project_config {
        line_y = 2;
    }
    for directory_list {
        if is_project_config {
            if it.is_directory || it.is_symlink {
                continue;
            }
            Draw_Text_File_Icon(*renderer, 0, line_y, ifx line_y == project_explorer.cursor.y then 0.8 else 0.5);
        } else {
            if !it.is_directory && !it.is_symlink {
                continue;
            }
            folder_color := fRGBA.{rgb=.{0.94, 0.835, 0.57}, a=ifx line_y == project_explorer.cursor.y then 0.8 else 0.5};
            Draw_Folder_Icon(*renderer, 0, line_y, *folder_color);
        }
        line_y += 1;
    }

    Set_Shader_For_Text();
    Render_Text_Buffer_Lines(view_layer, *renderer, text_buffer, false);
    Flush_Draws();

    if is_project_config {
        label := ifx project_explorer.directory == project_state.config_directory
            then "[current project]"
            else "[open project]";
        // Text_To_Render_Space returns a glyph baseline, one rendered row
        // below the cursor-block origin for this blank backing line.
        _, label_y := Text_To_Render_Space(*renderer, 0, 2);
        Render_Text_String_At(label, renderer.align_info_main.screen_x, label_y, color=.{rgb=fRGB_WHITE, a=0.45});
    }

    View_Scroll(view_layer, *renderer, text_buffer);
    if project_explorer.cursor.y >= 1 {
        renderer.cursor_pos = .{project_explorer.cursor.x, project_explorer.cursor.y};
        Render_Cursor_Line_Block(*renderer, *project_explorer.cursor, 0.18);
    }
}

Project_Explorer_Show_Current_Project :: () {
    Project_Explorer_Set_Directory(project_state.config_directory);
}

Project_Explorer_Set_Directory :: (directory: string) {
    tool_view := *view_pool.items[tool_view_id];
    explorer := *tool_view.layers[ToolViewLayer.PROJECT_EXPLORER].project_explorer;
    String_Reset(*explorer.directory);
    explorer.directory = copy_string(directory);
    Convert_To_Forward_Slashes(explorer.directory);
    explorer.cursor = .{};
    View_Layer_Soft_Reset(*tool_view.layers[ToolViewLayer.PROJECT_EXPLORER]);
}

Project_Explorer_Show_All_Projects :: () {
    Project_Explorer_Set_Directory("");
    explorer := *view_pool.items[tool_view_id].layers[ToolViewLayer.PROJECT_EXPLORER].project_explorer;
    explorer.cursor.y = 1;
}

Project_Explorer_Selected_Project_Name :: () -> string {
    explorer := *view_pool.items[tool_view_id].layers[ToolViewLayer.PROJECT_EXPLORER].project_explorer;
    if explorer.directory.count > 0 || explorer.cursor.y < 1 {
        return "";
    }
    success, projects := Directory_List(Project_Config_Root());
    if !success then return "";
    project_index := explorer.cursor.y - 1;
    list_index: s32;
    for projects {
        if !it.is_directory && !it.is_symlink {
            continue;
        }
        if list_index == project_index {
            return it.name;
        }
        list_index += 1;
    }
    return "";
}

Project_Explorer_Normal_Mode_Return :: () {
    explorer := *view_pool.items[tool_view_id].layers[ToolViewLayer.PROJECT_EXPLORER].project_explorer;
    if explorer.directory.count == 0 {
        project_name := Project_Explorer_Selected_Project_Name();
        if project_name.count > 0 {
            Project_Explorer_Set_Directory(Project_Config_Directory(project_name));
        }
        return;
    }

    if explorer.cursor.y == 1 {
        if explorer.directory == project_state.config_directory {
            return;
        }
        success, unused, project_name := split_from_right(explorer.directory, #char "/");
        if success && Project_Load(project_name) {
            Project_Explorer_Show_Current_Project();
            Execute_Command_Hide_Tool_View();
        }
        return;
    }
    if explorer.cursor.y < 2 {
        return;
    }

    success, config_files := Directory_List(explorer.directory);
    if !success then return;
    file_index := explorer.cursor.y - 2;
    list_index: s32;
    for config_files {
        if it.is_directory || it.is_symlink {
            continue;
        }
        if list_index == file_index {
            editor_layer := Find_First_Layer_Of_Type_In_View_Stack(.FILE_EDITOR);
            if editor_layer != null {
                Open_File_In_Editor(*editor_layer.file_editor, tprint("%/%", explorer.directory, it.name), false);
            }
            return;
        }
        list_index += 1;
    }
}

Project_Explorer_Scroll_Left :: () {
    explorer := *view_pool.items[tool_view_id].layers[ToolViewLayer.PROJECT_EXPLORER].project_explorer;
    if explorer.directory.count > 0 {
        Project_Explorer_Show_All_Projects();
    }
}

Project_Explorer_Clamp_Cursor :: (cursor: *Cursor, text_buffer: *TextBuffer) {
    cursor.y = clamp(cursor.y, 0, sdw(max(text_buffer.lines.count-1, 0)));
    // Line zero is a heading, never a selectable entry. An empty projects
    // directory has only that line, so leave its cursor at zero in that case.
    if text_buffer.lines.count > 1 {
        cursor.y = max(cursor.y, sdw(1));
    }
    cursor.x = 0;
    cursor.target_x = 0;
}
