
Render_Layer :: (using vim_console: *VimConsole, is_active: bool, render_pass: ViewRenderPass) {
    if !is_active then return;

    view := Active_View();
    view.viewport.bottom_pixels = Integer_Option_Value(.FONT_SIZE) * 2;

    if render_pass == { 
    case .BACKGROUND;
        Render_Quad(Upper_Left(), Lower_Right(), vim_console_background_color, depth=VIM_CONSOLE_DEPTH);
    case .TEXT;
        Render_Vim_Console_Text(vim_console, is_active);
    case .FOREGROUND;
        if vim_console.mode == .COMMAND && Command_Autocomplete_Is_Open() {
            Render_Command_Autocomplete_Overlay();
        }
    }
}

Render_Command_Autocomplete_Overlay :: () {
    if command_autocomplete.matches.count == 0 || font == null {
        return;
    }

    console_ul := Upper_Left();
    console_lr := Lower_Right();
    padding: s32 = 6;
    column_gap: s32 = 18;
    row_height: s32 = xx (get_baseline_height(font) * 4);
    row_height += xx (cast(float32)row_height * line_spacing_factor);
    row_height = max(row_height, 1);

    popup_bottom := console_ul.y - 2;
    available_content_height := popup_bottom - padding*2;
    visible_count := min(
        command_autocomplete.matches.count,
        cast(s64)max(available_content_height / row_height, 0),
    );
    if visible_count <= 0 {
        return;
    }

    max_command_char_count: s64;
    max_description_char_count: s64;
    for command_autocomplete.matches {
        max_command_char_count = max(max_command_char_count, it.input.count);
        max_description_char_count = max(max_description_char_count, it.description.count);
    }

    character_width := Width(font);
    desired_width := padding*2
        + xx max_command_char_count*character_width
        + column_gap
        + xx max_description_char_count*character_width;
    popup_left := max(console_ul.x, 0);
    popup_right := min(max(console_lr.x, popup_left), popup_left + desired_width);
    popup_height := padding*2 + xx visible_count*row_height;
    popup_top := popup_bottom - popup_height;
    popup_ul := IntVector2.{popup_left, popup_top};
    popup_lr := IntVector2.{popup_right, popup_bottom};
    if popup_lr.x <= popup_ul.x || popup_lr.y <= popup_ul.y {
        return;
    }

    first_index := max(command_autocomplete.selected_index - visible_count/2, 0);
    first_index = min(first_index, command_autocomplete.matches.count - visible_count);

    saved_scissor_ul := rendering_scissor_ul;
    saved_scissor_lr := rendering_scissor_lr;
    rendering_scissor_ul = popup_ul;
    rendering_scissor_lr = popup_lr;
    Set_Scissor(rendering_scissor_ul, rendering_scissor_lr);
    defer {
        Flush_Draws();
        rendering_scissor_ul = saved_scissor_ul;
        rendering_scissor_lr = saved_scissor_lr;
        Set_Scissor(rendering_scissor_ul, rendering_scissor_lr);
    }

    Set_Shader_For_Blended_Color();
    Render_Quad(popup_ul, popup_lr, .{0.025, 0.08, 0.11, 0.97});
    highlight_y_offset := max(row_height/8, 2);
    for 0..visible_count-1 {
        match_index := first_index + it;
        if match_index != command_autocomplete.selected_index {
            continue;
        }
        row_top := popup_top + padding + xx it*row_height + highlight_y_offset;
        Render_Quad(
            .{popup_left + 1, row_top},
            .{popup_right - 1, row_top + row_height},
            .{0.10, 0.25, 0.31, 0.95},
        );
    }
    Flush_Draws();

    Set_Shader_For_Lines();
    Render_Quad_Lines(popup_ul, popup_lr, .{0.42, 0.50, 0.52, 0.55});
    Flush_Draws();

    command_x := popup_left + padding;
    description_x := command_x + xx max_command_char_count*character_width + column_gap;
    for 0..visible_count-1 {
        match_index := first_index + it;
        match := command_autocomplete.matches[match_index];
        text_y := popup_top + padding + xx (it+1)*row_height;
        Render_Text_String_At(match.input, command_x, text_y, .{0.72, 0.78, 0.79, 0.96});
        Render_Text_String_At(match.description, description_x, text_y, .{0.46, 0.52, 0.54, 0.84});
    }
}

Render_Vim_Console_Text :: (using vim_console: *VimConsole, is_active: bool) {
    renderer: TextRenderer;
    view_layer := View_Layer_From_Data(xx vim_console);
    Initialize_Text_Renderer(*renderer, view_layer, 2);
    renderer.screen_render_begin.y = Upper_Left().y + cast(s32)(cast(float)Integer_Option_Value(.FONT_SIZE) * 1.4);
    tabbed_buffer_chars := Expand_Tabs(auxiliary_input_buffer, 4);
    // renderer.screen_render_begin.y -= 3;

    prefix := ifx vim_console.mode == .COMMAND then ":" else "/"; // command or search
    Immediate_Render_Marked_Line(*renderer, tabbed_buffer_chars, bRGB_WHITE, prefix, VIM_CONSOLE_TEXT_DEPTH);

    cursor.style = .VERTICAL_LINE;
    cursor.x = xx (tabbed_buffer_chars.count + 1);
    cursor.y = 0;
    renderer.cursor_pos = .{cursor.x, cursor.y};
    ul, lr := Render_Text_Cursor(*renderer, *vim_console.cursor, false, VIM_CONSOLE_TEXT_DEPTH);
    Set_Shader_For_Text();
}
