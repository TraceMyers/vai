
Render_Layer :: (using file_editor: *FileEditor, is_active: bool, render_pass: ViewRenderPass) {
    if render_pass == {
    case .BACKGROUND;
        Render_File_Editor_Background(file_editor, is_active);
    case .LINES;
        Render_File_Editor_Lines(file_editor, is_active);
    case .TEXT;
        Render_File_Editor_Text(file_editor, is_active);
    case .FOREGROUND;
        Render_File_Editor_Foreground(file_editor, is_active);
    case;
    }
}

Render_File_Editor_Background :: (using file_editor: *FileEditor, is_active: bool) {
    Render_Quad(Upper_Left(), Lower_Right(), .{rgb=file_editor_background_color, a=1.0});

    if vi_mode == .VISUAL && is_active {
        renderer: TextRenderer;
        view_layer := View_Layer_From_Data(xx file_editor);
        Initialize_Text_Renderer(*renderer, view_layer);
        text_buffer := *file_buffers.items[file_editor.file_buffer];
    
        Render_Text_Selection_Blocks(*renderer, text_buffer, *cursor);
        Set_Shader_For_Color();
    }
}

Render_File_Editor_Lines :: (using file_editor: *FileEditor, is_active: bool) {
    Render_Quad_Lines(Upper_Left(), Lower_Right(), file_editor_outline_color);
    // TODO: line numbers option
    Render_Gutter_Separator_Line(file_editor_outline_color);
}

Render_File_Editor_Text :: (using file_editor: *FileEditor, is_active: bool) {
    if file_editor.file_buffer < 0 then return;

    renderer: TextRenderer;
    view_layer := View_Layer_From_Data(xx file_editor);
    Initialize_Text_Renderer(*renderer, view_layer);

    text_buffer := *file_buffers.items[file_editor.file_buffer];
    Render_Text_Buffer_Lines(*renderer, text_buffer, true);

    view_max = .{};
    view_line_max := min(cast(s64)(renderer.text_view_clip.y + renderer.line_count - 1), text_buffer.lines.count-1);
    for renderer.text_view_clip.y..view_line_max {
        view_max.x = xx max(cast(float32)Line_Count(text_buffer, it), view_max.x);
    }
    view_max.y = xx (text_buffer.lines.count - 1);

    if is_active {
        Flush_Draws();
        cursor.style = ifx vi_mode == .INSERT then .VERTICAL_LINE else .BLOCK;
        // it's al ittle odd for this to be inside a render function, but it makes use of the text renderer data.
        Cursor_Scroll(file_editor, *renderer);
        Render_Text_Cursor(*renderer, *file_editor.cursor);
    }

    Render_Cursor_Line_Block(*renderer, *file_editor.cursor);

    Set_Shader_For_Text();
}

Render_File_Editor_Foreground :: (using file_editor: *FileEditor, is_active: bool) {
    if file_editor.file_buffer < 0 || !is_active then return;
    view_layer := View_Layer_From_Data(xx file_editor);
    text_buffer := *file_buffers.items[file_editor.file_buffer];
    Render_Scroll_Bar(view_layer, text_buffer);
}

Process_Text_Input :: (using file_editor: *FileEditor, utf32: []u32) {
    if file_editor.file_buffer < 0 then return;
    text_buffer := *file_buffers.items[file_editor.file_buffer];
    Insert_Code_Points(text_buffer, cursor.y, cursor.x, utf32);
    for 0..utf32.count-1 {
        Cursor_Scroll_Right();
    }
}

CursorNet :: struct {
    visible_min: float;
    visible_max: float;
    min: float;
    max: float;
}

Calculate_Cursor_Net :: (bound_min: float, bound_count: float, ideal_net_size: float) -> CursorNet {
    net: CursorNet = ---;
    net.visible_min = bound_min;
    net.visible_max = net.visible_min + max(bound_count, 1) - 1;

    top_bot_diff := net.visible_max - net.visible_min;
    half_diff := top_bot_diff / 2;
    net_size := clamp(half_diff - 1, 0, ideal_net_size);

    net.min = net.visible_min + net_size;
    net.max = net.visible_max - net_size;
    return net;
}

// when the cursor's x or y is outside the visible range, teleport the view to the cursor
Teleport_View_Axis_To_Cursor :: (cursor_axis: float, view_axis: *float, net: *CursorNet) {
    if cursor_axis < net.visible_min {
        net_diff := cursor_axis - net.min;
        view_axis.* += net_diff;
        view_axis.* = max(view_axis.*, 0);
    } else if cursor_axis > net.visible_max {
        net_diff := cursor_axis - net.max;
        view_axis.* += net_diff;
    }
}

Cursor_Scroll :: (using file_editor: *FileEditor, renderer: *TextRenderer) {
    layer := View_Layer_From_Data(xx file_editor);
    layer_cursor := Layer_Cursor(layer);
    if !layer_cursor.just_moved then return;
    layer_cursor.just_moved = false;

    IDEAL_NET_SIZE : float : 8.0;

    vt_net := Calculate_Cursor_Net(layer.view_position.y, xx renderer.line_count, IDEAL_NET_SIZE);
    cursor_y := cast(float)layer_cursor.y;
    Teleport_View_Axis_To_Cursor(cursor_y, *layer.view_position.y, *vt_net);

    ul := Upper_Left();
    lr := Lower_Right();
    viewport_width := lr.x - ul.x;

    col_count := (cast(float) viewport_width / cast(float) renderer.screen_char_width) - (IDEAL_NET_SIZE - 1.0);
    hz_net := Calculate_Cursor_Net(layer.view_position.x, col_count, IDEAL_NET_SIZE);
    cursor_x := cast(float)layer_cursor.x;
    Teleport_View_Axis_To_Cursor(cursor_x, *layer.view_position.x, *hz_net);
}