
// for use with Scoped_Construct
Editor_Views :: struct {

    Initialize :: () -> bool {
        view_layer_pool.allow_grow_default = false;
        view_layer_pool.allow_shrink_default = false;
        view_pool.allow_grow_default = false;
        view_pool.allow_shrink_default = false;
        Initialize(*view_layer_pool, VIEWS_MAX);
        Initialize(*view_pool, VIEWS_MAX);
        actions_executed_this_frame.allocator = temp;

        editor_view_stack.data = editor_view_stack_buffer.data;

        Create_Base_Views();
        return true;
    }

    Shutdown :: () {
        Project_Save_View_Session();
        Shutdown(*view_layer_pool);
        Shutdown(*view_pool);
    }

}

Create_Base_Views :: () {
    BLUE :: fRGBA.{0.05, 0.2, 0.7, 1.0};

    transparent_blue := BLUE;
    transparent_blue.r *= 2.0;
    transparent_blue.g *= 2.0;
    transparent_blue.b = 0.95;
    vim_console_background_color = transparent_blue;
    top_bar_background_color = transparent_blue.rgb;
    file_editor_background_color = .{.02, .18, .24};
    file_explorer_background_color = .{.01, .15, .22};
    file_editor_outline_color = .{1,1,1,0.3};
    file_editor_line_numbers_sep_color = .{1,1,1,0.15};

    // root
    {
        id := Add_View(.{}, null);
        assert(id == ROOT_ID);
    }
    // top bar
    // {
    //     layer: ViewLayer;
    //     layer.type = .TOP_BAR;
    //     layer.top_bar = .{};
    //     Add_View(.{type=.PIXELS, top_pixels=24}, *layer, ROOT_ID);
    // }

    // // bottom bar / vim console
    {
        layer: ViewLayer;
        layer.type = .VIM_CONSOLE;
        layer.vim_console = .{};
        vim_console_id = Add_View(.{type=.PIXELS, bottom_pixels=20}, *layer, ROOT_ID);
    }

    // tool window zone
    // ------------------------------------------
    {
        layer: ViewLayer;
        layer.type = .FILE_EXPLORER;
        layer.file_explorer = .{};
        layer.file_explorer.text_buffer = Request_Item(*file_buffers);
        file_buffers.items[layer.file_explorer.text_buffer].flags = .FILE_EXPLORER;
        layer.file_explorer.directory = copy_string(get_working_directory());
        Convert_To_Forward_Slashes(layer.file_explorer.directory);
        tool_view_id = Add_View(.{type=.PROPORTION, left=0.0}, *layer, ROOT_ID);
    }
    {
        layer: ViewLayer;
        layer.type = .OS_CONSOLE;
        layer.os_console = .{};
        Add_View_Layer(*view_pool.items[tool_view_id], *layer);
    }
    {
        layer: ViewLayer;
        layer.type = .PROJECT_EXPLORER;
        layer.project_explorer = .{};
        layer.project_explorer.text_buffer = Request_Item(*file_buffers);
        file_buffers.items[layer.project_explorer.text_buffer].flags = .PROJECT_EXPLORER;
        Add_View_Layer(*view_pool.items[tool_view_id], *layer);
    }
    // ------------------------------------------

    // empty background to stage file editors
    {
        base_empty_view_id = Add_View(.{type=.PROPORTION, right=1.0}, null, ROOT_ID);
        // base_empty := Split_View(*view_pool.items[tool_view_id], .HORIZONTAL, false, 1.0);
        // .{type=.PROPORTION, right=1.0}, null, ROOT_ID
        // base_empty_view_id = base_empty - view_pool.items.data;
    }
    // default file editor
    intro_file_name := Prepare_Intro_File();
    {
        layer: ViewLayer;
        layer.type = .FILE_EDITOR;
        layer.file_editor = .{};
        layer.file_editor.file_buffer = Get_File_Buffer_ID(intro_file_name);
        Push_Active_View_ID(Add_View(.{inverted=true}, *layer, base_empty_view_id));
    }

    #if DEBUG_BIN_POOL {
        split := Split_View(*view_pool.items[Active_View_ID()], .HORIZONTAL, false);
        split.layers[0].type = .DEBUG;
        split.layers[0].debug = .{};
        split.layers[0].debug.type = .BIN_POOL;
    } else #if DEBUG_UNDO_REDO {
        split := Split_View(*view_pool.items[Active_View_ID()], .HORIZONTAL, false);
        split.layers[0].type = .DEBUG;
        split.layers[0].debug = .{};
        split.layers[0].debug.type = .UNDO_REDO;
    } else #if DEBUG_TEXT_BUFFER {
        split := Split_View(*view_pool.items[Active_View_ID()], .HORIZONTAL, false);
        split.layers[0].type = .DEBUG;
        split.layers[0].debug = .{};
        split.layers[0].debug.type = .TEXT_BUFFER;
    }
}

Prepare_Intro_File :: () -> string {
    INTRO_FILE_NAME :: "intro.txt";
    // INTRO_FILE_NAME :: "test_files/undo_redo.txt";
    // INTRO_FILE_NAME :: "test_files/struct_utilities.jai";
    file_data := read_entire_file(INTRO_FILE_NAME);
    defer free(file_data);
    // Preserve user-authored instructions, but refresh a stock intro so existing
    // installations receive the current reference.  Detect earlier stock versions
    // by a distinctive phrase each contained; none appear in the current text, so
    // a refreshed or user-edited file is never rewritten again.
    has_old_stock_intro := find_index_from_left(file_data, "currently the only tool is the file explorer, which is incomplete.", 0) != -1
        || find_index_from_left(file_data, "vim-adventures.com", 0) != -1;
    if file_data.count == 0 || has_old_stock_intro {
        write_entire_file(INTRO_FILE_NAME, INTRO_FILE_TEXT);
    }
    return INTRO_FILE_NAME;
}

Active_View :: inline () -> *View {
    return *view_pool.items[Active_View_ID()];
}

Active_View_Layer :: inline () -> *ViewLayer {
    view := Active_View();
    return *view.layers[view.active_layer];
}

View_From_ID :: inline (id: s64) -> *View {
    return *view_pool.items[id];
}

Find_View_Screen_Rect :: (wanted_view_id: s64, from_view_id: s64, from_rect: ViewportRect) -> ViewportRect, bool {
    if wanted_view_id == from_view_id {
        return from_rect, true;
    }

    view := View_From_ID(from_view_id);
    for view.children {
        child := View_From_ID(it);
        child_rect := from_rect;
        Apply_Viewport_To_Rect(*child_rect, *child.viewport);
        result_rect, found := Find_View_Screen_Rect(wanted_view_id, it, child_rect);
        if found {
            return result_rect, true;
        }
    }
    return .{}, false;
}

Set_Rendering_Bounds_To_View :: (view_id: s64) -> bool {
    if view_id < 0 || !Is_Item_In_Use(*view_pool, view_id) {
        return false;
    }
    rect, found := Find_View_Screen_Rect(view_id, ROOT_ID, Window_Viewport_Rect());
    if !found {
        return false;
    }
    rendering_scissor_ul, rendering_scissor_lr = Viewport_Rect_Points(*rect, s32);
    return true;
}

Active_Layer_Of_View :: inline (v: *View) -> *ViewLayer {
    if v.layers.count == 0 {
        return null;
    }
    return *v.layers[v.active_layer];
}

Get_Active_Layer_Of_Type :: (type: ViewLayerType) -> *View, *ViewLayer {
    if Active_View_ID() < 0 {
        return null, null;
    }
    active_view := View_From_ID(Active_View_ID());
    active_layer := Active_Layer_Of_View(active_view);
    if active_layer == null {
        return null, null;
    }
    if (active_layer.type & type) == 0 {
        return null, null;
    }
    return active_view, active_layer;
}

OS_Console_Layer :: () -> *ViewLayer {
    return *view_pool.items[tool_view_id].layers[OS_CONSOLE_LAYER];
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// View Interface

Add_View :: (v: Viewport, top_layer: *ViewLayer = null, parent_id := -1, replace_child_id := -1) -> s64 {
    if parent_id < 0 {
        // must be root
        assert(Is_Empty(*view_pool));
        assert(Is_Empty(*view_layer_pool));
    }

    view_id := Request_Item(*view_pool);
    view := Get_Item(*view_pool, view_id);
    view.viewport = v;
    view.children.data = view.children_buffer.data;
    view.layers.data = null;
    view.layers.count = 0;

    // a view only has layers if it is meant to be rendered. empty views are parents to other views that are rendered.
    view_layers_id := -1;
    if top_layer != null {
        view_layers_id = Request_Item(*view_layer_pool);
        view_layers_chunk := Get_Item(*view_layer_pool, view_layers_id); 
        view.layers.data = view_layers_chunk.items.data;
        Add_View_Layer(view, top_layer);
        view.active_layer = 0;
    }

    if parent_id >= 0 {
        parent := Get_Item(*view_pool, parent_id);
        assert(parent.children.count < VIEW_CHILDREN_MAX);
        if replace_child_id == -1 {
            parent.children.count += 1;
            parent.children[parent.children.count-1] = xx view_id;
        } else {
            found_replacement := false;
            for *parent.children {
                if it.* == replace_child_id {
                    it.* = xx view_id;
                    found_replacement = true;
                    break;
                }
            }
            assert(found_replacement);
        }
    }
    return view_id;
}

Add_View_Layer :: (v: *View, layer: *ViewLayer) {
    assert(v.layers.count < VIEW_LAYERS_MAX);
    i := v.layers.count;
    v.layers.count += 1;
    v.layers[i] = layer.*;
    v.layers[i].id = view_layer_id_counter;
    view_layer_id_counter += 1;
}

Split_View :: (v: *View, direction: SplitDirection, set_as_active := true, new_proportion := 0.5) -> *View {
    parent_id := Find_Parent(v);
    assert(parent_id != -1);
    assert(new_proportion >= 0 && new_proportion <= 1);
    parent := Get_Item(*view_pool, parent_id);
    // can't split a thing that doesn't present visually
    assert(v.active_layer < v.layers.count);

    new_view_id: s64;
    layer_copy: ViewLayer;
    layer_copy = v.layers[v.active_layer];

    if parent.children.count == 1 {
        v.viewport = .{};
    } else if parent.children.count == 2 {
        parent_id = Reparent_To_Empty(v);
    } else {
        // splitting is designed as 1-2 views staged on an empty parent. 0 or > 2 is invalid
        assert(false);
    }

    new_view_id = Add_View(.{}, *layer_copy, parent_id);
    if set_as_active {
        Push_Active_View_ID(new_view_id);
    }
    new_view := Get_Item(*view_pool, new_view_id);

    complement_proportion := 1.0 - new_proportion;
    if direction == .VERTICAL {
        v.viewport.top = complement_proportion;
        new_view.viewport.bottom = new_proportion;
    } else {
        v.viewport.left = complement_proportion;
        new_view.viewport.right = new_proportion;
    }
    return new_view;
}

Process_Text_Input :: (utf32: []u32) -> bool {
    if utf32.count == 0 then return false;
    active_view_layer := Active_View_Layer();
    if active_view_layer != null {
        if active_view_layer.type == {
        case .FILE_EDITOR;
            Process_Text_Input(*active_view_layer.file_editor, utf32);
            return true;
        case .FILE_EXPLORER;
            Process_Text_Input(*active_view_layer.file_explorer, utf32);
            return true;
        case .PROJECT_EXPLORER;
            // Project browsing is intentionally navigation-only. Configuration
            // files open in a regular editor before they can be modified.
            return true;
        case .VIM_CONSOLE;
            return false;
        }
    }
    return true;
}

View_Layer_Soft_Reset :: (layer: *ViewLayer) {
    cursor := Layer_Cursor(layer);
    if cursor then cursor.* = .{};
    layer.view_position = .{};
}

Center_View_On_Cursor :: (layer: *ViewLayer, y_max: float, renderer: *TextRenderer = null) {
    layer_cursor := Layer_Cursor(layer);
    if layer_cursor == null {
        return;
    }
    backup_renderer: TextRenderer;
    if renderer == null {
        renderer = *backup_renderer;
        Initialize_Text_Renderer(renderer, layer);
    }
    half_view_line_count := cast(float)(renderer.line_count / 2);
    layer.view_position.y = clamp(cast(float)layer_cursor.y - half_view_line_count, 0, y_max);
}

Clear_View :: (id: s64) {
    view := Get_Item(*view_pool, id);
    for view.children {
        Clear_View(it);
    }
    if view.layers.data != null {
        layer_chunk_id := Get_Item_Index(*view_layer_pool, xx view.layers.data);
        Return_Item(*view_layer_pool, layer_chunk_id);
        view.layers.data = null;
        view.layers.count = 0;
    }
    Return_Item(*view_pool, id, .DISALLOW);
}

Find_Valid_Child_View_To_Make_Active :: (parent: *View) -> s64 {
    for child_id : parent.children {
        child := Get_Item(*view_pool, child_id);
        if child.layers.data == null {
            assert(child.children.count > 0);
            return Find_Valid_Child_View_To_Make_Active(child);
        } else {
            return child_id;
        }
    }
    return -1;
}

Count_Layers_Of_Type :: (v: *View, type: ViewLayerType, recursive: bool) -> s64 {
    count := 0;
    for v.layers {
        if it.type == type then count += 1;
    }
    if recursive then for v.children {
        count += Count_Layers_Of_Type(*view_pool.items[it], type, true);
    }
    return count;
}

// TODO: using dependent id to clean up active view is messy
Close_View :: (id: s64, dependent_id := -1) {
    assert(id != tool_view_id);
    parent_id := Find_Parent(id);
    parent := Get_Item(*view_pool, parent_id);
    assert(parent.children.count > 0);

    total_file_editor_count := Count_Layers_Of_Type(*view_pool.items[base_empty_view_id], .FILE_EDITOR, true);
    view_file_editor_count := Count_Layers_Of_Type(*view_pool.items[id], .FILE_EDITOR, true);
    new_file_editor_count := total_file_editor_count - view_file_editor_count;

    if new_file_editor_count <= 0 {
        quit = true;
    } else {
        Clear_View(id);

        for 0..parent.children.count-1 {
            child := parent.children[it];
            if child == id {
                if it != parent.children.count-1 {
                    parent.children[it] = parent.children[parent.children.count-1];
                } 
                parent.children.count -= 1;
                if parent.active_layer == it {
                    parent.active_layer = 0;
                }
                break;
            }
        }

        if parent.children.count == 0 {
            Close_View(parent_id, id);
        } else {
            assert(parent.children.count == 1);

            child := Get_Item(*view_pool, parent.children[0]);
            valid_active_id := Find_Valid_Child_View_To_Make_Active(parent);
            assert(valid_active_id != -1);

            if parent_id == base_empty_view_id {
                // The workspace staging node has a stable global ID and must
                // survive after its final split is closed.
                child.viewport = .{inverted=true};
            } else {
                parent_of_parent := Get_Parent(parent);
                replaced_parent_with_child := false;
                if parent_of_parent != null {
                    for *parent_of_parent.children {
                        if it.* == parent_id {
                            child.viewport = parent.viewport;
                            it.* = parent.children[0];
                            parent.children.count = 0;
                            Clear_View(parent_id);
                            replaced_parent_with_child = true;
                            break;
                        }
                    }
                }
                assert(replaced_parent_with_child);
            }

            for *editor_view_stack {
                if it.* == id || it.* == dependent_id {
                    it.* = valid_active_id;
                }
            }
        }
    }
}

Close_Text_Buffer :: (id: s64) {
    buffer := *file_buffers.items[id];
    Shutdown_Text_Buffer(buffer); 
    Return_Item(*file_buffers, id);

    valid_id := Find_Valid_File_Editor_Buffer(id, true);
    if valid_id == -1 {
        intro_file_name := Prepare_Intro_File();
        valid_id = Get_File_Buffer_ID(intro_file_name);
        assert(valid_id != -1);
    }

    IDPair :: struct {
        invalid_buffer_id: s64;
        valid_buffer_id: s64;
    } 
    Replace_Invalid_File_Buffer :: (v: *View, view_id: s64, viewport_id: s64, id_pair: *IDPair) {
        for *v.layers {
            if it.type == .FILE_EDITOR && it.file_editor.file_buffer == id_pair.invalid_buffer_id {
                 it.file_editor.file_buffer = id_pair.valid_buffer_id;
            }
        }
    }

    id_pair := IDPair.{id, valid_id};
    Walk_View_Tree(0, Replace_Invalid_File_Buffer, *id_pair, false);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Update_Views :: () {
//     // not a whole lot happening here rn...
//     if Active_View_Layer().type == .FILE_EDITOR {

//     }
// }

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Custom_Title_Bar_Display_Text :: () -> string {
    if Is_Empty(*view_pool) || editor_view_stack.count == 0 {
        return "";
    }
    layer := Active_View_Layer();
    if layer != null {
        if layer.type == {
        case .FILE_EXPLORER;
            if layer.file_explorer.directory.count > 0 {
                return layer.file_explorer.directory;
            }
        case .PROJECT_EXPLORER;
            if layer.project_explorer.directory.count > 0 {
                return layer.project_explorer.directory;
            }
        case;
        }
        buffer := Layer_Text_Buffer(layer);
        if buffer != null && buffer.file_path.count > 0 {
            return buffer.file_path;
        }
    }

    // Command bars and tool layers may temporarily own input. Keep the most
    // recently selected editor path visible instead of blanking the title.
    stack_index := editor_view_stack.count;
    while stack_index > 0 {
        stack_index -= 1;
        view_id := editor_view_stack[stack_index];
        if view_id < 0 || !Is_Item_In_Use(*view_pool, view_id) {
            continue;
        }
        view := View_From_ID(view_id);
        editor_layer := Active_Layer_Of_View(view);
        if editor_layer == null || editor_layer.type != .FILE_EDITOR {
            continue;
        }
        buffer := Layer_Text_Buffer(editor_layer);
        if buffer != null && buffer.file_path.count > 0 {
            return buffer.file_path;
        }
    }
    if project_state.main_directory.count > 0 {
        return project_state.main_directory;
    }
    working_directory := get_working_directory();
    Convert_To_Forward_Slashes(working_directory);
    return working_directory;
}

Custom_Title_Bar_Elide_From_Left :: (text: string, maximum_character_count: s32) -> string {
    if maximum_character_count <= 0 {
        return "";
    }
    if text.count <= cast(s64)maximum_character_count {
        return text;
    }
    if maximum_character_count <= 3 {
        return "...";
    }
    suffix_count := cast(s64)(maximum_character_count - 3);
    suffix := string.{suffix_count, text.data + text.count - suffix_count};
    return tprint("...%", suffix);
}

Render_Custom_Title_Bar :: (render_pass: ViewRenderPass) {
    title_bar_height := min(Custom_Title_Bar_Height(), max(window.height, 0));
    if title_bar_height <= 0 || window.width <= 0 {
        return;
    }
    button_width := Custom_Title_Bar_Button_Width();
    title_bar_ul: IntVector2 = .{0, 0};
    title_bar_lr: IntVector2 = .{window.width, title_bar_height};

    if render_pass == {
    case .BACKGROUND;
        Render_Quad(title_bar_ul, title_bar_lr, .{0.035, 0.19, 0.245, 1.0});
        for button: CustomTitleBarButton.MINIMIZE..CustomTitleBarButton.CLOSE {
            ul, lr := Custom_Title_Bar_Button_Rect(button, window.width, title_bar_height, button_width);
            color := fRGBA.{0.015, 0.12, 0.17, 1.0};
            if Custom_Title_Bar_Hovered_Button() == button {
                color = ifx button == .CLOSE
                    then fRGBA.{0.72, 0.10, 0.15, 1.0}
                    else fRGBA.{0.09, 0.27, 0.32, 1.0};
            }
            if Custom_Title_Bar_Pressed_Button() == button
            && Custom_Title_Bar_Hovered_Button() == button {
                color = ifx button == .CLOSE
                    then fRGBA.{0.56, 0.07, 0.11, 1.0}
                    else fRGBA.{0.06, 0.21, 0.26, 1.0};
            }
            Render_Quad(ul, lr, color);
        }
    case .LINES;
        border_color := fRGBA.{0.22, 0.35, 0.39, 0.72};
        Render_Line(.{0, title_bar_height-1}, .{window.width, title_bar_height-1}, border_color);
        for button: CustomTitleBarButton.MINIMIZE..CustomTitleBarButton.CLOSE {
            ul, lr := Custom_Title_Bar_Button_Rect(button, window.width, title_bar_height, button_width);
            Render_Line(ul, .{ul.x, lr.y}, border_color);

            center: IntVector2 = .{(ul.x+lr.x)/2, (ul.y+lr.y)/2};
            glyph_half := max((title_bar_height * 5) / (CUSTOM_TITLE_BAR_HEIGHT_96 * 2), 4);
            glyph_color := fRGBA.{0.78, 0.84, 0.85, 0.95};
            if Custom_Title_Bar_Hovered_Button() == button {
                glyph_color = .{0.93, 0.96, 0.96, 1.0};
            }
            if button == {
            case .MINIMIZE;
                glyph_y := center.y + glyph_half / 2;
                Render_Line(.{center.x-glyph_half, glyph_y}, .{center.x+glyph_half, glyph_y}, glyph_color);
            case .MAXIMIZE;
                Render_Quad_Lines(
                    .{center.x-glyph_half, center.y-glyph_half},
                    .{center.x+glyph_half, center.y+glyph_half},
                    glyph_color,
                );
            case .CLOSE;
                Render_Line(
                    .{center.x-glyph_half, center.y-glyph_half},
                    .{center.x+glyph_half, center.y+glyph_half},
                    glyph_color,
                );
                Render_Line(
                    .{center.x+glyph_half, center.y-glyph_half},
                    .{center.x-glyph_half, center.y+glyph_half},
                    glyph_color,
                );
            case;
            }
        }
    case .TEXT;
        identity_x := max((10 * title_bar_height) / CUSTOM_TITLE_BAR_HEIGHT_96, 6);
        identity := "vai";
        path_x := identity_x + cast(s32)(identity.count + 2) * Width(font);
        controls_left := max(window.width - button_width*3, 0);
        available_path_width := max(controls_left - path_x - 8, 0);
        available_path_characters := ifx Width(font) > 0 then available_path_width / Width(font) else 0;
        path := "title-bar-path-probe";
        line_height: s32 = xx (get_baseline_height(font) * 4);
        text_y := max((title_bar_height + line_height) / 2, line_height);

        saved_scissor_ul := rendering_scissor_ul;
        saved_scissor_lr := rendering_scissor_lr;
        rendering_scissor_ul = title_bar_ul;
        rendering_scissor_lr = .{controls_left, title_bar_height};
        Set_Scissor(rendering_scissor_ul, rendering_scissor_lr);
        Render_Text_String_At(identity, identity_x, text_y, .{0.78, 0.86, 0.87, 0.96});
        if path.count > 0 {
            Render_Text_String_At(path, path_x, text_y, .{0.46, 0.55, 0.57, 0.88});
        }
        rendering_scissor_ul = saved_scissor_ul;
        rendering_scissor_lr = saved_scissor_lr;
        Set_Scissor(rendering_scissor_ul, rendering_scissor_lr);
    case;
    }
}

Render_Views :: (full_update: bool) {
    Begin_Draw_Frame(full_update);
    defer End_Draw_Frame();
    debug_view_open = Count_Layers_Of_Type(*view_pool.items[ROOT_ID], .DEBUG, true) > 0;
    if Is_Empty(*view_pool) then return;
    Collapse_Views_At_Or_Below_Bar_Size();
    Refresh_Collapsed_View_Bar_Proportions();
    
    if full_update {
        // walking the view tree multiple times because tree traversal is pretty cheap + number of draw calls can be reduced by grouping draws into natural batches (background rects, lines, text, etc..)
        Set_Shader_For_Blended_Color();
        Render_Custom_Title_Bar(.BACKGROUND);
        Walk_View_Tree(0, Render_View, ViewRenderPass.BACKGROUND);
        Render_Mouse_View_Resize_Interface();
        Flush_Draws();
        Set_Shader_For_Lines();
        Render_Custom_Title_Bar(.LINES);
        Walk_View_Tree(0, Render_View, ViewRenderPass.LINES);
        Flush_Draws();
        // Set_Shader_For
        // Walk_View_Tree(0, Render_View, ViewRenderPass.IMAGES);
        Set_Shader_For_Text();
        Render_Custom_Title_Bar(.TEXT);
        Walk_View_Tree(0, Render_View, ViewRenderPass.TEXT);
        Flush_Draws();
        // it's the responsibility of the render proc to set the shader when doing foreground rendering
        Walk_View_Tree(0, Render_View, ViewRenderPass.FOREGROUND);
        Flush_Draws();
    } else {
        Copy_Previous_Render_Target();
        Walk_View_Tree(0, Render_Partial_Update, cast(*void)null);
    }
}

Render_View :: (view: *View, view_id: s64, viewport_id: s64, render_pass: ViewRenderPass) {
    rect := viewport_rects[viewport_id];
    rendering_scissor_ul, rendering_scissor_lr = Viewport_Rect_Points(*rect, s32);
    if render_pass == .BACKGROUND {
        view.pixel_dimensions.x = rendering_scissor_lr.x - rendering_scissor_ul.x;
        view.pixel_dimensions.y = rendering_scissor_lr.y - rendering_scissor_ul.y;
    }
    if rendering_scissor_lr.x <= rendering_scissor_ul.x
    || rendering_scissor_lr.y <= rendering_scissor_ul.y {
        return;
    }

    if View_Has_Hidden_Group_Ancestor(view_id) {
        return;
    }

    if view.hidden_group {
        Flush_Draws();
        if render_pass == .TEXT || render_pass == .FOREGROUND {
            Set_Scissor(rendering_scissor_ul, rendering_scissor_lr);
        }
        Render_Hidden_View_Group(view, view_id, render_pass);
        return;
    }

    if view.hidden {
        Flush_Draws();
        if render_pass == .TEXT || render_pass == .FOREGROUND {
            Set_Scissor(rendering_scissor_ul, rendering_scissor_lr);
        }
        Render_Collapsed_View_Tab(view, view_id == Active_View_ID(), render_pass);
        return;
    }

    if view.layers.data != null {

        Flush_Draws();

        if render_pass == {
        // case .BACKGROUND;   #through;
        case .IMAGES;       #through;
        case .TEXT;         #through;
        case .FOREGROUND;
            // during these render passes, views must make sure their draws are dispatched while this scissor is set
            Set_Scissor(rendering_scissor_ul, rendering_scissor_lr);
        }
        // the rest of the passes use the entire window as their scissor and their draws are dispatched at the end of the pass

        view_layer := *view.layers[view.active_layer];
        if view_layer.type == .DEBUG {
            a := 0;
        }
        view_active := view_id == Active_View_ID();
        if view_active {
            if render_pass == .BACKGROUND {
                bounds_ul, bounds_lr := View_Bounds(view_layer);
                scroll_speed := settings_file_data.arrow_key_scroll_speed; 
                if Is_Virtual_Key_Pressed(.UP) {
                    Scroll_View_Up(view_layer, bounds_ul.y, scroll_speed);
                } 
                if Is_Virtual_Key_Pressed(.DOWN) {
                    Scroll_View_Down(view_layer, bounds_lr.y, scroll_speed);
                }
                if Is_Virtual_Key_Pressed(.LEFT) {
                    Scroll_View_Left(view_layer, bounds_ul.x, scroll_speed);
                } 
                if Is_Virtual_Key_Pressed(.RIGHT) {
                    Scroll_View_Right(view_layer, bounds_lr.x, scroll_speed);
                }
            }
        }
        #insert #run Generate_View_Layer_Switch("Render_Layer(%, view_active, render_pass);");
        if view_active && render_pass == .BACKGROUND && vi_mode == .RESIZE_VIEW {
            Render_Resize_View_Interface();
        }
    }
}

Get_Active_View_Side :: (side: Side2D, inside_buffer: s32 = 0) -> begin: IntVector2, end: IntVector2 {
    begin, end := rendering_scissor_ul, rendering_scissor_lr;
    if side == {
    case .LEFT;
        end.x = begin.x + inside_buffer;
    case .RIGHT;
        begin.x = end.x - inside_buffer;
    case .TOP;
        end.y = begin.y + inside_buffer;
    case .BOTTOM;
        begin.y = end.y - inside_buffer;
    }
    return begin, end;
}

Render_Resize_View_Interface :: () {
    begin, end := Get_Active_View_Side(selected_view_side, 8);

    whole_view_color := fRGBA.{0.7, 0.6, 0.5, 0.1};
    Render_Quad(rendering_scissor_ul, rendering_scissor_lr, whole_view_color);

    Render_Quad(begin, end, Resize_View_Interface_Side_Color());
}

Resize_View_Interface_Side_Color :: () -> fRGBA {
    sin_xt := cast(float) sin(seconds_since_init() * 2.69);
    alpha := Respace(sin_xt, .{-1.0, 1.0}, .{0.25, 0.6});
    return .{0.9, 0.45, 0.6, alpha};
}

Render_Mouse_View_Resize_Interface :: () {
    edge: [2]*View;
    side: Side2D;
    found_edge := false;

    if mouse_interaction.active && mouse_interaction.mode == .VIEW_EDGE {
        edge = mouse_interaction.edge;
        side = mouse_interaction.edge_side;
        found_edge = View_Edge_Is_Live(*edge);
    } else if !mouse_left_button_down && mouse_hover_position_is_known {
        hit := Find_Mouse_View_Hit(mouse_hover_position);
        if hit.view != null && !hit.view.hidden {
            edge, side, found_edge = Find_Mouse_View_Resize_Edge(hit, mouse_hover_position);
        }
    }
    if !found_edge {
        return;
    }

    edge_view_id := edge[0] - view_pool.items.data;
    rect, found_rect := Find_View_Screen_Rect(edge_view_id, ROOT_ID, Window_Viewport_Rect());
    if !found_rect {
        return;
    }
    begin, end := Viewport_Rect_Points(*rect, s32);
    band_width := min(sdw(8), ifx side == .LEFT || side == .RIGHT
        then max(end.x - begin.x, 0)
        else max(end.y - begin.y, 0));
    if band_width <= 0 {
        return;
    }

    if side == {
    case .LEFT;
        end.x = begin.x + band_width;
    case .RIGHT;
        begin.x = end.x - band_width;
    case .TOP;
        end.y = begin.y + band_width;
    case .BOTTOM;
        begin.y = end.y - band_width;
    }
    Render_Quad(begin, end, Resize_View_Interface_Side_Color());
}

Collapsed_View_Bar_Thickness :: (side: Side2D) -> s32 {
    if collapsed_view_bar_thickness_for_tests > 0 {
        return collapsed_view_bar_thickness_for_tests;
    }
    if side == .LEFT || side == .RIGHT {
        return max(Width(font) + 10, sdw(18));
    }
    line_height: s32 = xx (get_baseline_height(font) * 4);
    line_height += xx (cast(float32)line_height * line_spacing_factor);
    return max(line_height + 8, sdw(20));
}

Collapsed_View_Label :: (view: *View) -> string {
    layer := Active_Layer_Of_View(view);
    if layer == null {
        return "view";
    }
    if layer.type == .FILE_EDITOR {
        buffer := Layer_Text_Buffer(layer);
        if buffer != null && buffer.file_path.count > 0 {
            success, unused, name := split_from_right(buffer.file_path, #char "/");
            if !success {
                success, unused, name = split_from_right(buffer.file_path, #char "\\");
            }
            if success && name.count > 0 {
                return name;
            }
            return buffer.file_path;
        }
        return "untitled";
    }
    if layer.type == {
    case .FILE_EXPLORER;
        return "file explorer";
    case .PROJECT_EXPLORER;
        return "project explorer";
    case .OS_CONSOLE;
        return "console";
    case .DEBUG;
        return "debug";
    case;
    }
    return "view";
}

Render_Collapsed_View_Tab :: (view: *View, is_active: bool, render_pass: ViewRenderPass) {
    Render_Collapsed_Tab(Collapsed_View_Label(view), view.hidden_side, is_active, render_pass);
}

Render_Collapsed_Tab :: (label: string, side: Side2D, is_active: bool, render_pass: ViewRenderPass) {
    Render_Collapsed_Tab_In_Rect(label, side, is_active, render_pass, rendering_scissor_ul, rendering_scissor_lr);
}

Render_Collapsed_Tab_In_Rect :: (label: string, side: Side2D, is_active: bool, render_pass: ViewRenderPass, ul: IntVector2, lr: IntVector2) {
    if lr.x <= ul.x || lr.y <= ul.y {
        return;
    }

    if render_pass == {
    case .BACKGROUND;
        background := ifx is_active
            then fRGBA.{0.22, 0.34, 0.39, 1.0}
            else fRGBA.{0.06, 0.20, 0.25, 1.0};
        Render_Quad(ul, lr, background);
    case .LINES;
        alpha := ifx is_active then 0.95 else 0.45;
        Render_Quad_Lines(ul, lr, .{rgb=fRGB_WHITE, a=alpha});
    case .TEXT;
        color := ifx is_active
            then fRGBA.{rgb=fRGB_WHITE, a=1.0}
            else fRGBA.{rgb=fRGB_WHITE, a=0.65};
        line_height: s32 = xx (get_baseline_height(font) * 4);
        line_height += xx (cast(float32)line_height * line_spacing_factor);
        vertical := side == .LEFT || side == .RIGHT;
        if vertical {
            x := ul.x + max(((lr.x - ul.x) - Width(font)) / 2, 1);
            y := ul.y + line_height;
            stacked_letter_spacing := max((line_height * 3) / 4, sdw(1));
            for 0..label.count-1 {
                if y > lr.y {
                    break;
                }
                character := string.{1, label.data + it};
                Render_Text_String_At(character, x, y, color);
                y += stacked_letter_spacing;
            }
        } else {
            Render_Text_String_At(label, ul.x + 6, ul.y + line_height, color);
        }
    case;
    }
}

Collect_Hidden_Leaf_View_IDs :: (view_id: s64, view_ids: *[..]s64) {
    if View_ID_Is_Selectable(view_id) {
        view := View_From_ID(view_id);
        if view.hidden {
            array_add(view_ids, view_id);
        }
        return;
    }
    view := View_From_ID(view_id);
    for view.children {
        Collect_Hidden_Leaf_View_IDs(it, view_ids);
    }
}

Hidden_Group_Shelf_Side :: (view: *View) -> Side2D {
    return ifx view.hidden_group_collapsed then view.hidden_group_side else .TOP;
}

Hidden_Group_Tab_Rect :: (group_ul: IntVector2, group_lr: IntVector2, side: Side2D, tab_index: s64, tab_count: s64) -> IntVector2, IntVector2 {
    shelf_ul := group_ul;
    shelf_lr := group_lr;
    vertical := side == .LEFT || side == .RIGHT;
    if !vertical {
        shelf_lr.y = min(shelf_lr.y, shelf_ul.y + Collapsed_View_Bar_Thickness(.TOP));
        width := max(shelf_lr.x - shelf_ul.x, 0);
        tab_ul: IntVector2 = .{shelf_ul.x + xx (cast(s64)width * tab_index / tab_count), shelf_ul.y};
        tab_lr: IntVector2 = .{shelf_ul.x + xx (cast(s64)width * (tab_index + 1) / tab_count), shelf_lr.y};
        return tab_ul, tab_lr;
    }

    shelf_lr.x = min(shelf_lr.x, shelf_ul.x + Collapsed_View_Bar_Thickness(.LEFT));
    height := max(shelf_lr.y - shelf_ul.y, 0);
    tab_ul: IntVector2 = .{shelf_ul.x, shelf_ul.y + xx (cast(s64)height * tab_index / tab_count)};
    tab_lr: IntVector2 = .{shelf_lr.x, shelf_ul.y + xx (cast(s64)height * (tab_index + 1) / tab_count)};
    return tab_ul, tab_lr;
}

Render_Hidden_View_Group :: (group: *View, group_id: s64, render_pass: ViewRenderPass) {
    hidden_view_ids: [..]s64;
    hidden_view_ids.allocator = temp;
    Collect_Hidden_Leaf_View_IDs(group_id, *hidden_view_ids);
    if hidden_view_ids.count == 0 {
        return;
    }

    group_ul := rendering_scissor_ul;
    group_lr := rendering_scissor_lr;
    side := Hidden_Group_Shelf_Side(group);
    for hidden_view_ids {
        tab_ul, tab_lr := Hidden_Group_Tab_Rect(group_ul, group_lr, side, it_index, hidden_view_ids.count);
        hidden_view := View_From_ID(it);
        Render_Collapsed_Tab_In_Rect(Collapsed_View_Label(hidden_view), side, it == Active_View_ID(), render_pass, tab_ul, tab_lr);
    }

    if group.hidden_group_collapsed {
        return;
    }

    shelf_height := Collapsed_View_Bar_Thickness(.TOP);
    empty_ul: IntVector2 = .{group_ul.x, min(group_ul.y + shelf_height, group_lr.y)};
    empty_lr := group_lr;
    if empty_lr.x <= empty_ul.x || empty_lr.y <= empty_ul.y {
        return;
    }

    if render_pass == {
    case .BACKGROUND;
        Render_Quad(empty_ul, empty_lr, .{rgb=file_editor_background_color, a=1.0});
        dot_color := fRGBA.{0.405, 0.485, 0.51, 0.26};
        dot_step := max(sdw(18), 8);
        dot_size := max(sdw(2), 2);
        dot_center := IntVector2.{(empty_ul.x+empty_lr.x)/2, (empty_ul.y+empty_lr.y)/2};
        feather_radius := cast(float)min(empty_lr.x-empty_ul.x, empty_lr.y-empty_ul.y);
        feather_inner := feather_radius * 0.10;
        feather_outer := feather_radius * 0.42;
        y := empty_ul.y + dot_step / 2;
        row: s32;
        while y < empty_lr.y {
            x := empty_ul.x + dot_step / 2 + (row % 2) * (dot_step / 2);
            while x < empty_lr.x {
                feather := Circular_Feather_From_Center(.{x, y}, dot_center, feather_inner, feather_outer);
                if feather > 0.01 {
                    color := dot_color;
                    color.a *= feather;
                    Render_Quad(.{x, y}, .{min(x + dot_size, empty_lr.x), min(y + dot_size, empty_lr.y)}, color);
                }
                x += dot_step;
            }
            y += dot_step;
            row += 1;
        }
    case .LINES;
        center_x := (empty_ul.x + empty_lr.x) / 2;
        center_y := (empty_ul.y + empty_lr.y) / 2 - sdw(18);
        icon_half_width := max(sdw(18), 10);
        icon_half_height := max(sdw(14), 8);
        icon_ul: IntVector2 = .{center_x - icon_half_width, center_y - icon_half_height};
        icon_lr: IntVector2 = .{center_x + icon_half_width, center_y + icon_half_height};
        icon_color := fRGBA.{0.46, 0.52, 0.54, 0.55};
        Render_Quad_Lines(icon_ul, icon_lr, icon_color);
        header_y := icon_ul.y + max(sdw(8), 4);
        Render_Line(.{icon_ul.x, header_y}, .{icon_lr.x, header_y}, icon_color);
        x_center := icon_lr.x - max(sdw(7), 4);
        x_half := max(sdw(3), 2);
        Render_Line(.{x_center - x_half, icon_ul.y + max(sdw(2), 1)}, .{x_center + x_half, header_y - max(sdw(2), 1)}, icon_color);
        Render_Line(.{x_center + x_half, icon_ul.y + max(sdw(2), 1)}, .{x_center - x_half, header_y - max(sdw(2), 1)}, icon_color);
    case .TEXT;
        show_input := Mapped_Input_For_Action(.SHOW_ACTIVE_VIEW, .NORMAL);
        if show_input.count == 0 {
            show_input = "show";
        }
        hint := tprint("Select a hidden view's tab then show it with %", show_input);
        line_height: s32 = xx (get_baseline_height(font) * 4);
        line_height += xx (cast(float32)line_height * line_spacing_factor);
        hint_width := xx hint.count * Width(font);
        hint_x := max(empty_ul.x + (empty_lr.x - empty_ul.x - hint_width) / 2, empty_ul.x + 4);
        hint_y := (empty_ul.y + empty_lr.y) / 2 + sdw(18) + line_height;
        Render_Text_String_At(hint, hint_x, min(hint_y, empty_lr.y - 2), .{0.48, 0.53, 0.55, 0.68});
    case;
    }
}

Get_View_Edge :: (view: *View, side: Side2D) -> [2]*View, Side2D {
    success: bool;
    family: ViewFamily;
    view_id := view - view_pool.items.data;
    base_empty := *view_pool.items[base_empty_view_id];

    if base_empty.children.count == 1 && base_empty.children[0] == view_id {
        family.self = View_From_ID(tool_view_id);
        family.sibling = base_empty;
        side = Opposite(side);
        success = view != null && family.sibling != null;
    } else {
        family, success = Get_View_Family(view);
    }

    side_opposite := Opposite(side);

    edge: [2]*View;
    if !success {
        return edge, side;
    }
    if (family.self.viewport.offsets[side_opposite] != 0 || family.sibling.viewport.offsets[side] != 0) {
        return .[family.self, family.sibling], side;
    }

    cur_view := view;
    // search upward until find parent that has a opposite-side component, or if all zeroes, sibling has a correct-side component. this represents having found the pair of views that determines the placement of an edge.
    ITER_LIMIT :: 1000;
    iter_ct := 0;
    while (iter_ct < ITER_LIMIT) {
        family, success := Get_View_Family(cur_view);
        if !success then break;
        if family.parent.viewport.offsets[side_opposite] != 0 {
            family_of_parent, success := Get_View_Family(family.parent);                
            edge[0] = family.parent;
            edge[1] = family_of_parent.sibling;
            break;
        }
        cur_view = family.parent;
        iter_ct += 1;
    }

    return edge, side;
}

Move_View_Edge :: (edge: *[2]*View, side: Side2D, direction: Side2D) {
    side_opposite := Opposite(side);

    view_total_side_length: s32;
    if side == .LEFT || side == .RIGHT {
        view_total_side_length = edge.*[0].pixel_dimensions.x + edge.*[1].pixel_dimensions.x;
    } else {
        view_total_side_length = edge.*[0].pixel_dimensions.y + edge.*[1].pixel_dimensions.y;
    }

    font_width := Width(font);
    pixel_move_speed := font_width;
    norm_speed := cast(float)pixel_move_speed / view_total_side_length;

    dir := ifx direction == side_opposite then -1.0 else 1.0;
    delta := dir * norm_speed;
    start_proportion := edge.*[0].viewport.offsets[side_opposite];
    Resize_View_Edge_To_Proportion(edge, side, start_proportion + delta, start_proportion, 1.0 - start_proportion);
}

Balance_View_Edge :: (edge: *[2]*View, side: Side2D, proportion: float) {
    assert(proportion >= 0 && proportion <= 1);
    side_opposite := Opposite(side);

    edge.*[0].viewport.offsets[side_opposite] = proportion;
    edge.*[1].viewport.offsets[side] = 1 - proportion;

    view_ids := s64.[edge.*[0] - view_pool.items.data, edge.*[1] - view_pool.items.data];    
    if view_ids[0] == tool_view_id {
        settings_file_data.tool_view_screen_proportion = edge.*[0].viewport.offsets[side_opposite];
    } else if view_ids[1] == tool_view_id {
        settings_file_data.tool_view_screen_proportion = edge.*[1].viewport.offsets[side];
    }
}

Get_Direct_View_Split_Edge :: (view: *View) -> edge: [2]*View, side: Side2D, success: bool {
    empty_edge: [2]*View;
    parent := Get_Parent(view);
    if parent == null || parent.children.count < 2 {
        return empty_edge, .LEFT, false;
    }

    family, found_family := Get_View_Family(view);
    if !found_family {
        return empty_edge, .LEFT, false;
    }

    if view.viewport.left > 0.0 && family.sibling.viewport.right > 0.0 {
        return .[view, family.sibling], .RIGHT, true;
    }
    if view.viewport.right > 0.0 && family.sibling.viewport.left > 0.0 {
        return .[view, family.sibling], .LEFT, true;
    }
    if view.viewport.top > 0.0 && family.sibling.viewport.bottom > 0.0 {
        return .[view, family.sibling], .BOTTOM, true;
    }
    if view.viewport.bottom > 0.0 && family.sibling.viewport.top > 0.0 {
        return .[view, family.sibling], .TOP, true;
    }
    return empty_edge, .LEFT, false;
}

View_ID_Is_Selectable :: (view_id: s64) -> bool {
    if view_id < 0 || view_id == ROOT_ID || view_id == vim_console_id {
        return false;
    }
    if !Is_Item_In_Use(*view_pool, view_id) {
        return false;
    }
    return view_pool.items[view_id].layers.count > 0;
}

View_ID_Has_Tab_Or_Content :: (view_id: s64) -> bool {
    if !View_ID_Is_Selectable(view_id) {
        return false;
    }
    view := *view_pool.items[view_id];
    if view.hidden {
        return true;
    }
    if view_id == tool_view_id && view.viewport.left <= 0.0 {
        return false;
    }
    return true;
}

Find_Visible_Selectable_View_ID :: (from_view_id: s64, excluding_view_id: s64) -> s64 {
    view := *view_pool.items[from_view_id];
    if from_view_id != excluding_view_id
    && View_ID_Is_Selectable(from_view_id)
    && !view.hidden
    && (from_view_id != tool_view_id || view.viewport.left > 0.0) {
        return from_view_id;
    }
    for view.children {
        found := Find_Visible_Selectable_View_ID(it, excluding_view_id);
        if found >= 0 {
            return found;
        }
    }
    return -1;
}

Set_Direct_View_Split_Proportion :: (view: *View, sibling: *View, side: Side2D, proportion: float) {
    side_opposite := Opposite(side);
    view.viewport.offsets[side_opposite] = clamp(proportion, 0.0001, 0.9999);
    sibling.viewport.offsets[side] = 1.0 - view.viewport.offsets[side_opposite];
}

View_Split_Parent_Axis_Length :: (view: *View, side: Side2D) -> s32 {
    parent_id := Find_Parent(view);
    if parent_id < 0 {
        return sdw(1);
    }
    parent_rect, found := Find_View_Screen_Rect(parent_id, ROOT_ID, Window_Viewport_Rect());
    if !found {
        return sdw(1);
    }
    return max(ifx side == .LEFT || side == .RIGHT
        then parent_rect.dimensions.x
        else parent_rect.dimensions.y, sdw(1));
}

Collapsed_View_Bar_Proportion :: (side: Side2D, total_length: s32) -> float {
    safe_total_length := max(total_length, sdw(1));
    // Viewport shaving rounds upward. Keeping the normalized target slightly
    // inside the desired integer size makes that ceil land on the exact bar
    // thickness across window sizes.
    target_pixels := max(cast(float)Collapsed_View_Bar_Thickness(side) - 0.25, 0.25);
    return clamp(target_pixels / cast(float)safe_total_length, 0.0001, 0.9999);
}

View_Has_Hidden_Group_Ancestor :: (view_id: s64) -> bool {
    parent_id := Find_Parent(view_id);
    while parent_id >= 0 {
        parent := View_From_ID(parent_id);
        if parent.hidden_group {
            return true;
        }
        parent_id = Find_Parent(parent_id);
    }
    return false;
}

Hidden_Subtree_State :: (view_id: s64) -> all_hidden: bool, selectable_leaf_count: s64 {
    if View_ID_Is_Selectable(view_id) {
        return View_From_ID(view_id).hidden, 1;
    }

    view := View_From_ID(view_id);
    all_descendants_hidden := true;
    leaf_count: s64;
    for view.children {
        child_all_hidden, child_leaf_count := Hidden_Subtree_State(it);
        if child_leaf_count > 0 {
            leaf_count += child_leaf_count;
            all_descendants_hidden = all_descendants_hidden && child_all_hidden;
        }
    }
    return all_descendants_hidden && leaf_count > 0, leaf_count;
}

View_Qualifies_As_Hidden_Group :: (view_id: s64) -> bool {
    view := View_From_ID(view_id);
    if view.layers.count > 0 || view.children.count < 2 {
        return false;
    }
    all_hidden, selectable_leaf_count := Hidden_Subtree_State(view_id);
    return all_hidden && selectable_leaf_count >= 2;
}

Collect_Maximal_Hidden_Group_IDs :: (view_id: s64, group_ids: *[..]s64) {
    if View_Qualifies_As_Hidden_Group(view_id) {
        array_add(group_ids, view_id);
        return;
    }
    view := View_From_ID(view_id);
    for view.children {
        Collect_Maximal_Hidden_Group_IDs(it, group_ids);
    }
}

Collect_Active_Hidden_Group_IDs :: (view_id: s64, group_ids: *[..]s64) {
    view := View_From_ID(view_id);
    if view.hidden_group {
        array_add(group_ids, view_id);
    }
    for view.children {
        Collect_Active_Hidden_Group_IDs(it, group_ids);
    }
}

View_ID_List_Contains :: (view_ids: []s64, view_id: s64) -> bool {
    for view_ids {
        if it == view_id {
            return true;
        }
    }
    return false;
}

Deactivate_Hidden_View_Group :: (group_id: s64) {
    group := View_From_ID(group_id);
    if group.hidden_group_collapsed {
        family, found_family := Get_View_Family(group);
        if found_family {
            Set_Direct_View_Split_Proportion(group, family.sibling, group.hidden_group_side, group.hidden_group_saved_proportion);
        }
    }
    group.hidden_group = false;
    group.hidden_group_collapsed = false;
}

Activate_Hidden_View_Group :: (group_id: s64) {
    group := View_From_ID(group_id);
    group.hidden_group = true;
    group.hidden_group_collapsed = false;
    group.hidden_group_side = .TOP;

    // The base editor split owns the full workspace. It keeps its height so it
    // can render a shelf plus the unmistakably empty dotted background.
    if group_id == base_empty_view_id {
        return;
    }

    edge, side, found_edge := Get_Direct_View_Split_Edge(group);
    if !found_edge {
        return;
    }

    side_opposite := Opposite(side);
    saved_proportion := group.viewport.offsets[side_opposite];
    total_length := View_Split_Parent_Axis_Length(group, side);
    bar_proportion := Collapsed_View_Bar_Proportion(side, total_length);

    group.hidden_group_collapsed = true;
    group.hidden_group_side = side;
    group.hidden_group_saved_proportion = clamp(saved_proportion, 0.01, 0.99);
    Set_Direct_View_Split_Proportion(group, edge[1], side, bar_proportion);

    sibling_id := edge[1] - view_pool.items.data;
    if View_ID_Is_Selectable(sibling_id) {
        edge[1].hidden_saved_proportion = 1.0 - group.hidden_group_saved_proportion;
    }
}

Reapply_Individual_Hidden_View_Layouts :: (view_id: s64) {
    view := View_From_ID(view_id);
    if View_ID_Is_Selectable(view_id) && view.hidden && !View_Has_Hidden_Group_Ancestor(view_id) {
        edge, side, found_edge := Get_Direct_View_Split_Edge(view);
        if found_edge && !edge[1].hidden && !edge[1].hidden_group {
            total_length := View_Split_Parent_Axis_Length(view, side);
            bar_proportion := Collapsed_View_Bar_Proportion(side, total_length);
            Set_Direct_View_Split_Proportion(view, edge[1], side, bar_proportion);
        }
        return;
    }
    for view.children {
        Reapply_Individual_Hidden_View_Layouts(it);
    }
}

Update_Hidden_View_Groups :: () {
    if !Is_Item_In_Use(*view_pool, base_empty_view_id) {
        return;
    }

    desired_group_ids: [..]s64;
    desired_group_ids.allocator = temp;
    active_group_ids: [..]s64;
    active_group_ids.allocator = temp;
    Collect_Maximal_Hidden_Group_IDs(base_empty_view_id, *desired_group_ids);
    Collect_Active_Hidden_Group_IDs(base_empty_view_id, *active_group_ids);

    // Restore old outer geometry before collapsing a newly maximal ancestor.
    for active_group_ids {
        if !View_ID_List_Contains(desired_group_ids, it) {
            Deactivate_Hidden_View_Group(it);
        }
    }
    for desired_group_ids {
        if !View_ID_List_Contains(active_group_ids, it) {
            Activate_Hidden_View_Group(it);
        }
    }
    Reapply_Individual_Hidden_View_Layouts(base_empty_view_id);
}

Refresh_Collapsed_View_Bar_Proportions_Recursive :: (view_id: s64) {
    view := View_From_ID(view_id);
    if view.hidden_group && view.hidden_group_collapsed {
        family, found_family := Get_View_Family(view);
        if found_family {
            total_length := View_Split_Parent_Axis_Length(view, view.hidden_group_side);
            bar_proportion := Collapsed_View_Bar_Proportion(view.hidden_group_side, total_length);
            Set_Direct_View_Split_Proportion(view, family.sibling, view.hidden_group_side, bar_proportion);
        }
    } else if View_ID_Is_Selectable(view_id)
    && view.hidden
    && !View_Has_Hidden_Group_Ancestor(view_id) {
        edge, side, found_edge := Get_Direct_View_Split_Edge(view);
        if found_edge {
            total_length := View_Split_Parent_Axis_Length(view, side);
            bar_proportion := Collapsed_View_Bar_Proportion(side, total_length);
            Set_Direct_View_Split_Proportion(view, edge[1], side, bar_proportion);
        }
    }

    for view.children {
        Refresh_Collapsed_View_Bar_Proportions_Recursive(it);
    }
}

Refresh_Collapsed_View_Bar_Proportions :: () {
    if Is_Empty(*view_pool) {
        return;
    }
    Refresh_Collapsed_View_Bar_Proportions_Recursive(ROOT_ID);
}

Collect_Views_At_Or_Below_Bar_Size :: (view_id: s64, view_ids: *[..]s64) {
    view := View_From_ID(view_id);
    if View_ID_Is_Selectable(view_id) {
        if !view.hidden && !View_Has_Hidden_Group_Ancestor(view_id) {
            edge, side, found_edge := Get_Direct_View_Split_Edge(view);
            if found_edge {
                rect, found_rect := Find_View_Screen_Rect(view_id, ROOT_ID, Window_Viewport_Rect());
                if found_rect {
                    axis_length := ifx side == .LEFT || side == .RIGHT
                        then rect.dimensions.x
                        else rect.dimensions.y;
                    if axis_length <= Collapsed_View_Bar_Thickness(side) {
                        array_add(view_ids, view_id);
                    }
                }
            }
        }
        return;
    }
    for view.children {
        Collect_Views_At_Or_Below_Bar_Size(it, view_ids);
    }
}

Collapse_Views_At_Or_Below_Bar_Size :: () {
    view_ids: [..]s64;
    view_ids.allocator = temp;
    Collect_Views_At_Or_Below_Bar_Size(ROOT_ID, *view_ids);
    for view_ids {
        saved_proportion := -1.0;
        belongs_to_mouse_drag := false;
        if mouse_interaction.active
        && mouse_interaction.mode == .VIEW_EDGE
        && View_Edge_Is_Live(*mouse_interaction.edge) {
            first_id := mouse_interaction.edge[0] - view_pool.items.data;
            second_id := mouse_interaction.edge[1] - view_pool.items.data;
            if it == first_id {
                saved_proportion = mouse_interaction.edge_restore_first_proportion;
                belongs_to_mouse_drag = true;
            } else if it == second_id {
                saved_proportion = mouse_interaction.edge_restore_second_proportion;
                belongs_to_mouse_drag = true;
            }
        }
        if Hide_View(it, saved_proportion) && belongs_to_mouse_drag {
            // Pixel rounding can make the layout pass recognize the terminal
            // bar one frame before the proportion comparison does. Preserve
            // that drag's original restore size, but leave the captured edge
            // armed so reversing the pointer can reveal the pane again.
        }
    }
}

Hide_View :: (view_id: s64, saved_proportion_override: float = -1.0) -> bool {
    if !View_ID_Is_Selectable(view_id) {
        return false;
    }
    view := *view_pool.items[view_id];
    if view.hidden {
        return true;
    }

    edge, side, found_edge := Get_Direct_View_Split_Edge(view);
    if !found_edge {
        return false;
    }

    fallback_view_id := previous_selected_view_id;
    if fallback_view_id == view_id || !View_ID_Has_Tab_Or_Content(fallback_view_id) {
        fallback_view_id = Find_Visible_Selectable_View_ID(ROOT_ID, view_id);
    }
    if Active_View_ID() == view_id && fallback_view_id < 0 {
        return false;
    }

    side_opposite := Opposite(side);
    saved_proportion := view.viewport.offsets[side_opposite];
    sibling := edge[1];
    if sibling.hidden {
        saved_proportion = view.hidden_saved_proportion;
    } else if sibling.hidden_group && sibling.hidden_group_collapsed {
        saved_proportion = 1.0 - sibling.hidden_group_saved_proportion;
    }
    if saved_proportion_override >= 0.0 {
        saved_proportion = saved_proportion_override;
    }
    total_length := View_Split_Parent_Axis_Length(view, side);
    bar_proportion := Collapsed_View_Bar_Proportion(side, total_length);

    view.hidden_side = side;
    view.hidden_saved_proportion = clamp(saved_proportion, 0.01, 0.99);
    sibling_id := sibling - view_pool.items.data;
    if View_ID_Is_Selectable(sibling_id) && !sibling.hidden {
        sibling.hidden_saved_proportion = 1.0 - view.hidden_saved_proportion;
    }
    view.hidden = true;
    Set_Direct_View_Split_Proportion(view, sibling, side, bar_proportion);
    Update_Hidden_View_Groups();

    if view_id == tool_view_id {
        tool_view_is_active = false;
    }
    if Active_View_ID() == view_id {
        if View_ID_Uses_Overlay_Stack(view_id) {
            Deactivate_Active_Overlay_View_ID(view_id, fallback_view_id);
        } else {
            Replace_Active_View_ID(fallback_view_id);
        }
    }
    return true;
}

Show_View :: (view_id: s64) -> bool {
    if !View_ID_Is_Selectable(view_id) {
        return false;
    }
    view := *view_pool.items[view_id];
    if !view.hidden {
        return true;
    }

    // A captured mouse gesture can outlive a topology change. Treat a
    // detached tab as unavailable without sending it through the diagnostic
    // family lookup used for genuinely malformed view trees.
    if Find_Parent(view_id) < 0 {
        return false;
    }
    family, found_family := Get_View_Family(view);
    if !found_family {
        return false;
    }
    Set_Direct_View_Split_Proportion(view, family.sibling, view.hidden_side, view.hidden_saved_proportion);
    view.hidden = false;
    Update_Hidden_View_Groups();
    if view_id == tool_view_id {
        tool_view_is_active = true;
        settings_file_data.tool_view_screen_proportion = view.hidden_saved_proportion;
    }
    return true;
}

Resize_View_Edge_To_Proportion :: (
    edge: *[2]*View,
    side: Side2D,
    requested_proportion: float,
    saved_first_proportion: float,
    saved_second_proportion: float
) -> collapsed: bool {
    total_length := View_Split_Parent_Axis_Length(edge.*[0], side);
    first_id := edge.*[0] - view_pool.items.data;
    second_id := edge.*[1] - view_pool.items.data;
    first_can_collapse := View_ID_Is_Selectable(first_id) && !edge.*[0].hidden;
    second_can_collapse := View_ID_Is_Selectable(second_id) && !edge.*[1].hidden;

    first_minimum := ifx first_can_collapse
        then Collapsed_View_Bar_Proportion(side, total_length)
        else 0.01;
    second_side := Opposite(side);
    second_minimum := ifx second_can_collapse
        then Collapsed_View_Bar_Proportion(second_side, total_length)
        else 0.01;

    if first_can_collapse && requested_proportion <= first_minimum {
        Balance_View_Edge(edge, side, first_minimum);
        if Hide_View(first_id, saved_first_proportion) {
            return true;
        }
    }
    if second_can_collapse && 1.0 - requested_proportion <= second_minimum {
        Balance_View_Edge(edge, side, 1.0 - second_minimum);
        if Hide_View(second_id, saved_second_proportion) {
            return true;
        }
    }

    Balance_View_Edge(edge, side, clamp(requested_proportion, first_minimum, 1.0 - second_minimum));
    return false;
}

// when the window is receiving no new input, we just copy the old render target to the new one. however,
// for the cursor to blink we need to redraw a few things.
Render_Partial_Update :: (view: *View, view_id: s64, viewport_id: s64, unused: *void) {
    if view.layers.data == null || view.hidden || View_Has_Hidden_Group_Ancestor(view_id) then return;
    active_layer := *view.layers[view.active_layer];
    if view_id != Active_View_ID() {
        active_view_layer := Active_View_Layer();
        if active_layer.type == .FILE_EDITOR 
        && active_view_layer.type == .FILE_EDITOR
        && active_layer.file_editor.file_buffer == active_view_layer.file_editor.file_buffer {
            // it's ok
            // TODO: there are more reasons to draw stuff here
        } else {
            return;
        }
    }
    cursor := Layer_Cursor(active_layer);
    if cursor == null then return;
    text_buffer := Layer_Text_Buffer(active_layer);
    if text_buffer == null then return;

    rect := viewport_rects[viewport_id];
    rendering_scissor_ul, rendering_scissor_lr = Viewport_Rect_Points(*rect, s32);
    Set_Scissor(rendering_scissor_ul, rendering_scissor_lr);

    renderer: TextRenderer;
    Initialize_Text_Renderer(*renderer, active_layer);

    // draw a bg quad across the entire line. if we try to redraw over it, the transparent edges will get filled in and the text will look bold / not blended well
    cursor_ul, cursor_lr := Render_Text_Cursor(*renderer, cursor, true);
    full_line_ul := cursor_ul;
    full_line_ul.x = renderer.align_info_main.screen_x;
    full_line_lr := cursor_lr;
    full_line_lr.x = rendering_scissor_lr.x;

    // TODO: bg color dependent on layer
    Set_Shader_For_Color();
    Render_Quad(full_line_ul, full_line_lr, fRGBA.{rgb=file_editor_background_color, a=1});

    // TODO: fix
    // Render_Text_Selection_Blocks(*renderer, text_buffer, cursor, cursor.y);

    // redraw the line of text the cursor is on
    visual_line_index := cursor.y - renderer.text_view_clip.y;
    if visual_line_index >= 0 && visual_line_index < renderer.line_count {
        renderer.rendered_line_count = visual_line_index;
        marked_utf32 := Line_View(text_buffer, cursor.y);
        if marked_utf32.count > renderer.text_view_clip.x {
            Set_Shader_For_Text();

            marked_utf32.data += renderer.text_view_clip.x;
            marked_utf32.count -= renderer.text_view_clip.x;

            utf8_buffer: [..]u8;
            utf8_buffer.allocator = temp;
            color_buffer: [..]TextColorLocation;
            color_buffer.allocator = temp;

            Get_Unmarked_Utf8(marked_utf32, *utf8_buffer, *color_buffer);
            Render_Text_Line(*renderer, *renderer.align_info_main, utf8_buffer, color_buffer);
            Render_Quads_Generated_For_Text();
        }
    }

    Render_Text_Cursor(*renderer, cursor);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// walk the tree of nodes that make up the UI and call view_proc per node. 
// the two integers view_proc takes are the view id and the viewport id (which only matters if push_viewports is true)
Walk_View_Tree :: (from_view_id: s64, Visit_Proc: (v: *View, view_id: s64, viewport_id: s64, user_data: T), user_data: $T, push_viewports := true) {
    view := Get_Item(*view_pool, from_view_id);
    view_is_root := from_view_id == 0;

    vp_id: s64;
    do_push_viewport := !view_is_root && push_viewports;
    if do_push_viewport {
        vp_id = Viewport_Push(view.viewport, true);
    }
    defer { if do_push_viewport then Viewport_Pop(); }

    Visit_Proc(view, from_view_id, vp_id, user_data);

    for view.children {
        Walk_View_Tree(it, Visit_Proc, user_data, push_viewports);
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// generates a switch statement over all ViewLayerTypes with the format:
// if #complete view_layer.type == {
// case .BACKGROUND;
//      code
// case .TOP_BAR;
//      code
// ...
// }
// passed-in code must include one '%' character, wherein "*view_layer.(name of layer field in union)" will be inserted
// for example, "Execute_Actions(%);", for the background switch case, expands to "Execute_Actions(*view_layer.background);"
// the point: self-maintaining switch - it extends all switches over view layers across the program automatically.
// it also requires a procedure polymorph for every enum, or the program won't compile;
Generate_View_Layer_Switch :: (with_code: string, layer_as_pointer := true) -> string {
    builder: String_Builder;
    print_to_builder(*builder, "if view_layer.type == {\n");

    names := enum_names(ViewLayerType);
    values := enum_values_as_enum(ViewLayerType);

    for names {
        if values[it_index] == .EMPTY {
            continue;
        } else {
            #if !ALLOW_DEBUG_VIEW {
                if values[it_index] == .DEBUG {
                    continue;
                }
            }
            format_string := tprint("case .%; %\n", it, with_code);
            context_alloc := context.allocator;
            context.allocator = temp;
            field_name := to_lower_copy(it);
            context.allocator = context_alloc;
            fully_qualified_name: string;
            if layer_as_pointer {
                fully_qualified_name = tprint("*view_layer.%", field_name);
            } else {
                fully_qualified_name = tprint("view_layer.%", field_name);
            }
            print_to_builder(*builder, format_string, fully_qualified_name);
        }
    }
    print_to_builder(*builder, "}\n");
    return builder_to_string(*builder);
}

ViewFamily :: struct {
    self: *View;
    sibling: *View;
    parent: *View;
}

Get_View_Family :: (v: *View) -> family: ViewFamily, success: bool {
    parent := Get_Parent(v);
    if parent == null {
        #if DEBUG_VIEWS then Log_Warning("parent is null");
        return .{}, false;
    }
    parent_is_root := parent - view_pool.items.data == 0;
    if parent.children.count < 1 || parent.layers.count != 0 {
        #if DEBUG_VIEWS then Log_Warning("parent child count is %", parent.children.count);
        return .{}, false;
    }
    for parent.children {
        child := *view_pool.items[it];
        if child == v then continue;
        if !parent_is_root {
            if child.layers.count == 0 {
                if child.children.count < 1 {
                    continue;
                }
            } else if child.layers[0].type == .VIM_CONSOLE then continue;
        } else {
            if child.layers.count > 0 && child.layers[0].type == .VIM_CONSOLE then continue;
        }
        return .{v, child, parent}, true;
    }
    #if DEBUG_VIEWS then Log_Warning("unable to find child");
    return .{}, false;
}

Get_Parent :: inline (v: *View) -> *View {
    id := Find_Parent(v);
    return ifx id == -1 then null else *view_pool.items[id];
}

Find_Parent :: inline (v: *View) -> s64 {
    id := Element_Index(v, view_pool.items);
    return Find_Parent(id, 0);
}

Find_Parent :: (of_node: s64, search_from_node := 0) -> s64 {
    view := Get_Item(*view_pool, search_from_node);
    for view.children {
        if it == of_node {
            return search_from_node;
        } else {
            search_id := Find_Parent(of_node, it);
            if search_id != -1 {
                return search_id;
            }
        }
    }
    return -1;
}

// returns id to empty parent
Reparent_To_Empty :: (v: *View, parent_id := -1) -> s64 {
    use_parent_id := ifx parent_id == -1 then Find_Parent(v) else parent_id;
    assert(use_parent_id != -1);
    view_id := Element_Index(v, view_pool.items);

    empty_id := Add_View(v.viewport, null, use_parent_id, view_id);

    empty_view := Get_Item(*view_pool, empty_id);
    empty_view.children.count += 1;
    empty_view.children[0] = xx view_id;

    v.viewport = .{};

    return empty_id;
}

View_Layer_From_Data :: (data: *ViewLayerData) -> *ViewLayer {
    data_offset := Offset_Of(ViewLayer, "data");
    byte_ptr := pub(data) - data_offset;
    return xx byte_ptr;
}

Move_View_Y :: (layer: *ViewLayer, row_delta: float32, y_lim: float32, $_DIR: enum {UP; DOWN;}) {
    if Bool_Option_Value(.SOFT_WRAP) && layer.type == .FILE_EDITOR {
        renderer: TextRenderer;
        Initialize_Text_Renderer(*renderer, layer);
        render_line: RenderLineData;
        Initialize_Render_Line_Data(*render_line, *renderer);
        line := render_line.start_line;

        row_delta_remain := row_delta;
        init_base_y_whole := cast(float)Floor(layer.view_position.y);

        ITER_MAX :: 99;
        for 0..ITER_MAX {
            line_text := Line_View(Layer_Text_Buffer(layer), line);
            line_row_ct_s32 := Render_Wrapped_Line(*renderer, null, null, line_text, *render_line, true);
            line_row_ct_s32 = max(line_row_ct_s32, sdw(1));
            line_row_ct := cast(float)line_row_ct_s32;
            linear_delta := row_delta_remain / cast(float)line_row_ct;

            #if _DIR == .UP {
                base_y_whole := init_base_y_whole - cast(float)it;
                new_y := layer.view_position.y - linear_delta;
                remain := base_y_whole - new_y;
                if remain < 0 {
                    layer.view_position.y = new_y;
                    break;
                }
                layer.view_position.y = base_y_whole;
                row_delta_remain = remain * cast(float)line_row_ct;
                line -= 1;
                if line < 0 {
                    break;
                }
            } else {
                base_y_whole := cast(float)Floor(layer.view_position.y);
                next_y_whole := base_y_whole + 1.0;
                new_y := layer.view_position.y + linear_delta;
                remain := new_y - next_y_whole;
                if remain < 0 {
                    layer.view_position.y = new_y;
                    break;
                }
                layer.view_position.y = next_y_whole;
                row_delta_remain = remain * cast(float)line_row_ct;
                line += 1;
                if line >= Layer_Text_Buffer(layer).lines.count {
                    break;
                }
            }
        }
        // nearest_whole_y := cast(float)Round_Away_From_Zero(layer.view_position.y);
        // whole_y_diff := abs(nearest_whole_y - layer.view_position.y);
        // if whole_y_diff < row_delta * (1.0 / 10.0) && whole_y_diff > 0.0001 {
        //     layer.view_position.y = nearest_whole_y;
        // }
    } else {
        #if _DIR == .UP {
            layer.view_position.y -= row_delta;
        } else {
            layer.view_position.y += row_delta;
        }
    }
    #if _DIR == .UP {
        layer.view_position.y = max(layer.view_position.y, y_lim);
    } else {
        layer.view_position.y = min(layer.view_position.y, y_lim);
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// a view may adjust its own scissor, but if this is called during a render pass that uses the entire window as the scissor, it's the responsibility of that view to set it back.
Set_View_Scissor :: (ul: IntVector2, lr: IntVector2) {
    rendering_scissor_ul = ul;
    rendering_scissor_lr = lr;
    Set_Scissor(rendering_scissor_ul, rendering_scissor_lr);
}

Scroll_View_Down :: (layer: *ViewLayer, y_max: float32, speed: float32) {
    row_delta := speed * Interactive_Delta_Time();
    Move_View_Y(layer, row_delta, y_max, .DOWN);
}

Scroll_View_Up :: (layer: *ViewLayer, y_min: float32, speed: float32) {
    row_delta := speed * Interactive_Delta_Time();
    Move_View_Y(layer, row_delta, y_min, .UP);
}

Scroll_View_Right :: (layer: *ViewLayer, x_max: float32, speed: float32) {
    layer.view_position.x += speed * Interactive_Delta_Time();
    layer.view_position.x = min(layer.view_position.x, x_max);
}

Scroll_View_Left :: (layer: *ViewLayer, x_min: float32, speed: float32) {
    layer.view_position.x -= speed * Interactive_Delta_Time();
    layer.view_position.x = max(layer.view_position.x, x_min);
}

View_Bounds :: (layer: *ViewLayer) -> (ul: Vector2, lr: Vector2) {
    if layer.type == {
    case .FILE_EDITOR;
        return .{}, layer.file_editor.view_max;
    case;
        return .{}, .{};
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

ViewLayerType :: enum_flags u16 {
    EMPTY               :: 0x0000;
    TOP_BAR             :: 0x0001;
    FILE_EDITOR;
    VIM_CONSOLE;
    FILE_EXPLORER;
    PROJECT_EXPLORER;
    OS_CONSOLE;
    DEBUG;
}

ViewLayerData :: union {
    empty: EmptyLayer = ---;
    top_bar: TopBar = ---;
    file_editor: FileEditor = ---;
    vim_console: VimConsole = ---;
    file_explorer: FileExplorer = ---;
    project_explorer: ProjectExplorer = ---;
    os_console: OSConsole = ---;
    debug: DebugView = ---;
}

ViewLayer :: struct {
    type: ViewLayerType;
    need_reinit: bool;
    id: u32;
    view_position: Vector2; 
    using data: ViewLayerData;
}

// if a layer wants a cursor, the cursor should be the first field so we can grab it regardless of the layer type
CursorLayer :: struct($LayerDataType: Type) {
    cursor: Cursor;
    using layer_data: LayerDataType;
}

DummyCursorLayer :: CursorLayer(struct{});

Is_Cursor_Layer_Type :: (view_layer: *ViewLayer) -> bool {
    is_cursor_type: bool;
    #insert #run Generate_View_Layer_Switch("is_cursor_type = Is_Subtype(cast(*Type_Info)(type_of(%)), \"CursorLayer\", true);", false);
    return is_cursor_type;
}

Layer_Cursor :: (layer: *ViewLayer) -> *Cursor {
    if layer == null || !Is_Cursor_Layer_Type(layer) then return null;
    return *(cast,force(*DummyCursorLayer)(*layer.data)).cursor;
}

Layer_Text_Buffer :: (layer: *ViewLayer) -> *TextBuffer {
    if layer.type == {
    case .FILE_EDITOR;
        buffer_index := layer.file_editor.file_buffer;
        if buffer_index != -1 {
            return *file_buffers.items[buffer_index];
        }
    case .FILE_EXPLORER;
        buffer_index := layer.file_explorer.text_buffer;
        if buffer_index != -1 {
            return *file_buffers.items[buffer_index];
        }
    case .PROJECT_EXPLORER;
        buffer_index := layer.project_explorer.text_buffer;
        if buffer_index != -1 {
            return *file_buffers.items[buffer_index];
        }
    case .DEBUG;
        if layer.debug.type == .GENERAL_DEBUG 
        || Active_View_Layer().type == .FILE_EDITOR 
        || Active_View_Layer().type == .FILE_EXPLORER {
            return Debug_View_Text_Buffer(*layer.debug);
        }
    }
    return null;
}

Layer_Render_Line_Y_Offset :: (layer: *ViewLayer, line: s32) -> s32 {
    if layer == null {
        return 0;
    }
    if layer.type == {
    case .FILE_EXPLORER;
        if line >= 2 {
            return -Integer_Option_Value(.FONT_SIZE) >> 1;
        }
    case .PROJECT_EXPLORER;
        // Project config views have a status row between their heading and
        // files, so use the normal line rhythm there. The project root keeps
        // the file-explorer-style compact listing.
        if layer.project_explorer.directory.count == 0 && line >= 2 {
            return -Integer_Option_Value(.FONT_SIZE) >> 1;
        }
    }
    return 0;
}

Find_Valid_File_Editor_Buffer :: (pivot_id: s64, forward: bool) -> s64 {
    i := 0;
    scroll_dir := ifx forward then 1 else -1;
    buf_id := pivot_id + scroll_dir;

    while i < file_buffers.items.count {
        if buf_id >= file_buffers.items.count {
            buf_id = 0;
        } else if buf_id < 0 {
            buf_id = file_buffers.items.count-1;
        }
        if Is_Item_In_Use(*file_buffers, buf_id) && file_buffers.items[buf_id].flags == 0 {
            return buf_id;

        }
        buf_id += scroll_dir;
        i += 1;
    }
    return -1;
}

Scroll_File_Buffer :: (layer: *ViewLayer, forward: bool) {
    assert(layer.type == .FILE_EDITOR);

    valid_buf_id := Find_Valid_File_Editor_Buffer(layer.file_editor.file_buffer, forward);
    if valid_buf_id == -1 {
        return;
    }

    layer.file_editor.file_buffer = valid_buf_id;
    file_editor := *layer.file_editor;
    // each file buffer has its a cursor position cached by file editors when they move
    layer.file_editor.cursor = file_buffers.items[valid_buf_id].saved_cursor;
    Center_View_On_Cursor(View_Layer_From_Data(xx file_editor), xx file_buffers.items[valid_buf_id].lines.count);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// layer types

EmptyLayer :: struct {}

TopBar :: struct {}

FileEditor :: CursorLayer(
    struct {
        file_buffer: s64 = -1;
        // only used for mouse wheel scrolling or anything bound to use mouse wheel-like scrolling
        view_velocity: Vector2;
        view_max: Vector2;
        text_selection_begin := IntVector2.{-1,-1};
        text_selection_end := IntVector2.{-1,-1};
        rendered_text_data: [..]RenderedTextData;
    }
);

VimConsole :: CursorLayer(
    struct {
        display_only: bool;
        mode: enum u8 {
            COMMAND;
            SEARCH;
        }
    }
);

DebugView :: CursorLayer(
    struct {
        type: DebugViewType;
    }   
);

FileExplorer :: CursorLayer(
    struct {
        text_buffer: s64 = -1;
        directory: string;
        // The destination left behind by upward path navigation.  Its suffix
        // after `directory` is rendered as the forward-navigation trail.
        forward_path: string;
        directory_list_outline_alpha: float;
        // The divider between the directory list and the preview.  Unlike the
        // old three-state setting, this is a continuous proportion so keyboard
        // and mouse resizing can share one layout.
        preview_vertical_proportion: float = 0.5;
        preview_saved_vertical_proportion: float = 0.5;
        preview_hidden: bool;
    }
);

ProjectExplorer :: CursorLayer(
    struct {
        text_buffer: s64 = -1;
        // Empty means the all-projects list. Otherwise, this is the expanded
        // project's configuration directory.
        directory: string;
    }
);

OSConsole :: CursorLayer(
    struct {
        input_read: *void;
        input_write: *void;
        output_read: *void;
        output_write: *void;
        pseudoconsole: *void;
        terminal: *void;
        terminal_id: u32;
        init_failure: bool;
    }
);

DebugViewType :: enum u8 {
    UNDO_REDO;
    BIN_POOL;
    TEXT_BUFFER;
    GENERAL_DEBUG;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

View :: struct {
    viewport: Viewport;
    layers: []ViewLayer;
    children_buffer: [VIEW_CHILDREN_MAX]s16;
    children: []s16;
    pixel_dimensions: IntVector2;
    active_layer: s8 = -1;
    hidden: bool;
    hidden_side: Side2D;
    hidden_saved_proportion: float = 0.5;
    hidden_group: bool;
    hidden_group_collapsed: bool;
    hidden_group_side: Side2D;
    hidden_group_saved_proportion: float = 0.5;
}

LateViewDraw :: struct {
    view_id: s64;
    viewport_id: s64;
}

ViewData :: struct {
    view: *View;
    id: s64;
    viewport_ul: IntVector2;
    viewport_lr: IntVector2;
}

DataChunk :: struct($T: Type, $COUNT: s64) {
    items: [COUNT]T;
}
ViewLayerChunk :: DataChunk(ViewLayer, VIEW_LAYERS_MAX);

SplitDirection :: enum u8 { HORIZONTAL; VERTICAL; }

ViewRenderPass :: enum u8 {
    BACKGROUND;
    LINES;
    IMAGES;
    TEXT;
    FOREGROUND;
}

Upper_Left :: inline () -> IntVector2 {
    return rendering_scissor_ul;
}

Lower_Right :: inline () -> IntVector2 {
    return rendering_scissor_lr;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Active_View_ID :: () -> s64 {
    if editor_view_stack.count > 0 {
        return editor_view_stack[editor_view_stack.count-1];
    } else return -1;
}

Background_View_ID :: (bg_steps: u32 = 1) -> s64 {
    i := editor_view_stack.count - (1 + cast(s64)(bg_steps));
    assert(i >= 0);
    return editor_view_stack[i];
}

Replace_Background_View_ID :: (id: s64, bg_steps: u32 = 1) {
    i := editor_view_stack.count - (1 + cast(s64)(bg_steps));
    assert(i >= 0);
    editor_view_stack[i] = id;
}

Replace_Active_View_ID :: (id: s64) {
    assert(editor_view_stack.count > 0);
    previous_id := Active_View_ID();
    if previous_id != id && View_ID_Is_Selectable(previous_id) && View_ID_Is_Selectable(id) {
        previous_selected_view_id = previous_id;
    }
    editor_view_stack[editor_view_stack.count-1] = id;
}

View_ID_Uses_Overlay_Stack :: (view_id: s64) -> bool {
    return view_id == tool_view_id || view_id == vim_console_id;
}

Remove_View_ID_From_Active_Stack :: (view_id: s64) {
    if editor_view_stack.count == 0 {
        return;
    }
    write_index: s64;
    for read_index: 0..editor_view_stack.count-1 {
        if editor_view_stack[read_index] == view_id {
            continue;
        }
        editor_view_stack[write_index] = editor_view_stack[read_index];
        write_index += 1;
    }
    editor_view_stack.count = write_index;
}

Focus_Overlay_View_ID :: (view_id: s64) -> bool {
    if Active_View_ID() == view_id {
        return true;
    }
    Remove_View_ID_From_Active_Stack(view_id);
    if editor_view_stack.count == 0 {
        return false;
    }
    Push_Active_View_ID(view_id);
    return true;
}

Deactivate_Active_Overlay_View_ID :: (view_id: s64, fallback_view_id: s64) -> bool {
    if Active_View_ID() != view_id {
        return false;
    }

    if editor_view_stack.count > 1 {
        Pop_Active_View_ID();
    } else if View_ID_Is_Selectable(fallback_view_id) {
        Replace_Active_View_ID(fallback_view_id);
        return true;
    } else {
        return false;
    }

    if View_ID_Is_Selectable(fallback_view_id) && Active_View_ID() != fallback_view_id {
        Replace_Active_View_ID(fallback_view_id);
    }
    return true;
}

Push_Active_View_ID :: (id: s64) {
    assert(editor_view_stack.count < editor_view_stack_buffer.count);
    previous_id := Active_View_ID();
    if previous_id != id && View_ID_Is_Selectable(previous_id) && View_ID_Is_Selectable(id) {
        previous_selected_view_id = previous_id;
    }
    editor_view_stack.count += 1;
    editor_view_stack[editor_view_stack.count-1] = id;
}

Pop_Active_View_ID :: () -> s64 {
    assert(editor_view_stack.count > 0);
    id := editor_view_stack[editor_view_stack.count-1];
    editor_view_stack.count -= 1;
    next_id := Active_View_ID();
    if id != next_id && View_ID_Is_Selectable(id) && View_ID_Is_Selectable(next_id) {
        previous_selected_view_id = id;
    }
    return id;
}

Find_First_Layer_Of_Type_In_View_Stack :: (type: ViewLayerType) -> *ViewLayer {
    _, layer := Find_First_View_And_Layer_Of_Type_In_View_Stack(type);
    return layer;
}

Find_First_View_And_Layer_Of_Type_In_View_Stack :: (type: ViewLayerType) -> view_id: s64, layer: *ViewLayer {
    assert(editor_view_stack.count > 0);
    for < editor_view_stack {
        view := view_pool.items[it];
        active_layer := *view.layers[view.active_layer];
        if active_layer.type == type {
            return it, active_layer;
        }
    }
    return -1, null;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

ToolViewLayer :: enum {
    FILE_EXPLORER :: 0;
    OS_CONSOLE    :: 1;
    PROJECT_EXPLORER :: 2;
}

VIEW_CHILDREN_MAX :: 16;
VIEW_LAYERS_MAX :: 16;
VIEWS_MAX :: 128;

VIM_CONSOLE_DEPTH :: 0.0;
VIM_CONSOLE_TEXT_DEPTH :: 0.1;
TEXT_DEPTH :: 0.0;

vim_console_id: s64;
kb_cursor_blink_time := 0.68;

tool_view_id: s64;
tool_view_is_active: bool;
last_tool_view_layer: ToolViewLayer = .FILE_EXPLORER;

editor_view_stack_buffer: [128]s64;
editor_view_stack: []s64;

view_pool: DynamicPool(View);
view_layer_pool: DynamicPool(ViewLayerChunk);
actions_executed_this_frame: [..]Action;

rendering_scissor_ul: IntVector2;
rendering_scissor_lr: IntVector2;

render_full_update: bool;
base_empty_view_id: s64;

view_layer_id_counter: u32;

selected_view_side: Side2D;
previous_selected_view_id: s64 = -1;
collapsed_view_bar_thickness_for_tests: s32 = -1;

ROOT_ID :: 0;
OS_CONSOLE_LAYER :: ToolViewLayer.OS_CONSOLE;

RenderedTextData :: struct {
    text_row: s32;
    glyph_count: s16;
    wrap_indent_length: s8;
    wrapped: bool;
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

INTRO_FILE_TEXT :: #string HERE
vai quick reference
===================
Modal editor, vim-style. Esc returns to Normal mode from anywhere.


NORMAL mode
-----------
Move   h j k l          left / down / up / right
       w W  b B         word forward / back   (W B = whitespace-delimited)
       e E              end of word
       0  H  L          line: column 0 / first non-blank / end
       gg  G            top / bottom of file
       {  }             previous / next blank line
       <C-u> <C-d>      half page up / down
       <C-U> <C-D>      full page up / down
       -  =             previous / next buffer
Edit   i  a             insert before / after cursor
       o  O             open line below / above
       x                delete character
       dd dw diw        delete line / word / inner word
       cc cw ciw        change line / word / inner word
       d0 c0            delete / change to column 0
       r<c>             replace character with <c>
       ~                toggle case
       yy  p  P         yank line / paste after / before
       u  <C-r>         undo / redo
       .                repeat last change
       <C-/>            toggle line comment
Find   /                search;  n N  next / prev match
Enter  v  :             visual mode / command mode
       <CR>             activate current row (explorer, projects, results)
Views  <C-h> <C-s>      hide / show active view
       <C-j> <C-k> <C-l>  grab bottom / top / right edge to resize
       <C-w><C-w>       focus next editor


INSERT mode
-----------
Type to insert text.  <CR> new line.  Backspace deletes.  Esc returns to Normal.


VISUAL mode
-----------
h j k l w b e ...   extend the selection
d  c  y             delete / change / yank selection
U  u                uppercase / lowercase selection
<C-/>               toggle comment.   Esc returns to Normal.


RESIZE-VIEW mode
----------------
<C-h> <C-j> <C-k> <C-l>   move the active edge left / down / up / right
h  s                      hide / show a view
/                         make view proportions equal


COMMAND mode  (:)
-----------------
Type a command name and <CR>. Tab autocompletes. Unambiguous prefixes work.
  :open  :o  <path>            open a file
  :save  :w                    save the current buffer
  :close :c  [buffer]          close the view (or its buffer)
  :quit  :q                    exit vai
  :vertical-split    :v        split the view vertically
  :horizontal-split  :h        split the view horizontally
  :buffer-next       :bn       show the next buffer
  :buffer-previous   :bp       show the previous buffer
  :set   :s  <option> <value>  change a setting (see below)
  :tools :t                    toggle the last tool window
  :explorer :e                 file explorer
  :projects :p                 project browser
  :project-create :pc <name> <path>   create a project (path without spaces)


Settings  (:set <name> <value>)
-------------------------------
  line-numbers           bool   show line numbers              (on)
  relative-line-numbers  bool   relative line numbers          (off)
  smart-case             bool   ignore case unless uppercase   (on)
  indent-width           int    spaces per indent              (4)
  auto-indent            bool   auto-indent new lines          (on)
  soft-wrap              bool   wrap long lines                (on)
  soft-wrap-indent       int    indent for wrapped lines       (2)
  font-size              int    editor font size               (14)


Tool windows
------------
  :explorer   Browse files. <CR>/l open, h go up. Selecting an asset previews
              images (PNG JPEG BMP TGA PSD GIF HDR EXR TIFF DNG PIC PPM PGM DDS)
              and unlit 3D scenes (glTF GLB FBX OBJ USD USDA USDC USDZ).
  :projects   Browse and switch projects. [open project] switches to it and
              restores its files/views; <CR>/l expands its config folder, h back.
  :tools      Toggle the most recently used tool window.


Configuration
-------------
All writable config lives in %APPDATA%/Vai (never beside the executable):
  main/settings.txt             global settings
  projects/<name>/project.txt   sets the project's main_directory
  projects/<name>/settings.txt  per-project setting overrides
  projects/<name>/views.txt     open files/views (managed by vai)
If no project is chosen, vai opens one named 'default'; later launches reopen
the last project. Drop a preview-provider DLL in %APPDATA%/Vai/plugins/preview
to add scene formats (see docs/scene-preview-plugins.md). .jai files are
syntax-highlighted.
HERE
