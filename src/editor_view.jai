
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
    vim_console_background_color = transparent_blue.rgb;
    top_bar_background_color = transparent_blue.rgb;
    file_editor_background_color = .{};
    file_editor_outline_color = .{1,1,1,0.15};

    // root
    ROOT_ID :: 0;
    {
        id := Add_View(.{}, null);
        assert(id == ROOT_ID);
    }
    // top bar
    {
        layer: ViewLayer;
        layer.type = .TOP_BAR;
        layer.top_bar = .{};
        Add_View(.{type=.PIXELS, top_pixels=24}, *layer, ROOT_ID);
    }
    // // bottom bar / vim console
    {
        layer: ViewLayer;
        layer.type = .VIM_CONSOLE;
        layer.vim_console = .{};
        vim_console_id = Add_View(.{type=.PIXELS, bottom_pixels=20}, *layer, ROOT_ID);
        vim_console := Get_Item(*view_pool, vim_console_id);
    }
    // empty background to stage file editors
    empty_id: s64;
    {
        empty_id = Add_View(.{type=.PIXELS, top_pixels=24, inverted=true}, null, ROOT_ID);
    }
    // default file editor
    {
        intro_file_name := Prepare_Intro_File();
        layer: ViewLayer;
        layer.type = .FILE_EDITOR;
        layer.file_editor = .{};
        layer.file_editor.file_buffer = Get_File_Buffer_ID(intro_file_name);
        active_view_id = Add_View(.{inverted=true}, *layer, empty_id);
    }
    // test split file editor
    Split_View(*view_pool.items[active_view_id], .VERTICAL);
}

Prepare_Intro_File :: () -> string {
    INTRO_FILE_NAME :: "intro.txt";
    file_data := read_entire_file(INTRO_FILE_NAME);
    if file_data.count == 0 {
        write_entire_file(INTRO_FILE_NAME, "type ':e somefilename' to open a file");
    }
    return INTRO_FILE_NAME;
}

Activate_Background_View :: () {
    active_view_id = background_view_id;
    background_view_id = -1;
}

Set_Active_View :: (id: s64) {
    active_view_id = id;
    background_view_id = -1;
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

    // a view only has layers if it is meant to be rendered. empty views simply house views that are rendered.
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
}

Split_View :: (v: *View, direction: SplitDirection) {
    parent_id := Find_Parent(v);
    assert(parent_id != -1);
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
    Set_Active_View(new_view_id);
    new_view := Get_Item(*view_pool, new_view_id);

    if direction == .HORIZONTAL {
        v.viewport.top = 0.5;
        new_view.viewport.bottom = 0.5;
    } else {
        v.viewport.left = 0.5;
        new_view.viewport.right = 0.5;
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// TODO: passes: background, lines, images, text, foreground
Render_Views :: () {
    Begin_Draw_Frame();
    defer End_Draw_Frame();
    if Is_Empty(*view_pool) then return;

    // walking the view tree multiple times because tree traversal is pretty cheap + number of draw calls can be reduced
    // by grouping draws into batches that can be drawn the same way
    Set_Shader_For_Color();
    Walk_View_Tree(0, Render_View, ViewRenderPass.BACKGROUND);
    Set_Shader_For_Lines();
    Walk_View_Tree(0, Render_View, ViewRenderPass.LINES);
    // Set_Shader_For
    // Walk_View_Tree(0, Render_View, ViewRenderPass.IMAGES);
    Set_Shader_For_Text();
    Walk_View_Tree(0, Render_View, ViewRenderPass.TEXT);
    Set_Shader_For_Color();
    Walk_View_Tree(0, Render_View, ViewRenderPass.FOREGROUND);
}

Render_View :: (view: *View, view_id: s64, viewport_id: s64, render_pass: ViewRenderPass) {
    if view.layers.data != null {
        rect := viewport_rects[viewport_id];
        rendering_scissor_ul, rendering_scissor_lr = Viewport_Rect_Points(*rect, s32);
        Set_Scissor(rendering_scissor_ul, rendering_scissor_lr);

        view_layer := *view.layers[view.active_layer];
        view_active := view_id == active_view_id;
        #insert #run Generate_View_Layer_Switch("Render_Layer(%, view_active, render_pass);");
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// walk the tree of nodes that make up the UI and call view_proc per node. 
// the two integers view_proc takes are the view id and the viewport id (which only matters if push_viewports is true)
Walk_View_Tree :: (from_view_id: s64, Visit_Proc: (v: *View, view_id: s64, viewport_id: s64, user_data: T), user_data: $T, push_viewports := true) {
    view := Get_Item(*view_pool, from_view_id);
    view_is_root := from_view_id == 0;

    vp_id: s64;
    do_push_viewport := !view_is_root && push_viewports;
    if do_push_viewport {
        vp_id = Viewport_Push(view.viewport, view.layers.data != null);
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
    for names {
        if it_index == 0 || it_index == names.count - 1{ // EMPTY layer or ALL
            // do nothing
        } else {
            format_string := tprint("case .%; %\n", it, with_code);
            context_alloc := context.allocator;
            context.allocator = temp;
            field_name := to_lower_copy_new(it);
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

Find_Parent :: inline (v: *View) -> s64 {
    return Find_Parent(Element_Index(v, view_pool.items), 0);
}

Find_Parent :: (of_node: s64, current_node := 0) -> s64 {
    view := Get_Item(*view_pool, current_node);
    for view.children {
        if it == of_node {
            return current_node;
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

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

ViewLayerType :: enum_flags u16 {
    EMPTY   :: 0x00;
    TOP_BAR :: 0x01;
    FILE_EDITOR;
    VIM_CONSOLE;
    ALL :: TOP_BAR | FILE_EDITOR | VIM_CONSOLE;
}

ViewLayerData :: union {
    empty: EmptyLayer = ---;
    top_bar: TopBar = ---;
    file_editor: FileEditor = ---;
    vim_console: VimConsole = ---;
}

ViewLayer :: struct {
    type: ViewLayerType;
    using data: ViewLayerData;
}

// if a layer wants a cursor, the cursor should be the first field so we can grab it regardless of the layer type
CursorLayer :: struct($LayerDataType: Type) {
    cursor: Cursor;
    using layer_data: LayerDataType;
}

DummyCursorLayer :: CursorLayer(struct{});

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// layer types

EmptyLayer :: struct {}

TopBar :: struct {}

FileEditor :: CursorLayer(
    struct {
        file_buffer: s64 = -1;
        // upper-left corner within the text file
        view_position: Vector2; 
        // only used for mouse wheel scrolling or anything bound to use mouse wheel-like scrolling
        view_velocity: Vector2;
    }
);

VimConsole :: CursorLayer(
    struct {
        display_only: bool;
    }
);

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

View :: struct {
    viewport: Viewport;
    layers: []ViewLayer;
    children_buffer: [VIEW_CHILDREN_MAX]s16;
    children: []s16;
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

VIEW_CHILDREN_MAX :: 16;
VIEW_LAYERS_MAX :: 16;
VIEWS_MAX :: 128;

active_view_id: s64;
// for storing the active view id when another view temporarily takes precedence
background_view_id: s64 = -1; 
vim_console_id: s64;
kb_cursor_blink_time := 0.68;

view_pool: DynamicPool(View);
view_layer_pool: DynamicPool(ViewLayerChunk);
actions_executed_this_frame: [..]Action;

rendering_scissor_ul: IntVector2;
rendering_scissor_lr: IntVector2;


#scope_file // ------------------------------------------------------------------------------------------------ { FILE }