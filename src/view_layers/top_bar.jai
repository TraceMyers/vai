
Render_Layer :: (using top_bar: *TopBar, is_active: bool, render_pass: ViewRenderPass) {
    if render_pass == {
    case .BACKGROUND;
        Render_Quad(Upper_Left(), Lower_Right(), .{rgb=top_bar_background_color, a=1.0});
    }
}