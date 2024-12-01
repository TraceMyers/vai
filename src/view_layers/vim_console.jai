
Render_Layer :: (using vim_console: *VimConsole, is_active: bool, render_pass: ViewRenderPass) {
    if render_pass == {
    case .BACKGROUND;
        Render_Quad(Upper_Left(), Lower_Right(), .{rgb=vim_console_background_color, a=1.0});
    }
}