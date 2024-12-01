
Render_Layer :: (using file_editor: *FileEditor, is_active: bool, render_pass: ViewRenderPass) {
    if render_pass == {
    case .BACKGROUND;
        Render_Quad(Upper_Left(), Lower_Right(), .{rgb=file_editor_background_color, a=1.0});
    case .LINES;
        Render_Quad_Lines(Upper_Left(), Lower_Right(), file_editor_outline_color);
    case;
    }
}