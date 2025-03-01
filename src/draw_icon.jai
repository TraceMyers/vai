
Draw_Folder_Icon :: (renderer: *TextRenderer, text_x: s32, text_y: s32, color: *fRGBA) {
    urx, ury := Text_To_Render_Space(renderer, text_x, text_y);
    // main rectangle
    ury += 4;
    lrx, lry := urx, ury;
    lrx += renderer.screen_char_width * 5 / 2;
    lry += renderer.screen_line_height - 8;
    Render_Quad(.{urx, ury}, .{lrx, lry}, color.*);
    // tiny rectangle / tab
    ury -= 2;
    lrx -= 2 * (lrx - urx) / 3;
    lry = ury + 2;
    Render_Quad(.{urx, ury}, .{lrx, lry}, color.*);
}

Draw_Text_File_Icon :: (renderer: *TextRenderer, text_x: s32, text_y: s32, alpha: float) {
    color := fRGBA.{rgb=.{0.8, 0.8, 0.85}, a=alpha};
    urx, ury := Text_To_Render_Space(renderer, text_x, text_y);
    // main rectangle
    urx += renderer.screen_char_width / 2;
    ury += 2;
    lrx, lry := urx, ury;
    lrx += renderer.screen_char_width * 3 / 2;
    lry += renderer.screen_line_height - 4;
    Render_Quad(.{urx, ury}, .{lrx, lry}, color);
    y_quarter_diff := renderer.screen_line_height / 4;
    ury -= 1;
    c := color;
    c.r = min(c.r * 1.25, 1.0);
    c.g = min(c.g * 1.25, 1.0);
    c.b = min(c.b * 1.25, 1.0);
    Render_Quad(.{urx+2, ury}, .{lrx-2, ury+(y_quarter_diff*3)+2}, c);
}

Draw_Code_File_Icon :: (renderer: *TextRenderer, text_x: s32, text_y: s32, alpha: float) {
    color := fRGBA.{rgb=.{0.94, 0.77, 0.835}, a=alpha};
    urx, ury := Text_To_Render_Space(renderer, text_x, text_y);
    // main rectangle
    urx += renderer.screen_char_width / 2;
    ury += 2;
    lrx, lry := urx, ury;
    lrx += renderer.screen_char_width * 3 / 2;
    lry += renderer.screen_line_height - 4;
    Render_Quad(.{urx, ury}, .{lrx, lry}, color);
    y_quarter_diff := renderer.screen_line_height / 4;
    ury -= 1;
    lry -= (renderer.screen_line_height - 2) / 2;
    lrx -= renderer.screen_char_width * 3 / 4;
    c := color;
    c.r *= 0.25;
    c.g *= 0.25;
    c.b *= 0.25;
    Render_Quad(.{urx, ury}, .{lrx, lry}, c);
}

Draw_Binary_File_Icon :: (renderer: *TextRenderer, text_x: s32, text_y: s32, alpha: float) {
    color := fRGBA.{rgb=.{0.72, 0.75, 0.98}, a=alpha};
    c := color;
    urx, ury := Text_To_Render_Space(renderer, text_x, text_y);
    // main rectangle
    urx += renderer.screen_char_width / 2;
    ury += 3;
    lrx, lry := urx, ury;
    lrx += renderer.screen_char_width * 3 / 2;
    lry += renderer.screen_line_height - 4;
    y_quarter_diff := renderer.screen_line_height / 4;
    ury -= 1;
    lry -= (renderer.screen_line_height - 2) / 2;
    lrx -= renderer.screen_char_width * 3 / 4;
    Render_Quad(.{urx, ury}, .{lrx, lry-1}, c);
    c.r = c.b;
    c.g *= 0.5;
    Render_Quad(.{lrx-4, lry-4}, .{lrx + (lrx-urx)-4, lry+(lry-ury)-1-4}, c);
    c.r = 0.1;
    c.b = 0.72;
    c.g = 0.85;
    Render_Quad(.{lrx-1, lry-1}, .{lrx + (lrx-urx)-1, lry+(lry-ury)-1}, c);
}