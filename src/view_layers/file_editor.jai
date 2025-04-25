
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
    Render_Quad(rendering_scissor_ul, rendering_scissor_lr, .{rgb=file_editor_background_color, a=1.0});
    
    if Bool_Option_Value(.LINE_NUMBERS) {
        renderer: TextRenderer;
        view_layer := View_Layer_From_Data(xx file_editor);
        Initialize_Text_Renderer(*renderer, view_layer, -1);
        gutter_lower_right := rendering_scissor_lr;
        gutter_lower_right.x = rendering_scissor_ul.x + renderer.screen_gutter_width;
        
        max_channel_index := Channel_Max(file_editor_background_color);
        max_channel := file_editor_background_color.channels[max_channel_index];
        gutter_color := file_editor_background_color * 0.72;
        gutter_color.channels[max_channel_index] = max_channel * 0.2 + gutter_color.channels[max_channel_index] * 0.8;


        Render_Quad(rendering_scissor_ul, gutter_lower_right, .{rgb=gutter_color, a=1.0});
    }
}

Render_File_Editor_Lines :: (using file_editor: *FileEditor, is_active: bool) {
    Render_Quad_Lines(Upper_Left(), Lower_Right(), file_editor_outline_color);
    if Bool_Option_Value(.LINE_NUMBERS) {
        Render_Gutter_Separator_Line(file_editor_line_numbers_sep_color);
    }
}

Render_File_Editor_Text :: (using file_editor: *FileEditor, is_active: bool) {
    if file_editor.file_buffer < 0 then return;

    draw_line_numbers := Bool_Option_Value(.LINE_NUMBERS);
    override_gutter_size := ifx draw_line_numbers then sdw(-1) else sdw(0);

    renderer: TextRenderer;
    view_layer := View_Layer_From_Data(xx file_editor);
    Initialize_Text_Renderer(*renderer, view_layer, override_gutter_size);

    if is_active {
        // it's al ittle odd for this to be inside a render function, but it makes use of the text renderer data.
        View_Scroll(view_layer, *renderer, *file_buffers.items[file_editor.file_buffer]);
        // view might move, need to reinit
        Initialize_Text_Renderer(*renderer, view_layer, override_gutter_size);
    }

    text_buffer := *file_buffers.items[file_editor.file_buffer];
    Render_Text_Buffer_Lines(view_layer, *renderer, text_buffer, draw_line_numbers);

    view_max = .{};
    view_line_max := min(cast(s64)(renderer.text_view_clip.y + renderer.line_count - 1), text_buffer.lines.count-1);
    if view_line_max >= renderer.text_view_clip.y {
        for renderer.text_view_clip.y..view_line_max {
            view_max.x = xx max(cast(float32)Line_Count(text_buffer, it), view_max.x);
        }
    }
    view_max.y = xx (text_buffer.lines.count - 1);

    if is_active {
        Flush_Draws();
        cursor.style = ifx vi_mode == .INSERT then .VERTICAL_LINE else .BLOCK;
        Render_Text_Cursor(*renderer, *file_editor.cursor);
    }

    if vi_mode != .VISUAL || !is_active {
        Render_Cursor_Line_Block(*renderer, *file_editor.cursor);
    }
    Set_Shader_For_Text();

    if is_active {
        Add_Debug_Text(sprint("view y: %", view_layer.view_position.y));
    }
}

Render_File_Editor_Foreground :: (using file_editor: *FileEditor, is_active: bool) {
    if file_editor.file_buffer < 0 || !is_active then return;
    view_layer := View_Layer_From_Data(xx file_editor);
    text_buffer := *file_buffers.items[file_editor.file_buffer];
    Render_Scroll_Bar(view_layer, text_buffer);

    if vi_mode == .VISUAL {
        renderer: TextRenderer;
        Initialize_Text_Renderer(*renderer, view_layer);
        Render_Text_Selection_Blocks(*renderer, text_buffer, *cursor);
    }
}

Process_Text_Input :: (using file_editor: *FileEditor, utf32: []u32) {
    if file_buffer < 0 then return;
    text_buffer := *file_buffers.items[file_buffer];
    at_line_end := cursor.x == Line_Count(text_buffer, cursor.y);
    Insert_Code_Points(text_buffer, cursor.y, cursor.x, utf32);
    for 0..utf32.count-1 {
        Cursor_Scroll_Right();
    }
}

// a top and bottom net attacked to the center of the viewport that the cursor pulls on
CursorNet :: struct {
    visible_min: float;
    visible_max: float;
    min: float;
    max: float;
    size: float;
}

Calculate_Cursor_Net :: (bound_min: float, bound_count: float, ideal_net_size: float) -> CursorNet {
    net: CursorNet = ---;
    net.visible_min = bound_min;
    net.visible_max = net.visible_min + max(bound_count, 1) - 1;

    top_bot_diff := net.visible_max - net.visible_min;
    half_diff := top_bot_diff / 2;
    net.size = clamp(half_diff - 1, 0, ideal_net_size);

    net.min = net.visible_min + net.size;
    net.max = net.visible_max - net.size;
    return net;
}

// when the cursor's x or y is outside the visible net range, teleport the view to the cursor
Teleport_View_Axis_To_Cursor :: (cursor_axis: float, view_axis: *float, net: *CursorNet) {
    hard_scroll_min := net.visible_min + net.size;
    hard_scroll_max := net.visible_max - net.size;
    if cursor_axis < hard_scroll_min {
        net_diff := cursor_axis - hard_scroll_min;
        view_axis.* += net_diff;
    } else if cursor_axis > hard_scroll_max {
        net_diff := cursor_axis - hard_scroll_max;
        view_axis.* += net_diff;
    }
    view_axis.* = max(view_axis.*, 0);
}

View_Axis_Follow_Cursor_Smoothly :: (cursor: *Cursor, view_axis: *float, cursor_axis: float, net_boundary: float, net_size: float, action: Action, compare_greater: bool, scroll_speed: float) {
    if cursor.active_scroll_action != action {
        if compare_greater {
            if cursor_axis > net_boundary {
                cursor.active_scroll_action = action;
            }
        } else if cursor_axis < net_boundary {
            cursor.active_scroll_action = action;
        }
    }
    if cursor.active_scroll_action == action {
        CORRECTION_SPEED :: 1.0;
        target_pos_diff := cursor_axis - net_boundary;
        correction_norm := target_pos_diff / net_size;
        if !compare_greater {
            scroll_speed = -scroll_speed;
        }
        view_axis.* += (scroll_speed + CORRECTION_SPEED * correction_norm) * Smoothed_Delta_Time();
        view_axis.* = max(view_axis.*, 0);
    }
}

View_Scroll :: (layer: *ViewLayer, renderer: *TextRenderer, text_buffer: *TextBuffer) {
    layer_cursor := Layer_Cursor(layer);
    file_editor := layer.file_editor;

    IDEAL_NET_SIZE : float : 8.0;

    if layer_cursor.just_moved {
        text_buffer.saved_cursor = layer_cursor.*;
    }

    new_y := layer.view_position.y;

    vt_net := Calculate_Cursor_Net(new_y, xx renderer.line_count, IDEAL_NET_SIZE);
    cursor_y := cast(float)layer_cursor.y;
    if layer_cursor.just_moved {
        Teleport_View_Axis_To_Cursor(cursor_y, *new_y, *vt_net);
    }

    ul := Upper_Left();
    lr := Lower_Right();
    viewport_width := lr.x - ul.x;

    col_count := (cast(float) viewport_width / cast(float) renderer.screen_char_width) - (IDEAL_NET_SIZE - 1.0);
    hz_net := Calculate_Cursor_Net(layer.view_position.x, col_count, IDEAL_NET_SIZE);
    cursor_x := cast(float)layer_cursor.x;
    if layer_cursor.just_moved {
        Teleport_View_Axis_To_Cursor(cursor_x, *layer.view_position.x, *hz_net);
    }

    layer_cursor.just_moved = false;

    if layer_cursor.y < text_buffer.lines.count - 1 {
        scroll_down_repeat, scroll_down_speed := Get_Action_Repeat_Rate(layer_cursor, .SCROLL_DOWN);
        scroll_up_repeat, scroll_up_speed := Get_Action_Repeat_Rate(layer_cursor, .SCROLL_UP);
        scroll_right_repeat, scroll_right_speed := Get_Action_Repeat_Rate(layer_cursor, .SCROLL_RIGHT);
        scroll_left_repeat, scroll_left_speed := Get_Action_Repeat_Rate(layer_cursor, .SCROLL_LEFT);

        if scroll_down_repeat {
            View_Axis_Follow_Cursor_Smoothly(layer_cursor, *new_y, cursor_y, vt_net.max, vt_net.size, .SCROLL_DOWN, true, scroll_down_speed);
        } else if scroll_up_repeat {
            View_Axis_Follow_Cursor_Smoothly(layer_cursor, *new_y, cursor_y, vt_net.min, vt_net.size, .SCROLL_UP, false, scroll_up_speed);
        } else if scroll_right_repeat {
            View_Axis_Follow_Cursor_Smoothly(layer_cursor, *layer.view_position.x, cursor_x, hz_net.max, hz_net.size, .SCROLL_RIGHT, true, scroll_right_speed);
        } else if scroll_left_repeat {
            View_Axis_Follow_Cursor_Smoothly(layer_cursor, *layer.view_position.x, cursor_x, hz_net.min, hz_net.size, .SCROLL_LEFT, false, scroll_left_speed);
        } else {
            layer_cursor.active_scroll_action = .NONE;
        }
    }

    new_y = clamp(new_y, 0, cast(float)(text_buffer.lines.count-1));
    if Bool_Option_Value(.SOFT_WRAP) {
        layer.view_position.x = 0;
    } else {
        layer.view_position.x = max(layer.view_position.x, 0);
    }

    y_delta := new_y - layer.view_position.y;
    y_delta_abs := abs(y_delta);
    if y_delta_abs > 0 {
        if y_delta > 0 {
            text_buffer := Layer_Text_Buffer(layer);
            if text_buffer {
                Move_View_Y(layer, y_delta_abs, xx (text_buffer.lines.count-1), .DOWN);
            }
        } else {
            Move_View_Y(layer, y_delta_abs, 0, .UP);
        }
    }
}

Open_File_In_Editor :: (file_editor: *FileEditor, filename: string, create_if_doesnt_exist: bool) -> bool {
    new_buffer_id := Get_File_Buffer_ID(filename);
    if new_buffer_id == -1 {
        if !create_if_doesnt_exist {
            return false;
        }
        write_entire_file(filename, "");
        new_buffer_id = Get_File_Buffer_ID(filename);
        if new_buffer_id == -1 {
            return false;
        }
    }
    file_editor.file_buffer = new_buffer_id;
    // each file buffer has its a cursor position cached by file editors when they move
    file_editor.cursor = file_buffers.items[new_buffer_id].saved_cursor;
    Center_View_On_Cursor(View_Layer_From_Data(xx file_editor), xx file_buffers.items[new_buffer_id].lines.count);
    return true;
}