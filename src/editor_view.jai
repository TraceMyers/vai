
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
        tool_view_id = Add_View(.{type=.PROPORTION, left=0.0}, *layer, ROOT_ID);
    }
    {
        layer: ViewLayer;
        layer.type = .OS_CONSOLE;
        layer.os_console = .{};
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
    if file_data.count == 0 {
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
    view.* = .{};
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

Render_Views :: (full_update: bool) {
    Begin_Draw_Frame(full_update);
    defer End_Draw_Frame();
    debug_view_open = Count_Layers_Of_Type(*view_pool.items[ROOT_ID], .DEBUG, true) > 0;
    if Is_Empty(*view_pool) then return;
    
    if full_update {
        // walking the view tree multiple times because tree traversal is pretty cheap + number of draw calls can be reduced by grouping draws into natural batches (background rects, lines, text, etc..)
        Set_Shader_For_Blended_Color();
        Walk_View_Tree(0, Render_View, ViewRenderPass.BACKGROUND);
        Flush_Draws();
        Set_Shader_For_Lines();
        Walk_View_Tree(0, Render_View, ViewRenderPass.LINES);
        Flush_Draws();
        // Set_Shader_For
        // Walk_View_Tree(0, Render_View, ViewRenderPass.IMAGES);
        Set_Shader_For_Text();
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

    sin_xt := cast(float) sin(seconds_since_init() * 2.69);
    alpha := Respace(sin_xt, .{-1.0, 1.0}, .{0.25, 0.6});
    side_color := fRGBA.{0.9, 0.45, 0.6, alpha};
    Render_Quad(begin, end, side_color);
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

    edge.*[0].viewport.offsets[side_opposite] = clamp(edge.*[0].viewport.offsets[side_opposite] + delta, 0.01, .99);
    edge.*[1].viewport.offsets[side] = 1.0 - edge.*[0].viewport.offsets[side_opposite];

    view_ids := s64.[edge.*[0] - view_pool.items.data, edge.*[1] - view_pool.items.data];    
    if view_ids[0] == tool_view_id {
        settings_file_data.tool_view_screen_proportion = edge.*[0].viewport.offsets[side_opposite];
    } else if view_ids[1] == tool_view_id {
        settings_file_data.tool_view_screen_proportion = edge.*[1].viewport.offsets[side];
    }
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

// when the window is receiving no new input, we just copy the old render target to the new one. however,
// for the cursor to blink we need to redraw a few things.
Render_Partial_Update :: (view: *View, view_id: s64, viewport_id: s64, unused: *void) {
    if view.layers.data == null then return;
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
    parent_is_root := parent - view_pool.items.data == 0;
    if parent == null {
        #if DEBUG_VIEWS then Log_Warning("parent is null");
        return .{}, false;
    }
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

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// a view may adjust its own scissor, but if this is called during a render pass that uses the entire window as the scissor, it's the responsibility of that view to set it back.
Set_View_Scissor :: (ul: IntVector2, lr: IntVector2) {
    rendering_scissor_ul = ul;
    rendering_scissor_lr = lr;
    Set_Scissor(rendering_scissor_ul, rendering_scissor_lr);
}

Scroll_View_Down :: (layer: *ViewLayer, y_max: float32, speed: float32) {
    layer.view_position.y += speed * xx delta_time;
    layer.view_position.y = min(layer.view_position.y, y_max);
}

Scroll_View_Up :: (layer: *ViewLayer, y_min: float32, speed: float32) {
    test_min_y := -FLOAT32_MAX; 
    wrap_overflow_y := 0.0;
    if Do_Line_Wrap(layer) {
        renderer: TextRenderer;
        Initialize_Text_Renderer(*renderer, layer);
        render_line: RenderLineData;
        Initialize_Render_Line_Data(*render_line, *renderer);
        if render_line.start_line > 0 {
            prev_line := render_line.start_line - 1;
            prev_line_text := Line_View(Layer_Text_Buffer(layer), prev_line);
            prev_line_wrap_ct := Render_Wrapped_Line(*renderer, null, null, prev_line_text, *render_line, true);
            if prev_line_wrap_ct > 1 {
                test_min_y = cast(float32)Floor(layer.view_position.y, s32);
                if layer.view_position.y - test_min_y > 0.9999 {
                    test_min_y += 1;
                }
                wrap_overflow_y = xx (prev_line_wrap_ct - 1);
            }
        }
    }

    layer.view_position.y -= speed * xx delta_time;
    layer.view_position.y = max(layer.view_position.y, y_min);

    if layer.view_position.y < test_min_y {
        file_editor := *layer.file_editor;
        file_editor.scroll_up_subposition += test_min_y - layer.view_position.y;
        if file_editor.scroll_up_subposition >= wrap_overflow_y {
            layer.view_position.y -= file_editor.scroll_up_subposition - wrap_overflow_y;
            file_editor.scroll_up_subposition = 0;
        } else {
            layer.view_position.y = test_min_y;
        }
    }
}

Scroll_View_Right :: (layer: *ViewLayer, x_max: float32, speed: float32) {
    layer.view_position.x += speed * xx delta_time;
    layer.view_position.x = min(layer.view_position.x, x_max);
}

Scroll_View_Left :: (layer: *ViewLayer, x_min: float32, speed: float32) {
    layer.view_position.x -= speed * xx delta_time;
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
    OS_CONSOLE;
    DEBUG;
}

ViewLayerData :: union {
    empty: EmptyLayer = ---;
    top_bar: TopBar = ---;
    file_editor: FileEditor = ---;
    vim_console: VimConsole = ---;
    file_explorer: FileExplorer = ---;
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
        scroll_up_subposition: float32;
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
        end_path_bin: BinID;
        directory: string;
        directory_list_outline_alpha: float;
        preview_vertical_proportion: enum {
            NONE;
            HALF;
            FULL;
        } = .HALF;
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
    editor_view_stack[editor_view_stack.count-1] = id;
}

Push_Active_View_ID :: (id: s64) {
    assert(editor_view_stack.count < editor_view_stack_buffer.count);
    editor_view_stack.count += 1;
    editor_view_stack[editor_view_stack.count-1] = id;
}

Pop_Active_View_ID :: () -> s64 {
    assert(editor_view_stack.count > 0);
    id := editor_view_stack[editor_view_stack.count-1];
    editor_view_stack.count -= 1;
    return id;
}

Find_First_Layer_Of_Type_In_View_Stack :: (type: ViewLayerType) -> *ViewLayer {
    assert(editor_view_stack.count > 0);
    for < editor_view_stack {
        view := view_pool.items[it];
        active_layer := *view.layers[view.active_layer];
        if active_layer.type == type {
            return active_layer;
        }
    }
    return null;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

ToolViewLayer :: enum {
    FILE_EXPLORER :: 0;
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

ROOT_ID :: 0;
OS_CONSOLE_LAYER :: 1;

RenderedTextData :: struct {
    text_row: s32;
    glyph_count: s16;
    wrap_indent_length: s8;
    wrapped: bool;
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

INTRO_FILE_TEXT :: #string HERE
type ':open somefilename' to open a file.
type ':split-horizontal somefilename' to open a file in side-by-side. (or leave out the filename to split the current file)
type ':close view' or just ':close' to close a view.
type ':close buffer' to close a text buffer
type ':save' to write the selected buffer to file.
type ':quit' to quit the program.
type ':tools' to open the tool view. currently the only tool is the file explorer, which is incomplete.

Shorthand commands work as long as what you've typed could only resolve to one command.
For example, ':o ...' loads a file into a buffer just like ':open ...' would.

For learning vim motions, check out vim-adventures.com. 
If you're already familiar with vim, you'll notice a few things are different in vai, and many features are missing. 
In the future, more will be different, and many more features will be available... it just takes time ;d 
HERE