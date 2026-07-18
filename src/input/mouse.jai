
Mouse_Event_Type :: enum u8 {
    LEFT_DOWN;
    LEFT_DOUBLE_CLICK;
    LEFT_UP;
    MOVE;
    LEAVE;
}

Mouse_Event :: struct {
    type: Mouse_Event_Type;
    position: IntVector2;
}

Mouse_Interaction_Mode :: enum u8 {
    NONE;
    CURSOR;
    SELECTION;
    VIEW_EDGE;
    FILE_EXPLORER_PREVIEW;
    COLLAPSED_VIEW;
    COLLAPSED_FILE_EXPLORER_PREVIEW;
}

Mouse_Interaction :: struct {
    active: bool;
    mode: Mouse_Interaction_Mode;
    view_id: s64 = -1;
    view_ul: IntVector2;
    view_lr: IntVector2;
    press_position: IntVector2;
    selection_begin: IntVector2;
    edge: [2]*View;
    edge_side: Side2D;
    edge_start_proportion: float;
    edge_restore_first_proportion: float;
    edge_restore_second_proportion: float;
    edge_total_length: s32;
}

Mouse_View_Hit :: struct {
    view: *View;
    view_id: s64 = -1;
    ul: IntVector2;
    lr: IntVector2;
}

Mouse_Position_From_LParam :: (l_param: LPARAM) -> IntVector2 {
    x := cast(s32)(l_param & 0xffff);
    y := cast(s32)((l_param >> 16) & 0xffff);
    if (x & 0x8000) != 0 then x -= 0x1_0000;
    if (y & 0x8000) != 0 then y -= 0x1_0000;
    return .{
        x,
        y,
    };
}

Take_Mouse_Event :: (type: Mouse_Event_Type, position: IntVector2) {
    array_add(*mouse_events, .{type, position});
}

Cancel_Mouse_Interaction :: () {
    mouse_left_button_down = false;
    mouse_interaction = .{};
    array_reset_keeping_memory(*mouse_events);
}

Mouse_Input_Locks_Keyboard :: () -> bool {
    if mouse_left_button_down || mouse_interaction.active {
        return true;
    }
    for mouse_events {
        if it.type != .MOVE && it.type != .LEAVE {
            return true;
        }
    }
    return false;
}

Discard_Keyboard_Input_For_Mouse :: () {
    Discard_Platform_Keyboard_Input_For_Mouse();
    array_reset_keeping_memory(*action_input_buffer);
    array_reset_keeping_memory(*action_repeat_buffer);
    array_reset_keeping_memory(*frame_input_stream);
    frame_input_stream_index = -1;
    // Reset() changes the array length to zero. Rendering queries the four
    // arrow-key bits every frame, so retain the initialized capacity and only
    // clear its held-key state.
    Clear(*key_pressed);
}

Process_Mouse_Input :: () -> bool {
    Platform_Refresh_Mouse_Buttons();
    if mouse_events.count == 0 {
        return false;
    }

    for mouse_events {
        if it.type != .LEAVE {
            mouse_hover_position = it.position;
            mouse_hover_position_is_known = true;
        }
        if it.type == {
        case .LEFT_DOWN;
            Begin_Mouse_Interaction(it.position);
        case .LEFT_DOUBLE_CLICK;
            Begin_Mouse_Double_Click(it.position);
        case .MOVE;
            Update_Mouse_Interaction(it.position);
        case .LEFT_UP;
            Update_Mouse_Interaction(it.position);
            mouse_interaction = .{};
        case .LEAVE;
            mouse_hover_position_is_known = false;
        }
    }
    array_reset_keeping_memory(*mouse_events);
    return true;
}

Begin_Mouse_Interaction :: (position: IntVector2) {
    mouse_interaction = .{};
    mouse_interaction.active = true;
    mouse_interaction.press_position = position;

    hit := Find_Mouse_View_Hit(position);
    if hit.view == null {
        return;
    }
    mouse_interaction.view_id = hit.view_id;
    mouse_interaction.view_ul = hit.ul;
    mouse_interaction.view_lr = hit.lr;

    if hit.view.hidden {
        Activate_Mouse_View(hit.view_id);
        vi_mode = .NORMAL;
        Begin_Collapsed_View_Drag(hit.view_id);
        return;
    }

    layer := Active_Layer_Of_View(hit.view);
    if layer == null {
        return;
    }

    // The explorer's internal divider gets first claim on a drag.  This keeps
    // its continuous preview resize independent from the outer view splitter.
    if layer.type == .FILE_EXPLORER {
        if layer.file_explorer.preview_hidden {
            preview_ul, preview_lr := File_Explorer_Preview_Box(hit.ul, hit.lr, File_Explorer_Preview_Proportion(*layer.file_explorer), true);
            if Mouse_Point_In_Rect(position, preview_ul, preview_lr) {
                Activate_Mouse_View(hit.view_id);
                vi_mode = .NORMAL;
                mouse_interaction.mode = .COLLAPSED_FILE_EXPLORER_PREVIEW;
                return;
            }
        } else {
            divider_y := File_Explorer_Preview_Divider_Y(hit.ul, hit.lr, File_Explorer_Preview_Proportion(*layer.file_explorer));
            if abs(position.y - divider_y) <= MOUSE_RESIZE_GRAB_RADIUS {
                mouse_interaction.mode = .FILE_EXPLORER_PREVIEW;
                return;
            }
        }
    }

    if Begin_Mouse_View_Edge_Resize(hit, position) {
        return;
    }

    Activate_Mouse_View(hit.view_id);
    cursor_position, found_cursor := Mouse_Cursor_Position(hit, position);
    if !found_cursor {
        return;
    }

    cursor := Layer_Cursor(layer);
    if cursor == null {
        return;
    }
    if vi_mode == .VISUAL {
        vi_mode = .NORMAL;
    }
    Set_Mouse_Cursor_Position(cursor, cursor_position);
    mouse_interaction.selection_begin = cursor_position;
    if layer.type == .FILE_EDITOR {
        mouse_interaction.mode = .CURSOR;
    }
}

Begin_Mouse_Double_Click :: (position: IntVector2) {
    hit := Find_Mouse_View_Hit(position);
    if hit.view == null {
        return;
    }

    if hit.view.hidden {
        Activate_Mouse_View(hit.view_id);
        Show_View(hit.view_id);
        vi_mode = .NORMAL;
        mouse_interaction = .{};
        return;
    }

    layer := Active_Layer_Of_View(hit.view);
    if layer != null && layer.type == .FILE_EXPLORER && layer.file_explorer.preview_hidden {
        preview_ul, preview_lr := File_Explorer_Preview_Box(hit.ul, hit.lr, File_Explorer_Preview_Proportion(*layer.file_explorer), true);
        if Mouse_Point_In_Rect(position, preview_ul, preview_lr) {
            Activate_Mouse_View(hit.view_id);
            Show_File_Explorer_Preview(*layer.file_explorer, hit.lr.y - hit.ul.y);
            vi_mode = .NORMAL;
            mouse_interaction = .{};
            return;
        }
    }

    Begin_Mouse_Interaction(position);
}

Begin_Collapsed_View_Drag :: (view_id: s64) {
    resize_view := View_From_ID(view_id);
    parent_id := Find_Parent(view_id);
    while parent_id >= 0 {
        parent := View_From_ID(parent_id);
        if parent.hidden_group && parent.hidden_group_collapsed {
            resize_view = parent;
            break;
        }
        parent_id = Find_Parent(parent_id);
    }

    edge, side, found_edge := Get_Direct_View_Split_Edge(resize_view);
    if !found_edge {
        edge, side, found_edge = Get_Direct_View_Split_Edge(View_From_ID(view_id));
    }
    mouse_interaction.mode = .COLLAPSED_VIEW;
    if !found_edge {
        return;
    }
    side_opposite := Opposite(side);
    mouse_interaction.edge = edge;
    mouse_interaction.edge_side = side;
    mouse_interaction.edge_total_length = ifx side == .LEFT || side == .RIGHT
        then edge[0].pixel_dimensions.x + edge[1].pixel_dimensions.x
        else edge[0].pixel_dimensions.y + edge[1].pixel_dimensions.y;
    mouse_interaction.edge_start_proportion = edge[0].viewport.offsets[side_opposite];
    mouse_interaction.edge_restore_first_proportion = mouse_interaction.edge_start_proportion;
    mouse_interaction.edge_restore_second_proportion = 1.0 - mouse_interaction.edge_start_proportion;
    if edge[0].hidden {
        mouse_interaction.edge_restore_first_proportion = edge[0].hidden_saved_proportion;
    } else if edge[0].hidden_group && edge[0].hidden_group_collapsed {
        mouse_interaction.edge_restore_first_proportion = edge[0].hidden_group_saved_proportion;
    }
    if edge[1].hidden {
        mouse_interaction.edge_restore_second_proportion = edge[1].hidden_saved_proportion;
    } else {
        mouse_interaction.edge_restore_second_proportion = 1.0 - mouse_interaction.edge_restore_first_proportion;
    }
    if resize_view == View_From_ID(view_id)
    && View_Has_Hidden_Group_Ancestor(view_id)
    && mouse_interaction.edge_total_length > 0 {
        // A full-workspace hidden group has a horizontal shelf rather than an
        // external collapsed edge. Treat the selected leaf as collapsed on its
        // own split so the drag distance, not stale internal geometry, sets
        // the revealed size.
        mouse_interaction.edge_start_proportion =
            cast(float)Collapsed_View_Bar_Thickness(side) / cast(float)mouse_interaction.edge_total_length;
    }
}

Update_Mouse_Interaction :: (position: IntVector2) {
    if !mouse_interaction.active {
        return;
    }

    if mouse_interaction.mode == {
    case .VIEW_EDGE;
        Resize_Mouse_View_Edge(position);
    case .FILE_EXPLORER_PREVIEW;
        Resize_Mouse_File_Explorer_Preview(position);
    case .COLLAPSED_VIEW;
        Update_Collapsed_View_Drag(position);
    case .COLLAPSED_FILE_EXPLORER_PREVIEW;
        Update_Collapsed_File_Explorer_Preview_Drag(position);
    case .CURSOR; #through;
    case .SELECTION;
        Update_Mouse_Cursor_Selection(position);
    case;
    }
}

Mouse_Drag_Passed_Threshold :: (position: IntVector2) -> bool {
    mouse_delta_x := cast(s64)position.x - cast(s64)mouse_interaction.press_position.x;
    mouse_delta_y := cast(s64)position.y - cast(s64)mouse_interaction.press_position.y;
    return mouse_delta_x * mouse_delta_x + mouse_delta_y * mouse_delta_y
        >= cast(s64)MOUSE_DRAG_START_DISTANCE * cast(s64)MOUSE_DRAG_START_DISTANCE;
}

Mouse_Drag_Passed_Split_Axis_Threshold :: (position: IntVector2, side: Side2D) -> bool {
    delta := ifx side == .LEFT || side == .RIGHT
        then position.x - mouse_interaction.press_position.x
        else position.y - mouse_interaction.press_position.y;
    return abs(delta) >= MOUSE_DRAG_START_DISTANCE;
}

Update_Collapsed_View_Drag :: (position: IntVector2) {
    has_resize_edge := View_Edge_Is_Live(*mouse_interaction.edge)
        && mouse_interaction.edge_total_length > 0;
    passed_threshold := ifx has_resize_edge
        then Mouse_Drag_Passed_Split_Axis_Threshold(position, mouse_interaction.edge_side)
        else Mouse_Drag_Passed_Threshold(position);
    if !passed_threshold {
        return;
    }
    if !has_resize_edge {
        mouse_interaction.mode = .NONE;
        return;
    }

    // For an ordinary collapsed pane, leave it hidden until the pointer
    // actually reverses away from its terminal bar. A collapsed ancestor group
    // still needs its selected leaf revealed before its outer edge can move.
    edge_has_hidden_leaf := mouse_interaction.edge[0].hidden || mouse_interaction.edge[1].hidden;
    if !edge_has_hidden_leaf {
        if !View_ID_Is_Selectable(mouse_interaction.view_id)
        || !View_From_ID(mouse_interaction.view_id).hidden
        || !Show_View(mouse_interaction.view_id) {
            mouse_interaction.mode = .NONE;
            return;
        }
    }

    mouse_interaction.mode = .VIEW_EDGE;
    Resize_Mouse_View_Edge(position);
}

Update_Collapsed_File_Explorer_Preview_Drag :: (position: IntVector2) {
    if !Mouse_Drag_Passed_Split_Axis_Threshold(position, .TOP) {
        return;
    }
    view := View_From_ID(mouse_interaction.view_id);
    layer := Active_Layer_Of_View(view);
    if layer == null || layer.type != .FILE_EXPLORER {
        return;
    }
    layer.file_explorer.preview_hidden = false;
    mouse_interaction.mode = .FILE_EXPLORER_PREVIEW;
    Resize_Mouse_File_Explorer_Preview(position);
}

Activate_Mouse_View :: (view_id: s64) {
    active_view_id := Active_View_ID();
    if view_id == vim_console_id {
        // The command bar is only an input target while command mode has
        // already pushed it. Clicking the passive status bar must not replace
        // the sole editor entry in the active-view stack.
        return;
    }

    if View_ID_Uses_Overlay_Stack(active_view_id) && active_view_id != view_id {
        if editor_view_stack.count > 1 {
            Pop_Active_View_ID();
        }
        vi_mode = .NORMAL;
    }

    if view_id == tool_view_id {
        Focus_Overlay_View_ID(view_id);
    } else if Active_View_ID() != view_id {
        Replace_Active_View_ID(view_id);
    }
}

Begin_Mouse_View_Edge_Resize :: (hit: Mouse_View_Hit, position: IntVector2) -> bool {
    edge, side, found_edge := Find_Mouse_View_Resize_Edge(hit, position);
    if !found_edge {
        return false;
    }

    side_opposite := Opposite(side);
    mouse_interaction.mode = .VIEW_EDGE;
    mouse_interaction.edge = edge;
    mouse_interaction.edge_side = side;
    mouse_interaction.edge_start_proportion = edge[0].viewport.offsets[side_opposite];
    mouse_interaction.edge_restore_first_proportion = mouse_interaction.edge_start_proportion;
    mouse_interaction.edge_restore_second_proportion = 1.0 - mouse_interaction.edge_start_proportion;
    mouse_interaction.edge_total_length = ifx side == .LEFT || side == .RIGHT
        then edge[0].pixel_dimensions.x + edge[1].pixel_dimensions.x
        else edge[0].pixel_dimensions.y + edge[1].pixel_dimensions.y;
    return true;
}

Find_Mouse_View_Resize_Edge :: (hit: Mouse_View_Hit, position: IntVector2) -> edge: [2]*View, side: Side2D, found: bool {
    empty_edge: [2]*View;
    sides := Side2D.[.LEFT, .TOP, .RIGHT, .BOTTOM];
    for sides {
        distance := ifx it == .LEFT then abs(position.x - hit.ul.x)
            else ifx it == .RIGHT then abs(position.x - hit.lr.x)
            else ifx it == .TOP then abs(position.y - hit.ul.y)
            else abs(position.y - hit.lr.y);
        if distance > MOUSE_RESIZE_GRAB_RADIUS {
            continue;
        }

        candidate_edge, candidate_side := Get_View_Edge(hit.view, it);
        if !View_Edge_Is_Live(*candidate_edge) {
            continue;
        }
        if candidate_edge[0].hidden || candidate_edge[1].hidden {
            continue;
        }
        return candidate_edge, candidate_side, true;
    }
    return empty_edge, .LEFT, false;
}

View_Edge_Is_Live :: (edge: *[2]*View) -> bool {
    view_ids: [2]s64;
    for edge.* {
        if it == null {
            return false;
        }
        view_id := it - view_pool.items.data;
        if view_id < 0 || view_id >= view_pool.items.count || !Is_Item_In_Use(*view_pool, view_id) {
            return false;
        }
        view_ids[it_index] = view_id;
    }
    first_parent_id := Find_Parent(view_ids[0]);
    return first_parent_id >= 0 && Find_Parent(view_ids[1]) == first_parent_id;
}

Resize_Mouse_View_Edge :: (position: IntVector2) {
    if mouse_interaction.edge_total_length <= 0
    || !View_Edge_Is_Live(*mouse_interaction.edge) {
        mouse_interaction.mode = .NONE;
        return;
    }
    mouse_delta: s64 = ifx mouse_interaction.edge_side == .LEFT || mouse_interaction.edge_side == .RIGHT
        then cast(s64)position.x - cast(s64)mouse_interaction.press_position.x
        else cast(s64)position.y - cast(s64)mouse_interaction.press_position.y;
    side_sign := ifx mouse_interaction.edge_side == .RIGHT || mouse_interaction.edge_side == .BOTTOM then 1.0 else -1.0;
    proportion := mouse_interaction.edge_start_proportion
        + side_sign * cast(float)mouse_delta / cast(float)mouse_interaction.edge_total_length;

    edge := mouse_interaction.edge;
    side := mouse_interaction.edge_side;
    total_length := View_Split_Parent_Axis_Length(edge[0], side);
    first_minimum := Collapsed_View_Bar_Proportion(side, total_length);
    second_minimum := Collapsed_View_Bar_Proportion(Opposite(side), total_length);
    first_id := edge[0] - view_pool.items.data;
    second_id := edge[1] - view_pool.items.data;

    if edge[0].hidden {
        if proportion <= first_minimum {
            Balance_View_Edge(*edge, side, first_minimum);
            return;
        }
        if !Show_View(first_id) {
            mouse_interaction.mode = .NONE;
            return;
        }
    }
    if edge[1].hidden {
        if 1.0 - proportion <= second_minimum {
            Balance_View_Edge(*edge, side, 1.0 - second_minimum);
            return;
        }
        if !Show_View(second_id) {
            mouse_interaction.mode = .NONE;
            return;
        }
    }
    if !View_Edge_Is_Live(*edge) {
        mouse_interaction.mode = .NONE;
        return;
    }

    Resize_View_Edge_To_Proportion(
        *mouse_interaction.edge,
        side,
        proportion,
        mouse_interaction.edge_restore_first_proportion,
        mouse_interaction.edge_restore_second_proportion
    );
}

Resize_Mouse_File_Explorer_Preview :: (position: IntVector2) {
    view := View_From_ID(mouse_interaction.view_id);
    layer := Active_Layer_Of_View(view);
    if layer == null || layer.type != .FILE_EXPLORER {
        return;
    }
    proportion := File_Explorer_Preview_Proportion_From_Divider_Y(mouse_interaction.view_ul, mouse_interaction.view_lr, position.y);
    Set_File_Explorer_Preview_Proportion(*layer.file_explorer, proportion, mouse_interaction.view_lr.y - mouse_interaction.view_ul.y);
}

Update_Mouse_Cursor_Selection :: (position: IntVector2) {
    view := View_From_ID(mouse_interaction.view_id);
    hit := Mouse_View_Hit.{view, mouse_interaction.view_id, mouse_interaction.view_ul, mouse_interaction.view_lr};
    layer := Active_Layer_Of_View(view);
    if layer == null || layer.type != .FILE_EDITOR {
        return;
    }

    cursor_position, found_cursor := Mouse_Cursor_Position(hit, position);
    if !found_cursor {
        return;
    }
    cursor := Layer_Cursor(layer);
    if cursor == null {
        return;
    }

    if mouse_interaction.mode == .CURSOR
    && Mouse_Drag_Passed_Threshold(position) {
        vi_mode = .VISUAL;
        cursor.begin_selection = mouse_interaction.selection_begin;
        mouse_interaction.mode = .SELECTION;
    }

    if mouse_interaction.mode == .SELECTION {
        Set_Mouse_Cursor_Position(cursor, cursor_position);
    }
}

Set_Mouse_Cursor_Position :: (cursor: *Cursor, position: IntVector2) {
    cursor.x = position.x;
    cursor.y = position.y;
    cursor.target_x = position.x;
    cursor.soft_wrap_target_x = -1;
    cursor.just_moved = true;
    cursor.reset_blink = true;
}

Mouse_Cursor_Position :: (hit: Mouse_View_Hit, position: IntVector2) -> IntVector2, bool {
    layer := Active_Layer_Of_View(hit.view);
    if layer == null {
        return .{}, false;
    }
    buffer := Layer_Text_Buffer(layer);
    if buffer == null || buffer.lines.count == 0 {
        return .{}, false;
    }

    // Wrapped-line measurement uses the current rendering scissor.  Mouse
    // input happens before the render pass, so temporarily provide the hit
    // view's bounds while converting screen coordinates to text coordinates.
    saved_scissor_ul := rendering_scissor_ul;
    saved_scissor_lr := rendering_scissor_lr;
    rendering_scissor_ul = hit.ul;
    rendering_scissor_lr = hit.lr;
    defer {
        rendering_scissor_ul = saved_scissor_ul;
        rendering_scissor_lr = saved_scissor_lr;
    }

    text_ul, text_lr := hit.ul, hit.lr;
    force_gutter_width: s32 = -1;
    if layer.type == .FILE_EXPLORER {
        directory_list_ul, directory_list_lr := File_Explorer_Directory_List_Box(
            hit.ul,
            hit.lr,
            File_Explorer_Preview_Proportion(*layer.file_explorer),
            layer.file_explorer.preview_hidden
        );
        if !Mouse_Point_In_Rect(position, directory_list_ul, directory_list_lr) {
            return .{}, false;
        }
        text_ul, text_lr = directory_list_ul, directory_list_lr;
        force_gutter_width = 8;
    } else if !Mouse_Point_In_Rect(position, text_ul, text_lr) {
        return .{}, false;
    }

    renderer: TextRenderer;
    Initialize_Text_Renderer(*renderer, layer, force_gutter_width, text_ul, text_lr);
    if !renderer.initialized || renderer.screen_char_width <= 0 || renderer.screen_line_height <= 0 {
        return .{}, false;
    }
    if layer.type == .FILE_EXPLORER {
        renderer.screen_render_begin.y += 1;
    }

    cursor_position: IntVector2;
    if layer.type == .FILE_EDITOR && Bool_Option_Value(.SOFT_WRAP) {
        cursor_position = Mouse_Soft_Wrap_Cursor_Position(layer, buffer, *renderer, text_ul, position);
    } else {
        cursor_position.y = renderer.text_view_clip.y + max((position.y - text_ul.y) / renderer.screen_line_height, 0);
        cursor_position.y = clamp(cursor_position.y, 0, sdw(buffer.lines.count - 1));
        line := Line_View(buffer, cursor_position.y);
        cursor_position.x = renderer.text_view_clip.x + (position.x - renderer.screen_render_begin.x) / renderer.screen_char_width;
        cursor_position.x = Clamp_X_To_Line(cursor_position.x, line);
    }

    if layer.type == .FILE_EXPLORER {
        clamp_cursor := Cursor.{x=cursor_position.x, y=cursor_position.y};
        if cursor_position.y == 1 {
            clamp_cursor.y = 0;
        }
        File_Explorer_Clamp_Y_To_Directory_List(*clamp_cursor);
        if clamp_cursor.y == 0 {
            File_Explorer_Reset_Cursor_On_Path(*clamp_cursor, buffer);
        }
        cursor_position = .{clamp_cursor.x, clamp_cursor.y};
    } else if layer.type == .PROJECT_EXPLORER {
        clamp_cursor := Cursor.{x=cursor_position.x, y=cursor_position.y};
        Project_Explorer_Clamp_Cursor(*clamp_cursor, buffer);
        cursor_position = .{clamp_cursor.x, clamp_cursor.y};
    }
    return cursor_position, true;
}

Mouse_Soft_Wrap_Cursor_Position :: (layer: *ViewLayer, buffer: *TextBuffer, renderer: *TextRenderer, text_ul: IntVector2, position: IntVector2) -> IntVector2 {
    row_lengths := Temp_Resize_Array(s32);
    current_line := clamp(cast(s32)Floor(layer.view_position.y), 0, sdw(buffer.lines.count - 1));
    continuation_indent := Get_Soft_Wrap_Row_Lengths(layer, current_line, *row_lengths);
    if row_lengths.count == 0 {
        array_add(*row_lengths, 0);
    }

    fractional_line_position := layer.view_position.y - cast(float)current_line;
    visual_row := cast(s32)Floor(cast(float)(position.y - text_ul.y) / cast(float)renderer.screen_line_height
        + fractional_line_position * cast(float)row_lengths.count);
    visual_row = max(visual_row, 0);

    while visual_row >= row_lengths.count && current_line < buffer.lines.count - 1 {
        visual_row -= xx row_lengths.count;
        current_line += 1;
        continuation_indent = Get_Soft_Wrap_Row_Lengths(layer, current_line, *row_lengths);
        if row_lengths.count == 0 {
            array_add(*row_lengths, 0);
        }
    }
    visual_row = clamp(visual_row, 0, sdw(row_lengths.count - 1));

    row_start: s32;
    if visual_row > 0 {
        for 0..visual_row-1 {
            row_start += row_lengths[it];
        }
    }
    visual_x := (position.x - renderer.screen_render_begin.x) / renderer.screen_char_width;
    cursor_x := Soft_Wrap_X_From_Visual_X(row_start, row_lengths[visual_row], visual_row, continuation_indent, visual_x);
    return .{cursor_x, current_line};
}

Find_Mouse_View_Hit :: (position: IntVector2) -> Mouse_View_Hit {
    return Find_Mouse_View_Hit_Recursive(ROOT_ID, Window_Viewport_Rect(), position);
}

Find_Mouse_View_Hit_Recursive :: (view_id: s64, rect: ViewportRect, position: IntVector2) -> Mouse_View_Hit {
    ul, lr := Viewport_Rect_Points(*rect, s32);
    if !Mouse_Point_In_Rect(position, ul, lr) {
        return .{};
    }

    view := View_From_ID(view_id);
    // The hidden tool view keeps a zero left viewport offset; the generic
    // viewport code treats that as an unshaved full-window rectangle. Its
    // renderer explicitly skips it, so hit testing must do the same or it
    // steals every click from the visible editor behind it.
    if view_id == tool_view_id && view.viewport.left <= 0.0 {
        return .{};
    }
    if view.hidden_group {
        hidden_view_ids: [..]s64;
        hidden_view_ids.allocator = temp;
        Collect_Hidden_Leaf_View_IDs(view_id, *hidden_view_ids);
        side := Hidden_Group_Shelf_Side(view);
        for hidden_view_ids {
            tab_ul, tab_lr := Hidden_Group_Tab_Rect(ul, lr, side, it_index, hidden_view_ids.count);
            if Mouse_Point_In_Rect(position, tab_ul, tab_lr) {
                return .{View_From_ID(it), it, tab_ul, tab_lr};
            }
        }
        return .{};
    }
    for view.children {
        child := View_From_ID(it);
        child_rect := rect;
        Apply_Viewport_To_Rect(*child_rect, *child.viewport);
        hit := Find_Mouse_View_Hit_Recursive(it, child_rect, position);
        if hit.view != null {
            return hit;
        }
    }
    if view.layers.data != null {
        return .{view, view_id, ul, lr};
    }
    return .{};
}

Mouse_Point_In_Rect :: (position: IntVector2, ul: IntVector2, lr: IntVector2) -> bool {
    return position.x >= ul.x && position.x < lr.x && position.y >= ul.y && position.y < lr.y;
}

MOUSE_RESIZE_GRAB_RADIUS :: 6;
MOUSE_DRAG_START_DISTANCE :: 3;

mouse_events: [..]Mouse_Event;
mouse_left_button_down: bool;
mouse_interaction: Mouse_Interaction;
mouse_hover_position: IntVector2;
mouse_hover_position_is_known: bool;
