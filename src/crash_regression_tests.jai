Run_Crash_Regression_Tests :: () {
    Crash_Test_Initialize_View_State();
    defer Crash_Test_Shutdown_View_State();

    assert(Crash_Test_Passive_Command_Bar_Click());
    print("PASS passive command-bar click preserves the base view\n");

    assert(Crash_Test_Repeated_Tool_Focus_And_Hide());
    print("PASS repeated tool focus/hide keeps a bounded stack\n");

    assert(Crash_Test_Tool_Command_Focuses_Open_Tool());
    print("PASS :t/:e focus an open-but-unfocused tool instead of hiding it\n");

    assert(Crash_Test_Closed_View_ID_Reuse());
    print("PASS closed view IDs and layer slots are reused\n");

    assert(Crash_Test_Minimized_Window_Dimensions());
    print("PASS minimized dimensions skip rendering\n");

    assert(Crash_Test_Cycle_From_Non_Editor());
    print("PASS cycling from a non-editor selects the first editor\n");

    assert(Crash_Test_Signed_Captured_Mouse_Coordinates());
    print("PASS captured mouse coordinates remain signed without overflow\n");

    assert(Crash_Test_Collapse_Either_Side_Of_View_Split());
    print("PASS dragging either direction collapses the reached split safely\n");

    assert(Crash_Test_Auto_Collapse_Parks_Mouse_Resize());
    print("PASS layout auto-collapse parks its captured drag at the terminal bar\n");

    assert(Crash_Test_Mouse_Hover_Uses_Live_Edge_Without_Keyboard_Lock());
    print("PASS passive split hover finds the live edge without locking keyboard input\n");

    assert(Crash_Test_Custom_Title_Bar_Geometry());
    print("PASS custom title-bar controls, drag region, and resize edges do not overlap\n");

    assert(Crash_Test_Three_Pane_Drag_Reverses_Through_Both_Bars());
    print("PASS a nested three-pane drag reverses through either collapsed endpoint\n");

    assert(Crash_Test_Async_Result_Poll_Is_Non_Blocking());
    print("PASS preview result polling never waits for a busy worker\n");

    assert(Crash_Test_Latest_Preview_Request_Wins());
    print("PASS only the latest pending file preview is retained\n");

    assert(Crash_Test_Completed_Scene_Task_Invalidates_UI());
    print("PASS a completed scene-preview task invalidates the UI frame\n");

    assert(Crash_Test_Command_Autocomplete_Cycles_And_Escape_Restores());
    print("PASS command autocomplete cycles and Escape restores the typed prefix\n");

    assert(Crash_Test_Command_Autocomplete_Accept_And_Backspace());
    print("PASS command autocomplete accepts or restores before Backspace\n");

    assert(Crash_Test_Set_Option_Autocomplete());
    print("PASS set-option autocomplete filters, cycles, restores, and accepts\n");

    assert(Crash_Test_Interactive_Frame_Time_Filter());
    print("PASS interactive frame pacing rejects hitches without losing its average\n");

    assert(Crash_Test_Smooth_Scroll_Trajectory_Is_Continuous());
    print("PASS smooth scrolling has continuous velocity, low lag, and stable pacing\n");

    print("All 20 crash regression tests passed.\n");
}

Crash_Test_Initialize_View_State :: () {
    crash_test_window_info = .{width=1200, height=800};
    window.info = *crash_test_window_info;
    collapsed_view_bar_thickness_for_tests = 20;

    view_layer_pool.allow_grow_default = false;
    view_layer_pool.allow_shrink_default = false;
    view_pool.allow_grow_default = false;
    view_pool.allow_shrink_default = false;
    Initialize(*view_layer_pool, VIEWS_MAX);
    Initialize(*view_pool, VIEWS_MAX);

    editor_view_stack.data = editor_view_stack_buffer.data;
    editor_view_stack.count = 0;
    previous_selected_view_id = -1;

    root_id := Add_View(.{}, null);
    assert(root_id == ROOT_ID);

    layer: ViewLayer;
    layer.type = .VIM_CONSOLE;
    layer.vim_console = .{};
    vim_console_id = Add_View(.{type=.PIXELS, bottom_pixels=20}, *layer, ROOT_ID);

    layer = .{};
    layer.type = .FILE_EXPLORER;
    layer.file_explorer = .{};
    tool_view_id = Add_View(.{type=.PROPORTION, left=0.3}, *layer, ROOT_ID);

    base_empty_view_id = Add_View(.{type=.PROPORTION, right=0.7}, null, ROOT_ID);

    layer = .{};
    layer.type = .FILE_EDITOR;
    layer.file_editor = .{};
    editor_id := Add_View(.{inverted=true}, *layer, base_empty_view_id);
    Push_Active_View_ID(editor_id);
    tool_view_is_active = true;
}

Crash_Test_Shutdown_View_State :: () {
    Command_Autocomplete_Close(false);
    array_reset(*command_autocomplete.initial_input);
    array_reset(*command_autocomplete.matches);
    array_reset(*auxiliary_input_buffer);
    editor_view_stack.count = 0;
    Shutdown(*view_layer_pool);
    Shutdown(*view_pool);
    array_reset(*mouse_events);
    collapsed_view_bar_thickness_for_tests = -1;
    window.info = null;
}

Crash_Test_Base_Editor_ID :: () -> s64 {
    return view_pool.items[base_empty_view_id].children[0];
}

Crash_Test_Passive_Command_Bar_Click :: () -> bool {
    editor_id := Crash_Test_Base_Editor_ID();
    Activate_Mouse_View(vim_console_id);
    if editor_view_stack.count != 1 || Active_View_ID() != editor_id {
        return false;
    }

    Push_Active_View_ID(vim_console_id);
    Activate_Mouse_View(editor_id);
    return editor_view_stack.count == 1 && Active_View_ID() == editor_id;
}

Crash_Test_Repeated_Tool_Focus_And_Hide :: () -> bool {
    editor_id := Crash_Test_Base_Editor_ID();
    for 0..editor_view_stack_buffer.count * 2 {
        if !Focus_Overlay_View_ID(tool_view_id) {
            return false;
        }
        if editor_view_stack.count != 2 || Active_View_ID() != tool_view_id {
            return false;
        }
        if !Deactivate_Active_Overlay_View_ID(tool_view_id, editor_id) {
            return false;
        }
        if editor_view_stack.count != 1 || Active_View_ID() != editor_id {
            return false;
        }
    }
    return true;
}

// Verifies the focus-aware tool commands: showing/toggling a tool that is open
// but not focused moves the cursor into it (rather than hiding it), and Show is
// idempotent when it is already focused.  The init state is the key case: the
// tool panel is visible while the editor holds focus.
Crash_Test_Tool_Command_Focuses_Open_Tool :: () -> bool {
    editor_id := Crash_Test_Base_Editor_ID();
    no_args: [][]u32;

    // Precondition from init: tool shown (FILE_EXPLORER) but editor focused.
    if !tool_view_is_active || Active_View_ID() != editor_id  return false;

    // :t on an open-but-unfocused tool focuses it (must not hide it).
    Execute_Command_Toggle_Tool_View(no_args);
    if !tool_view_is_active || Active_View_ID() != tool_view_id  return false;

    // Move focus back to the editor; the tool stays visible.
    if !Deactivate_Active_Overlay_View_ID(tool_view_id, editor_id)  return false;
    if !tool_view_is_active || Active_View_ID() != editor_id  return false;

    // :e on an open-but-unfocused explorer moves the cursor into it.
    Execute_Command_Toggle_File_Explorer(no_args);
    if !tool_view_is_active || Active_View_ID() != tool_view_id  return false;

    // Show on an already-visible+focused tool is idempotent.
    Execute_Command_Show_Tool_View(.FILE_EXPLORER);
    if !tool_view_is_active || Active_View_ID() != tool_view_id  return false;

    // Restore the init invariant (editor focused) for subsequent tests.
    Deactivate_Active_Overlay_View_ID(tool_view_id, editor_id);
    return tool_view_is_active && Active_View_ID() == editor_id;
}

Crash_Test_Closed_View_ID_Reuse :: () -> bool {
    editor_id := Crash_Test_Base_Editor_ID();
    first_recycled_id: s64 = -1;
    for 0..VIEWS_MAX * 2 {
        split := Split_View(View_From_ID(editor_id), .HORIZONTAL, false);
        if split == null {
            return false;
        }
        view_id := split - view_pool.items.data;
        if first_recycled_id < 0 {
            first_recycled_id = view_id;
        } else if view_id != first_recycled_id {
            return false;
        }

        Close_View(view_id);
        if Is_Item_In_Use(*view_pool, view_id) {
            return false;
        }
        if !Is_Item_In_Use(*view_pool, base_empty_view_id) {
            return false;
        }
        base := View_From_ID(base_empty_view_id);
        if base.children.count != 1 || base.children[0] != editor_id {
            return false;
        }
    }
    return true;
}

Crash_Test_Minimized_Window_Dimensions :: () -> bool {
    return !Window_Dimensions_Are_Renderable(0, 0)
        && !Window_Dimensions_Are_Renderable(100, 0)
        && !Window_Dimensions_Are_Renderable(0, 100)
        && Window_Dimensions_Are_Renderable(1, 1);
}

Crash_Test_Cycle_From_Non_Editor :: () -> bool {
    sort_info := EditorSortInfo.[
        .{view_id=11},
        .{view_id=22},
        .{view_id=33},
    ];
    return Next_Editor_Index(99, sort_info) == 0
        && Next_Editor_Index(11, sort_info) == 1
        && Next_Editor_Index(33, sort_info) == 0
        && Next_Editor_Index(11, EditorSortInfo.[]) == -1;
}

Crash_Test_Signed_Captured_Mouse_Coordinates :: () -> bool {
    negative_x := Mouse_Position_From_LParam(cast(LPARAM)0x0002_ffff);
    negative_y := Mouse_Position_From_LParam(cast(LPARAM)0xffff_0002);
    if negative_x != IntVector2.{-1, 2} || negative_y != IntVector2.{2, -1} {
        return false;
    }

    mouse_interaction = .{};
    mouse_interaction.press_position = .{32767, 32767};
    return Mouse_Drag_Passed_Threshold(.{-32768, -32768});
}

Crash_Test_Collapse_Either_Side_Of_View_Split :: () -> bool {
    first_id := Crash_Test_Base_Editor_ID();
    first := View_From_ID(first_id);
    second := Split_View(first, .HORIZONTAL, false);
    if second == null {
        return false;
    }
    second_id := second - view_pool.items.data;
    Replace_Active_View_ID(second_id);
    edge, side, found_edge := Get_Direct_View_Split_Edge(first);
    if !found_edge {
        print("collapse regression: no initial edge\n");
        return false;
    }

    collapsed_first := Resize_View_Edge_To_Proportion(*edge, side, 0.0, 0.5, 0.5);
    if !collapsed_first || !first.hidden || second.hidden || Active_View_ID() != second_id {
        print("collapse regression: first %, hidden %/%, active % expected %\n",
            collapsed_first, first.hidden, second.hidden, Active_View_ID(), second_id);
        return false;
    }
    if !Show_View(first_id) {
        print("collapse regression: could not restore first\n");
        return false;
    }

    edge, side, found_edge = Get_Direct_View_Split_Edge(first);
    if !found_edge {
        print("collapse regression: no restored edge\n");
        return false;
    }
    collapsed_second := Resize_View_Edge_To_Proportion(*edge, side, 1.0, 0.5, 0.5);
    if !collapsed_second || first.hidden || !second.hidden || Active_View_ID() != first_id {
        print("collapse regression: second %, hidden %/%, active % expected %\n",
            collapsed_second, first.hidden, second.hidden, Active_View_ID(), first_id);
        return false;
    }
    return true;
}

Crash_Test_Auto_Collapse_Parks_Mouse_Resize :: () -> bool {
    first_id := Crash_Test_Base_Editor_ID();
    first := View_From_ID(first_id);
    edge, side, found_edge := Get_Direct_View_Split_Edge(first);
    if !found_edge {
        return false;
    }
    second_id := edge[1] - view_pool.items.data;
    if !Show_View(second_id) {
        return false;
    }

    mouse_interaction = .{};
    mouse_interaction.active = true;
    mouse_interaction.mode = .VIEW_EDGE;
    mouse_interaction.edge = edge;
    mouse_interaction.edge_side = side;
    mouse_interaction.edge_total_length = 1000;
    mouse_interaction.edge_start_proportion = 0.5;
    mouse_interaction.edge_restore_first_proportion = 0.5;
    mouse_interaction.edge_restore_second_proportion = 0.5;
    Balance_View_Edge(*edge, side, 0.999);
    Collapse_Views_At_Or_Below_Bar_Size();
    second := View_From_ID(second_id);
    if !second.hidden
    || abs(second.hidden_saved_proportion - 0.5) > 0.0001
    || mouse_interaction.mode != .VIEW_EDGE {
        return false;
    }

    Resize_Mouse_View_Edge(.{1000, 0});
    return mouse_interaction.mode == .VIEW_EDGE && second.hidden;
}

Crash_Test_Mouse_Hover_Uses_Live_Edge_Without_Keyboard_Lock :: () -> bool {
    first := View_From_ID(Crash_Test_Base_Editor_ID());
    edge, side, found_edge := Get_Direct_View_Split_Edge(first);
    if !found_edge {
        return false;
    }
    second_id := edge[1] - view_pool.items.data;
    if !Show_View(second_id) {
        return false;
    }

    first_id := first - view_pool.items.data;
    rect, found_rect := Find_View_Screen_Rect(first_id, ROOT_ID, Window_Viewport_Rect());
    if !found_rect {
        return false;
    }
    ul, lr := Viewport_Rect_Points(*rect, s32);
    position: IntVector2 = .{(ul.x + lr.x) / 2, (ul.y + lr.y) / 2};
    if side == {
    case .LEFT;
        position.x = ul.x;
    case .RIGHT;
        position.x = lr.x;
    case .TOP;
        position.y = ul.y;
    case .BOTTOM;
        position.y = lr.y;
    }
    hit := Mouse_View_Hit.{first, first_id, ul, lr};
    hover_edge, hover_side, found_hover := Find_Mouse_View_Resize_Edge(hit, position);
    if !found_hover || hover_side != side || hover_edge[0] != edge[0] || hover_edge[1] != edge[1] {
        return false;
    }

    mouse_left_button_down = false;
    mouse_interaction = .{};
    array_reset_keeping_memory(*mouse_events);
    Take_Mouse_Event(.MOVE, position);
    if Mouse_Input_Locks_Keyboard() || !Process_Mouse_Input() {
        return false;
    }
    if !mouse_hover_position_is_known || mouse_hover_position != position || Mouse_Input_Locks_Keyboard() {
        return false;
    }

    Take_Mouse_Event(.LEAVE, .{});
    return Process_Mouse_Input() && !mouse_hover_position_is_known;
}

Crash_Test_Mouse_Position_For_Proportion :: (
    side: Side2D,
    press_position: IntVector2,
    start_proportion: float,
    total_length: s32,
    requested_proportion: float
) -> IntVector2 {
    side_sign := ifx side == .RIGHT || side == .BOTTOM then 1.0 else -1.0;
    pixel_delta: s32 = xx ((requested_proportion - start_proportion) * cast(float)total_length / side_sign);
    position := press_position;
    if side == .LEFT || side == .RIGHT {
        position.x += pixel_delta;
    } else {
        position.y += pixel_delta;
    }
    return position;
}

Crash_Test_Custom_Title_Bar_Geometry :: () -> bool {
    if Scale_Custom_Title_Bar_Metric(CUSTOM_TITLE_BAR_HEIGHT_96, 96) != 28
    || Scale_Custom_Title_Bar_Metric(CUSTOM_TITLE_BAR_HEIGHT_96, 192) != 56 {
        return false;
    }
    workspace_rect := Window_Viewport_Rect();
    if workspace_rect.y != 28
    || workspace_rect.dimensions.x != crash_test_window_info.width
    || workspace_rect.dimensions.y != crash_test_window_info.height-28 {
        return false;
    }

    width: s32 = 1000;
    height: s32 = 700;
    title_bar_height: s32 = 28;
    button_width: s32 = 36;
    minimize_ul, minimize_lr := Custom_Title_Bar_Button_Rect(.MINIMIZE, width, title_bar_height, button_width);
    maximize_ul, maximize_lr := Custom_Title_Bar_Button_Rect(.MAXIMIZE, width, title_bar_height, button_width);
    close_ul, close_lr := Custom_Title_Bar_Button_Rect(.CLOSE, width, title_bar_height, button_width);
    if minimize_ul != IntVector2.{892, 0}
    || minimize_lr != IntVector2.{928, 28}
    || maximize_ul != IntVector2.{928, 0}
    || maximize_lr != IntVector2.{964, 28}
    || close_ul != IntVector2.{964, 0}
    || close_lr != IntVector2.{1000, 28} {
        return false;
    }

    if Custom_Title_Bar_Button_At(.{910, 14}, width, title_bar_height, button_width) != .MINIMIZE
    || Custom_Title_Bar_Button_At(.{946, 14}, width, title_bar_height, button_width) != .MAXIMIZE
    || Custom_Title_Bar_Button_At(.{982, 14}, width, title_bar_height, button_width) != .CLOSE
    || Custom_Title_Bar_Button_At(.{500, 14}, width, title_bar_height, button_width) != .NONE {
        return false;
    }

    resize_border: s32 = 6;
    // Win32 non-client hit codes: HTCLIENT=1, HTCAPTION=2,
    // HTTOP=12, and HTTOPLEFT=13.
    return Win32_Custom_Frame_Hit_Test(.{2, 2}, width, height, title_bar_height, button_width, resize_border, false) == 13
        && Win32_Custom_Frame_Hit_Test(.{500, 2}, width, height, title_bar_height, button_width, resize_border, false) == 12
        && Win32_Custom_Frame_Hit_Test(.{982, 14}, width, height, title_bar_height, button_width, resize_border, false) == 1
        && Win32_Custom_Frame_Hit_Test(.{500, 14}, width, height, title_bar_height, button_width, resize_border, false) == 2
        && Win32_Custom_Frame_Hit_Test(.{500, 100}, width, height, title_bar_height, button_width, resize_border, false) == 1
        && Win32_Custom_Frame_Hit_Test(.{500, 2}, width, height, title_bar_height, button_width, resize_border, true) == 2;
}

Crash_Test_Three_Pane_Drag_Reverses_Through_Both_Bars :: () -> bool {
    left := View_From_ID(Crash_Test_Base_Editor_ID());
    outer_edge, unused_side, found_outer_edge := Get_Direct_View_Split_Edge(left);
    if !found_outer_edge {
        return false;
    }
    right := outer_edge[1];
    lower := Split_View(right, .VERTICAL, false);
    if lower == null {
        return false;
    }

    edge, side, found_edge := Get_Direct_View_Split_Edge(right);
    if !found_edge {
        return false;
    }
    first_id := edge[0] - view_pool.items.data;
    second_id := edge[1] - view_pool.items.data;
    total_length: s32 = 800;
    press_position: IntVector2 = .{400, 400};

    mouse_interaction = .{};
    mouse_interaction.active = true;
    mouse_interaction.mode = .VIEW_EDGE;
    mouse_interaction.edge = edge;
    mouse_interaction.edge_side = side;
    mouse_interaction.edge_total_length = total_length;
    mouse_interaction.press_position = press_position;
    mouse_interaction.edge_start_proportion = 0.5;
    mouse_interaction.edge_restore_first_proportion = 0.5;
    mouse_interaction.edge_restore_second_proportion = 0.5;

    Resize_Mouse_View_Edge(Crash_Test_Mouse_Position_For_Proportion(side, press_position, 0.5, total_length, 0.0));
    if !View_From_ID(first_id).hidden || View_From_ID(second_id).hidden || mouse_interaction.mode != .VIEW_EDGE {
        return false;
    }
    Resize_Mouse_View_Edge(Crash_Test_Mouse_Position_For_Proportion(side, press_position, 0.5, total_length, 0.25));
    if View_From_ID(first_id).hidden || View_From_ID(second_id).hidden {
        return false;
    }
    Resize_Mouse_View_Edge(Crash_Test_Mouse_Position_For_Proportion(side, press_position, 0.5, total_length, 1.0));
    if View_From_ID(first_id).hidden || !View_From_ID(second_id).hidden || mouse_interaction.mode != .VIEW_EDGE {
        return false;
    }
    Resize_Mouse_View_Edge(Crash_Test_Mouse_Position_For_Proportion(side, press_position, 0.5, total_length, 0.75));
    if View_From_ID(first_id).hidden || View_From_ID(second_id).hidden {
        return false;
    }
    Resize_Mouse_View_Edge(Crash_Test_Mouse_Position_For_Proportion(side, press_position, 0.5, total_length, 0.0));
    if !View_From_ID(first_id).hidden || View_From_ID(second_id).hidden {
        return false;
    }

    parent_id := Find_Parent(first_id);
    if parent_id < 0 || Find_Parent(second_id) != parent_id {
        return false;
    }

    // A fresh press on the bar must reuse the same attached edge without
    // asking Show_View to resolve an orphaned/stale view family.
    edge[0].pixel_dimensions.y = total_length / 2;
    edge[1].pixel_dimensions.y = total_length / 2;
    mouse_interaction = .{};
    mouse_interaction.active = true;
    mouse_interaction.view_id = first_id;
    mouse_interaction.press_position = press_position;
    Begin_Collapsed_View_Drag(first_id);
    if mouse_interaction.mode != .COLLAPSED_VIEW || !View_Edge_Is_Live(*mouse_interaction.edge) {
        return false;
    }
    reveal_position := Crash_Test_Mouse_Position_For_Proportion(
        mouse_interaction.edge_side,
        press_position,
        mouse_interaction.edge_start_proportion,
        mouse_interaction.edge_total_length,
        0.25
    );
    Update_Collapsed_View_Drag(reveal_position);
    return mouse_interaction.mode == .VIEW_EDGE
        && !View_From_ID(first_id).hidden
        && !View_From_ID(second_id).hidden;
}

Crash_Test_Completed_Scene_Task_Invalidates_UI :: () -> bool {
    return Crash_Test_Completed_Scene_Task_Invalidates_UI_Impl();
}

Crash_Test_Async_Result_Poll_Is_Non_Blocking :: () -> bool {
    return Crash_Test_Async_Result_Poll_Is_Non_Blocking_Impl();
}

Crash_Test_Latest_Preview_Request_Wins :: () -> bool {
    return Crash_Test_Latest_Preview_Request_Wins_Impl();
}

Crash_Test_Set_Command_Input :: (text: string) {
    array_reset_keeping_memory(*auxiliary_input_buffer);
    for text {
        array_add(*auxiliary_input_buffer, cast(u32)it);
    }
}

Crash_Test_Command_Input_Equals :: (text: string) -> bool {
    if auxiliary_input_buffer.count != text.count {
        return false;
    }
    for text {
        if Remove_Modifier_Flags(auxiliary_input_buffer[it_index]) != cast(u32)it {
            return false;
        }
    }
    return true;
}

Crash_Test_Command_Autocomplete_Cycles_And_Escape_Restores :: () -> bool {
    Command_Autocomplete_Close(false);
    Crash_Test_Set_Command_Input("b");
    Command_Autocomplete_Advance();
    if !Command_Autocomplete_Is_Open() || command_autocomplete.matches.count != 2 {
        return false;
    }

    first_selected := command_autocomplete.selected_index;
    first_name := command_autocomplete.matches[first_selected].input;
    if !Crash_Test_Command_Input_Equals(first_name) {
        return false;
    }

    Command_Autocomplete_Advance();
    if command_autocomplete.selected_index == first_selected {
        return false;
    }
    second_name := command_autocomplete.matches[command_autocomplete.selected_index].input;
    if !Crash_Test_Command_Input_Equals(second_name) {
        return false;
    }

    saved_vi_mode := vi_mode;
    vi_mode = .COMMAND;
    Enter_Normal_Mode();
    restored := vi_mode == .COMMAND
        && !Command_Autocomplete_Is_Open()
        && Crash_Test_Command_Input_Equals("b");
    vi_mode = saved_vi_mode;
    return restored;
}

Crash_Test_Command_Autocomplete_Accept_And_Backspace :: () -> bool {
    Command_Autocomplete_Close(false);
    Crash_Test_Set_Command_Input("pro");
    Command_Autocomplete_Advance();
    if !Command_Autocomplete_Is_Open() {
        return false;
    }

    selected_name := command_autocomplete.matches[command_autocomplete.selected_index].input;
    Command_Mode_Return();
    if Command_Autocomplete_Is_Open() || !Crash_Test_Command_Input_Equals(selected_name) {
        return false;
    }

    Crash_Test_Set_Command_Input("pro");
    Command_Autocomplete_Advance();
    if !Command_Autocomplete_Cancel() {
        return false;
    }
    auxiliary_input_buffer.count = max(auxiliary_input_buffer.count - 1, 0);
    return !Command_Autocomplete_Is_Open() && Crash_Test_Command_Input_Equals("pr");
}

Crash_Test_Set_Option_Autocomplete :: () -> bool {
    Command_Autocomplete_Close(false);
    Crash_Test_Set_Command_Input("set so");
    Command_Autocomplete_Advance();
    if !Command_Autocomplete_Is_Open()
    || command_autocomplete.matches.count != 2
    || command_autocomplete.replacement_start != 4
    || !Crash_Test_Command_Input_Equals("set soft-wrap") {
        return false;
    }

    Command_Autocomplete_Advance();
    if !Crash_Test_Command_Input_Equals("set soft-wrap-indent") {
        return false;
    }
    if !Command_Autocomplete_Cancel() || !Crash_Test_Command_Input_Equals("set so") {
        return false;
    }

    Crash_Test_Set_Command_Input("set ");
    Command_Autocomplete_Advance();
    if !Command_Autocomplete_Is_Open()
    || command_autocomplete.matches.count != option_mappings.count
    || !Crash_Test_Command_Input_Equals("set line-numbers") {
        return false;
    }
    Command_Mode_Return();
    return !Command_Autocomplete_Is_Open()
        && Crash_Test_Command_Input_Equals("set line-numbers");
}

Crash_Test_Interactive_Frame_Time_Filter :: () -> bool {
    stable_samples := float64.[
        0.0067, 0.0075, 0.0069, 0.0072, 0.0068, 0.0073, 0.0070,
    ];
    stable_dt := Robust_Interactive_Delta_Time(*stable_samples, 0.007);

    hitch_samples := stable_samples;
    hitch_samples[1] = 0.080;
    hitch_samples[5] = 0.120;
    hitch_dt := Robust_Interactive_Delta_Time(*hitch_samples, 0.007);

    sixty_fps_samples: [INTERACTIVE_DELTA_TIME_HISTORY_COUNT]float64;
    for *sixty_fps_samples {
        it.* = 1.0 / 60.0;
    }
    sixty_fps_dt := Robust_Interactive_Delta_Time(*sixty_fps_samples, 0.007);

    return stable_dt > 0.0068
        && stable_dt < 0.0072
        && abs(hitch_dt-stable_dt) < 0.0003
        && abs(sixty_fps_dt-cast(float32)(1.0/60.0)) < 0.00001;
}

Crash_Test_Smooth_Scroll_Trajectory_Is_Continuous :: () -> bool {
    frame_samples: [INTERACTIVE_DELTA_TIME_HISTORY_COUNT]float64;
    for *frame_samples {
        it.* = 1.0 / 120.0;
    }

    view: float;
    cursor_axis: float;
    previous_step: float;
    minimum_step: float = 1000;
    maximum_step: float;
    maximum_step_change: float;
    for frame_index: 0..239 {
        raw_dt := 1.0 / 120.0;
        if frame_index % 3 == 0 {
            raw_dt = 1.0 / 132.0;
        } else if frame_index % 3 == 1 {
            raw_dt = 1.0 / 109.0;
        }
        if frame_index == 90 {
            raw_dt = 0.080;
        }
        frame_samples[frame_index % INTERACTIVE_DELTA_TIME_HISTORY_COUNT] = raw_dt;

        if frame_index % 4 == 0 {
            cursor_axis += 1;
        }
        if frame_index == 90 {
            cursor_axis += 2;
        }

        filtered_dt := Robust_Interactive_Delta_Time(*frame_samples, raw_dt);
        previous_view := view;
        Smooth_View_Axis_Toward_Cursor(
            *view,
            cursor_axis,
            view,
            8.0,
            true,
            30.0,
            filtered_dt,
            true,
        );
        frame_step := view - previous_view;
        if frame_index >= 24 {
            minimum_step = min(minimum_step, frame_step);
            maximum_step = max(maximum_step, frame_step);
            maximum_step_change = max(maximum_step_change, abs(frame_step-previous_step));
        }
        previous_step = frame_step;
    }

    ideal_step := 30.0 / 120.0;
    if minimum_step <= ideal_step * 0.92
    || maximum_step >= ideal_step * 1.08
    || maximum_step_change >= ideal_step * 0.05
    || cursor_axis-view >= 3.0 {
        return false;
    }

    // A sustained hold should cover the same distance at very different
    // rendering frequencies.
    view_60: float;
    cursor_60: float;
    for frame_index: 0..59 {
        if frame_index % 2 == 0 {
            cursor_60 += 1;
        }
        Smooth_View_Axis_Toward_Cursor(
            *view_60, cursor_60, view_60, 8.0, true, 30.0, 1.0/60.0, true,
        );
    }

    view_240: float;
    cursor_240: float;
    for frame_index: 0..239 {
        if frame_index % 8 == 0 {
            cursor_240 += 1;
        }
        Smooth_View_Axis_Toward_Cursor(
            *view_240, cursor_240, view_240, 8.0, true, 30.0, 1.0/240.0, true,
        );
    }
    if abs(view_60-view_240) >= 0.05 {
        return false;
    }

    // Without fresh repeats, catch up to the cursor exactly; while repeats
    // continue, never predict more than two rows beyond it.
    catchup_view: float;
    still_catching_up := Smooth_View_Axis_Toward_Cursor(
        *catchup_view, 0.5, 0.0, 8.0, true, 40.0, 1.0, false,
    );
    if still_catching_up || abs(catchup_view-0.5) >= 0.0001 {
        return false;
    }

    predicted_view: float;
    for 0..9 {
        Smooth_View_Axis_Toward_Cursor(
            *predicted_view, 0.0, predicted_view, 8.0, true, 40.0, 1.0, true,
        );
    }
    if abs(predicted_view-2.0) >= 0.0001 {
        return false;
    }

    repeat_cursor: Cursor;
    repeat_cursor.move_history.current_index = 6;
    repeat_cursor.move_history.timestamps[0] = 1.0;
    repeat_cursor.move_history.timestamps[1] = 1.3;
    repeat_cursor.move_history.timestamps[2] = 1.333;
    repeat_cursor.move_history.timestamps[3] = 1.338;
    repeat_cursor.move_history.timestamps[4] = 1.371;
    repeat_cursor.move_history.timestamps[5] = 1.404;
    for 0..5 {
        repeat_cursor.move_history.actions[it] = .SCROLL_DOWN;
    }
    single_press_cursor: Cursor;
    single_press_cursor.move_history.current_index = 1;
    single_press_cursor.move_history.timestamps[0] = 1.0;
    single_press_cursor.move_history.actions[0] = .SCROLL_DOWN;
    if Cursor_Latest_Move_Was_Repeated(*single_press_cursor, .SCROLL_DOWN) {
        return false;
    }
    robust_repeat_rate := Cursor_Scroll_Repeat_Rate(*repeat_cursor, .SCROLL_DOWN, 40.0);
    return robust_repeat_rate > 29.0 && robust_repeat_rate < 32.0;
}

crash_test_window_info: WindowInfo;
