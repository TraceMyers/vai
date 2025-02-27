
Initialize_Render_Text :: () {
    // font = get_font_at_size("../fonts/cascadia_code", "Cascadia.ttf", pixel_height);
    fonts_path := tprint("%/../fonts/IBM_Plex_Mono", exe_path);
    font = get_font_at_size(fonts_path, "IBMPlexMono-Medium.ttf", pixel_height);
    font.temporary_glyphs.allocator = temp;
    font.current_quads.allocator = temp;
    assert(font != null);
}

Render_Text_End_Frame :: () {
    array_reset(*font.temporary_glyphs);
    array_reset(*font.current_quads);
}

Screen_Gutter_Width :: () -> s32 {
    screen_char_width := xx prepare_text(font, "m", 0);
    return xx (screen_char_width * gutter_char_width);
}

Normalized_Text_View_Window :: (view_position: Vector2, buffer: *TextBuffer) -> start: float32, end: float32 {
    ul := Upper_Left();
    lr := Lower_Right();
    viewport_height := max(lr.y - ul.y, 0);
    if viewport_height == 0 then return 0, 0;
    screen_line_height := xx (get_baseline_height(font) * 4);
    screen_line_height += xx (cast(float32)screen_line_height * line_spacing_factor);
    line_count := xx max((cast(float)viewport_height / cast(float)screen_line_height + 1.0), 0.0);

    total_space := cast(float32)(buffer.lines.count + line_count);
    window_space := cast(float32)line_count;
    return clamp(view_position.y / total_space, 0.0, 1.0), clamp((view_position.y + window_space) / total_space, 0.0, 1.0);
}

Initialize_Text_Renderer :: (using renderer: *TextRenderer, in_view_layer: *ViewLayer, force_gutter_char_width: s32 = -1) {
    view_layer = in_view_layer;

    ul := Upper_Left();
    lr := Lower_Right();

    viewport_height := max(lr.y - ul.y, 0);
    if viewport_height == 0 then return;
    screen_line_height = xx (get_baseline_height(font) * 4);
    screen_line_height += xx (cast(float32)screen_line_height * line_spacing_factor);
    line_count = xx max((cast(float)viewport_height / cast(float)screen_line_height + 1.0), 0.0);
    if line_count == 0 then return;
    screen_char_width = xx prepare_text(font, "m", 0);
    if force_gutter_char_width >= 0 {
        screen_gutter_width = force_gutter_char_width;
    } else {
        screen_gutter_width = screen_char_width * gutter_char_width;
    }

    gutter_right_pad : s32 = xx (cast(float32)screen_char_width * 0.45);
    align_info_gutter.alignment = .RIGHT;
    align_info_gutter.screen_x = ul.x + screen_gutter_width - gutter_right_pad;
    
    align_info_main.alignment = .LEFT;
    align_info_main.screen_x = ul.x + screen_gutter_width + gutter_right_pad;

    // base render x origin = left side of viewport after gutter
    screen_render_begin.x = align_info_main.screen_x;
    // adjust it leftward dpeending on how much of the line is clipped
    col_render_floor := cast(float32)(cast(s32)view_layer.view_position.x);
    col_render_mod_flt := view_layer.view_position.x - col_render_floor;
    col_render_mod := cast(s32)(col_render_mod_flt * xx screen_char_width);
    screen_render_begin.x -= col_render_mod;

    // base render y origin = one line below the top of the viewport (origin of glyph = bottom left of its rect)
    screen_render_begin.y = ul.y + screen_line_height;
    // adjust it upward depending on how much of the line is clipped
    row_render_floor := cast(float32)(cast(s32)view_layer.view_position.y);
    row_render_mod_flt := view_layer.view_position.y - row_render_floor;
    row_render_mod := cast(s32)(row_render_mod_flt * xx screen_line_height);
    screen_render_begin.y -= row_render_mod;

    // which row/col of text to begin rendering = just floor the view pos
    text_view_clip = IntVector2.{xx view_layer.view_position.x, xx view_layer.view_position.y};
}

Render_Text_Buffer_Lines :: (renderer: *TextRenderer, buffer: *TextBuffer, render_line_numbers: bool) {
    {
        Scoped_Immediate_Text_Render();

        text_scissor_ul := rendering_scissor_lr;
        text_scissor_ul.x = renderer.align_info_main.screen_x;
        Set_Scissor(text_scissor_ul, rendering_scissor_lr);

        utf8_buffer: [..]u8;
        utf8_buffer.allocator = temp;
        color_buffer: [..]TextColorLocation;
        color_buffer.allocator = temp;

        renderer.rendered_line_count = 0;
        for 0..renderer.line_count-1 {
            line_index := renderer.text_view_clip.y + it;
            if line_index >= buffer.lines.count then break;
            if line_index < 0 {
                renderer.rendered_line_count += 1;
                continue;
            }
            marked_utf32 := Line_View(buffer, line_index);
            if marked_utf32.count > renderer.text_view_clip.x {
                marked_utf32.data += renderer.text_view_clip.x;
                marked_utf32.count -= renderer.text_view_clip.x;
                Get_Unmarked_Utf8(marked_utf32, *utf8_buffer, *color_buffer);
                Render_Text_Line(renderer, *renderer.align_info_main, utf8_buffer, color_buffer);
            } else {
                renderer.rendered_line_count += 1;
            }
        }
    }

    // TODO: check line numbers option
    if render_line_numbers {
        line_count := renderer.rendered_line_count;
        Render_Line_Numbers(renderer, line_count);
    }
}

Render_Line_Numbers :: (renderer: *TextRenderer, line_count: s32) {
    Scoped_Immediate_Text_Render();

    gutter_scissor_lr := rendering_scissor_lr;
    gutter_scissor_lr.x = renderer.align_info_main.screen_x;
    Set_Scissor(rendering_scissor_ul, gutter_scissor_lr);

    color_buffer := TextColorLocation.[.{.{110, 110, 110}, 0}];

    cursor := Layer_Cursor(renderer.view_layer);
    cursor_y := ifx cursor then cursor.y else 0;

    renderer.rendered_line_count = 0;
    start_row := renderer.text_view_clip.y + 1;
    for r : 0..line_count-1 {
        line_number_text: string;
        if settings_file_data.relative_line_numbers {
            relative_number := start_row + r - (cursor_y + 1);
            if relative_number == 0 {
                line_number_text = tprint("%", start_row + r);
            } else {
                line_number_text = tprint("%", relative_number);
            }
        } else {
            line_number_text = tprint("%", start_row + r);
        }
        Render_Text_Line(renderer, *renderer.align_info_gutter, As_Array(line_number_text, u8), color_buffer);
    }
}

Render_Scroll_Bar :: (view_layer: *ViewLayer, text_buffer: *TextBuffer) {
    SCROLLBAR_WIDTH : s32 : 10;
    Set_Shader_For_Blended_Color();

    ul := Upper_Left();
    lr := Lower_Right();
    diff := As_Vector2(lr - ul);

    norm_scrollbar_y_begin, norm_scrollbar_y_end := Normalized_Text_View_Window(view_layer.view_position, text_buffer);
    scrollbar_begin := IntVector2.{lr.x - SCROLLBAR_WIDTH, ul.y + xx (diff.y * norm_scrollbar_y_begin)};
    scrollbar_end := IntVector2.{lr.x, ul.y + xx (diff.y * norm_scrollbar_y_end)};
    Render_Quad(scrollbar_begin, scrollbar_end, fRGBA.{0.8, 0.9, 1.0, 0.075});
    Flush_Draws();
}

Render_Gutter_Separator_Line :: (color: fRGBA) {
    gutter_width := Screen_Gutter_Width();
    gutter_line_ul := rendering_scissor_ul;
    gutter_line_ul.x += gutter_width;
    gutter_line_lr := rendering_scissor_lr;
    gutter_line_lr.x = gutter_line_ul.x;
    Render_Line(gutter_line_ul, gutter_line_lr, file_editor_outline_color);
}

Text_To_Render_Space :: inline (using renderer: *TextRenderer, text_x: s32, text_y: s32) -> (render_x: s32, render_y: s32) {
    render_x := align_info_main.screen_x + (text_x - text_view_clip.x) * screen_char_width;
    // this is one line too far, bottom lined up with bottom of letter
    render_y := screen_render_begin.y + (text_y - xx text_view_clip.y) * screen_line_height;
    // center on line
    render_y -= screen_line_height * 3 / 4;
    return render_x, render_y;
}

Render_Text_Cursor :: (renderer: *TextRenderer, cursor: *Cursor, just_want_out_rect := false, depth := DEFAULT_DEPTH) -> (ul: IntVector2, lr: IntVector2) {
    ul_x, ul_y := Text_To_Render_Space(renderer, cursor.x, cursor.y);
    lr_x := ul_x;
    lr_y := ul_y + renderer.screen_line_height;
    if #complete cursor.style == {
    case .BLOCK;
        lr_x += renderer.screen_char_width;
    case .VERTICAL_LINE;
        lr_x += 1;
    }

    if !just_want_out_rect {
        if cursor.reset_blink {
            cursor.blink_timer = kb_cursor_blink_time;
            cursor.reset_blink = false;
        }
        if cursor.blink_timer >= kb_cursor_blink_time {
            if cursor.blink_timer >= kb_cursor_blink_time * 2 {
                cursor.blink_timer -= kb_cursor_blink_time * 2;
            } else {
                Set_Shader_For_Color_Inversion();
                Render_Quad(.{ul_x, ul_y}, .{lr_x, lr_y}, depth=depth);
                Flush_Draws();
            }
        }
        cursor.blink_timer += Smoothed_Delta_Time();
    }

    return IntVector2.{ul_x, ul_y}, IntVector2.{lr_x, lr_y};
}

Render_Cursor_Line_Block :: (renderer: *TextRenderer, cursor: *Cursor, depth := DEFAULT_DEPTH) {
    _, ul_y := Text_To_Render_Space(renderer, cursor.x, cursor.y);
    ul_x := renderer.align_info_main.screen_x;
    lr_x := rendering_scissor_lr.x;
    lr_y := ul_y + renderer.screen_line_height;

    Set_Shader_For_Blended_Color();
    Render_Quad(IntVector2.{ul_x, ul_y}, IntVector2.{lr_x, lr_y}, .{rgb=fRGB_WHITE, a=0.09}, depth=depth);
    Flush_Draws();
}

Render_Text_Selection_Blocks :: (renderer: *TextRenderer, text_buffer: *TextBuffer, cursor: *Cursor, y_filter := -1) {
    if vi_mode != .VISUAL then return;

    Set_Shader_For_Blended_Color();
    start, end := Cursor_Selection(cursor);

    for start.y..end.y {
        if y_filter != -1 && it != y_filter {
            continue;
        }
        highlight_begin_x: s32;
        highlight_end_x: s32;
        if it == start.y {
            highlight_begin_x = start.x;
        } else {
            highlight_begin_x = 0;
        }
        if it == end.y {
            highlight_end_x = end.x;
        } else {
            highlight_end_x = xx Line_Count(text_buffer, it);
        }

        ul_x, ul_y := Text_To_Render_Space(renderer, highlight_begin_x, it);
        lr_x, _ := Text_To_Render_Space(renderer, highlight_end_x, it);
        lr_y := ul_y + renderer.screen_line_height;
        Render_Quad(.{ul_x, ul_y}, .{lr_x, lr_y}, color=.{rgb=fRGB_WHITE, a=0.2});
    }
}

Immediate_Render_Marked_Line :: (renderer: *TextRenderer, line: []u32, color: bRGB, prefix := "", depth := DEFAULT_DEPTH)  {
    Scoped_Immediate_Text_Render(depth);
    color_buffer := TextColorLocation.[.{color, 0}];
    utf8 := Get_Unmarked_Utf8(line);
    prefixed: string;
    if prefix.count > 0 {
        prefixed = tprint("%0%", prefix, As_String(utf8));
    } else {
        prefixed = As_String(utf8);
    }
    Render_Text_Line(renderer, *renderer.align_info_main, As_Array(prefixed, u8), color_buffer);    
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Alignment :: enum {
    LEFT;
    RIGHT;
    CENTER;
}

AlignInfo :: struct {
    screen_x: s32;
    alignment: Alignment;
}

TextColor :: struct {
    start_x: s32;
    color: bRGB;
}

TextRenderer :: struct {
    view_layer: *ViewLayer; // the layer onto which we're rendering
    // screen position query 
    align_info_main: AlignInfo;
    align_info_gutter: AlignInfo;
    screen_char_width: s32;
    screen_gutter_width: s32;
    screen_line_height: s32;
    screen_render_begin: IntVector2;
    // line position query
    line_count: s32;
    rendered_line_count: s32;
    text_view_clip: IntVector2; // which row, col to start rendering, as clipped by the viewport
    selection: TextSelection;
}

Render_Text_Line :: (renderer: *TextRenderer, align_info: *AlignInfo, utf8: []u8, colors: []TextColorLocation) {
    if colors.count == 0 then return;
    total_width: s32 = 0;
    for 0..colors.count-1 {
        // single out a segment of text with the same color
        start_byte := colors[it].location;
        end_byte := ifx it == colors.count - 1 then utf8.count else colors[it + 1].location;
        utf8_segment := string.{end_byte - start_byte, utf8.data + start_byte};

        text_width: s32 = xx Prepare_Text(utf8_segment);
        render_x: s32 = ---;
        if align_info.alignment == {
        case .LEFT;
            render_x = align_info.screen_x + total_width;
        case .RIGHT;
            render_x = align_info.screen_x - (text_width + total_width);
        case .CENTER;
            assert(false); // &unsupported
        }

        render_y := renderer.screen_render_begin.y + renderer.screen_line_height * renderer.rendered_line_count;
        Generate_Quads_For_Prepared_Text(render_x, render_y, color = To_fRGBA(colors[it].color));
        total_width += text_width;
    }
    renderer.rendered_line_count += 1;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

font: *Dynamic_Font;
pixel_height: s32 = 12;
gutter_char_width: s32 = 6;
line_spacing_factor := 0.4;

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

// text rendering requires drawing within a given scissor, so we need to flush any draws that came before, then at the end of the scope, flush any text we've added.
Scoped_Immediate_Text_Render :: (depth := DEFAULT_DEPTH) #expand {
    Flush_Draws();
    `defer Render_Quads_Generated_For_Text(depth);
    `defer Flush_Draws();
    // set the scissor back to whatever it was before
    `defer Set_Scissor(rendering_scissor_ul, rendering_scissor_lr);
}

Prepare_Text :: inline (text: string, effect_flags: Font_Effects = 0) -> width: s64 {
    return prepare_text(font, text, effect_flags);
}

// mostly a copy of the proc in Simmp of the same name
Generate_Quads_For_Prepared_Text :: (x: s64, y: s64, effect_flags: Font_Effects = 0, color := fRGBA_WHITE) {
    assert(font != null);

    array_reserve(*font.current_quads, font.current_quads.count + font.temporary_glyphs.count);

    maybe_offset := false;
    if font.y_offset_for_my_latin_characters maybe_offset = true;

    sx := cast(float) x;
    sy := cast(float) window.height - y; // text is rendered top-down

    // @Speed!
    for info: font.temporary_glyphs {
        if !info.page continue;

        quad := array_add(*font.current_quads);

        quad.glyph = info;
        quad.ul.x = sx + cast(float) info.offset_x;
        quad.ul.y = (sy + cast(float) info.ascent) - cast(float) info.height;
        quad.lr.x = (sx + cast(float) info.offset_x) + cast(float) info.width;
        quad.lr.y = sy + cast(float) info.ascent;
        quad.color = xx,force color;
        
        if maybe_offset && is_latin(info.utf32) {
            // e.g. our Chinese font did not seem to make characters
            // line up properly.
            quad.ul.y += font.y_offset_for_my_latin_characters;
            quad.lr.y += font.y_offset_for_my_latin_characters;
        }

        width  := info.page.bitmap_data.width;  // *Not* map.width, as map may be dirty.
        height := info.page.bitmap_data.height; // Ibid.

        quad.uv0.x = info.x0 / cast(float) width;
        quad.uv1.x = (cast(float) info.x0 + info.width) / width;

        quad.uv0.y = info.y0 / cast(float) height;
        quad.uv1.y = (cast(float) info.y0 + info.height) / height;

		sx += cast(float) info.advance;
    }
}