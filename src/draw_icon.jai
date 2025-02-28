
Draw_Folder :: (renderer: *TextRenderer, text_x: s32, text_y: s32, color: *fRGBA) {
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