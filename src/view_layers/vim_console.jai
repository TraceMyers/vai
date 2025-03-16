
Render_Layer :: (using vim_console: *VimConsole, is_active: bool, render_pass: ViewRenderPass) {
    if !is_active then return;

    view := Active_View();
    view.viewport.bottom_pixels = Integer_Option_Value(.FONT_SIZE) * 2;

    if render_pass == { 
    case .BACKGROUND;
        Render_Quad(Upper_Left(), Lower_Right(), vim_console_background_color, depth=VIM_CONSOLE_DEPTH);
    case .TEXT;
        Render_Vim_Console_Text(vim_console, is_active);
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
    ul, lr := Render_Text_Cursor(*renderer, *vim_console.cursor, false, VIM_CONSOLE_TEXT_DEPTH);
    Set_Shader_For_Text();
}