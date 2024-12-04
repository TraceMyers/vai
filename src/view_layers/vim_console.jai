
Render_Layer :: (using vim_console: *VimConsole, is_active: bool, render_pass: ViewRenderPass) {
    if !is_active then return;

    if render_pass == .BACKGROUND {
        Render_Quad(Upper_Left(), Lower_Right(), vim_console_background_color, depth=VIM_CONSOLE_DEPTH);
    }
}