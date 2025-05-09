
Render_Text :: struct {

    Initialize :: () -> success: bool {
        fonts_path := tprint("%/../fonts/cascadia_code", exe_path);
        font_pixel_height := Integer_Option_Value(.FONT_SIZE);
        font = get_font_at_size(fonts_path, "Cascadia.ttf", font_pixel_height);
        // fonts_path := tprint("%/../fonts/IBM_Plex_Mono", exe_path);
        // font = get_font_at_size(fonts_path, "IBMPlexMono-Medium.ttf", pixel_height);
        font.temporary_glyphs.allocator = temp;
        font.current_quads.allocator = temp;
        return font != null;
    }    

    Shutdown :: () {
        if font != null {
            free(font);
            font = null;
        }
    }

}

Width :: (font: *Dynamic_Font) -> s32 {
    return xx prepare_text(font, "m", 0);
}

Reinitialize_Font :: () {
    Render_Text.Shutdown();
    Render_Text.Initialize();
}

Render_Text_End_Frame :: () {
    array_reset(*font.temporary_glyphs);
    array_reset(*font.current_quads);
}

Screen_Gutter_Width :: () -> s32 {
    screen_char_width := Width(font);
    return xx ((screen_char_width + 2) * gutter_char_width + 2);
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

Initialize_Text_Renderer :: (using renderer: *TextRenderer, in_view_layer: *ViewLayer, force_gutter_char_width: s32 = -1, force_ul := IntVector2.{-1,-1}, force_lr := IntVector2.{-1,-1}) {
    view_layer = in_view_layer;

    ul := ifx force_ul.x >= 0 && force_ul.y >= 0 then force_ul else Upper_Left();
    lr := ifx force_lr.x >= 0 && force_lr.y >= 0 then force_lr else Lower_Right();

    viewport_height := max(lr.y - ul.y, 0);
    if viewport_height == 0 then return;
    screen_line_height = xx (get_baseline_height(font) * 4);
    screen_line_height += xx (cast(float32)screen_line_height * line_spacing_factor);
    line_count = xx max((cast(float)viewport_height / cast(float)screen_line_height + 1.0), 0.0);
    if line_count == 0 then return;
    screen_char_width = Width(font);
    if force_gutter_char_width >= 0 {
        screen_gutter_width = force_gutter_char_width;
    } else {
        screen_gutter_width = Screen_Gutter_Width();
    }

    gutter_right_pad : s32 = xx (cast(float32)screen_char_width * 0.45);
    align_info_gutter.alignment = .RIGHT;
    align_info_gutter.screen_x = ul.x + screen_gutter_width - (gutter_right_pad + (screen_char_width >> 1));
    
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
    initialized = true;

    if in_view_layer.type == .FILE_EDITOR && Bool_Option_Value(.SOFT_WRAP) && in_view_layer.file_editor.file_buffer >= 0 {
        render_line: RenderLineData;
        Initialize_Render_Line_Data(*render_line, renderer);
        first_rendered_line_text := Line_View(Layer_Text_Buffer(in_view_layer), render_line.start_line);
        first_rendered_line_row_ct := cast(float)Render_Wrapped_Line(renderer, null, null, first_rendered_line_text, *render_line, true);
        if first_rendered_line_row_ct > 1 {
            row_render_mod_flt = (view_layer.view_position.y - row_render_floor) * cast(float)first_rendered_line_row_ct;
            row_render_mod = cast(s32)(row_render_mod_flt * xx screen_line_height);
            screen_render_begin.y = ul.y + screen_line_height - row_render_mod;
        }
    }
}

Render_Wrapped_Line :: (renderer: *TextRenderer, color_buffer: *[..]TextColorLocation, utf8_buffer: *[..]u8, marked_utf32: []u32, render_line: *RenderLineData, just_count_lines := false, out_row_lengths: *[..]s32 = null) -> s32 {
    remaining_utf32 := marked_utf32;

    assert(render_line.total_reindent_on_wrap <= LOTTA_SPACES.count);
    indent_header := string.{render_line.total_reindent_on_wrap, LOTTA_SPACES.data};

    if out_row_lengths {
        array_reset_keeping_memory(out_row_lengths);
    }

    wrapped_text_selection_begins_at := S64_MAX;
    wrapped_text_selection_ends_at := S64_MAX;
    if !render_line.set_wrapped_text_selection_begin {
        if render_line.wrapped_text_selection_begin.y == render_line.line_index {
            wrapped_text_selection_begins_at = render_line.wrapped_text_selection_begin.x;
        }
    }
    if !render_line.set_wrapped_text_selection_end {
        if render_line.wrapped_text_selection_end.y == render_line.line_index {
            wrapped_text_selection_ends_at = render_line.wrapped_text_selection_end.x;
        }
    }

    wrapped_line_ct : s32 = 0;
    while remaining_utf32.count > 0 {
        partial_render_buf := remaining_utf32;
        render_remain_ct := remaining_utf32.count;
        use_indent_str: string;

        if wrapped_line_ct > 0 {
            render_remain_ct += indent_header.count;
            use_indent_str = indent_header;
        }

        max_render_with_indent_ct := render_line.wrap_max_render_character_count - use_indent_str.count;
        if partial_render_buf.count >= max_render_with_indent_ct-1 {
            partial_render_buf.count = max(max_render_with_indent_ct-1, sdw(1));
            // wrap on word. search back for space
            if partial_render_buf.count > 2 then for #v2 < 1..partial_render_buf.count-1 {
                if Is_Whitespace(partial_render_buf[it]) {
                    // make sure we're not digging into the indent
                    maybe_split_on_space_index := it;
                    for #v2 < 0..maybe_split_on_space_index-1 {
                        if !Is_Whitespace(partial_render_buf[it]) {
                            partial_render_buf.count = it + 2;
                            break;
                        }
                    }
                    break;
                }
            }
        }

        if out_row_lengths {
            array_add(out_row_lengths, sdw(partial_render_buf.count));
        }

        if !just_count_lines {
            if render_line.save_cursor_pos {
                at_end := remaining_utf32.count == partial_render_buf.count;
                if render_line.save_cursor_pos_x < partial_render_buf.count || at_end {
                    renderer.cursor_pos.y = render_line.start_line + renderer.rendered_line_count;
                    if wrapped_line_ct > 0 {
                        renderer.cursor_pos.x = sdw(render_line.save_cursor_pos_x + indent_header.count);
                    } else {
                        renderer.cursor_pos.x = sdw(render_line.save_cursor_pos_x);
                    }
                    render_line.save_cursor_pos = false;
                } else {
                    render_line.save_cursor_pos_x -= sdw(partial_render_buf.count);
                }
            }

            selection_begins_in_text, selection_ends_in_text: bool;
            selection_begins_at_end, selection_ends_at_end: bool;

            selection_begins_in_text = wrapped_text_selection_begins_at < partial_render_buf.count;
            selection_ends_in_text = wrapped_text_selection_ends_at < partial_render_buf.count;
            if remaining_utf32.count == partial_render_buf.count {
                selection_begins_at_end = wrapped_text_selection_begins_at == partial_render_buf.count;
                selection_ends_at_end = wrapped_text_selection_ends_at == partial_render_buf.count;
            }

            if selection_begins_in_text || selection_begins_at_end {
                if use_indent_str.count > 0 {
                    render_line.wrapped_text_selection_begin.x = xx (wrapped_text_selection_begins_at + use_indent_str.count);
                } else {
                    render_line.wrapped_text_selection_begin.x = xx wrapped_text_selection_begins_at;
                }
                render_line.wrapped_text_selection_begin.y = xx (render_line.start_line + renderer.rendered_line_count);
                render_line.set_wrapped_text_selection_begin = true;
            }
            if selection_ends_in_text || selection_ends_at_end {
                if use_indent_str.count > 0 {
                    render_line.wrapped_text_selection_end.x = xx (wrapped_text_selection_ends_at + use_indent_str.count);
                } else {
                    render_line.wrapped_text_selection_end.x = xx wrapped_text_selection_ends_at;
                }
                render_line.wrapped_text_selection_end.y = xx (render_line.start_line + renderer.rendered_line_count);
                render_line.set_wrapped_text_selection_end = true;
            }

            rendered_line := RenderedTextData.{render_line.line_index, 0, xx use_indent_str.count, wrapped_line_ct > 0};

            Get_Unmarked_Utf8(partial_render_buf, utf8_buffer, color_buffer);
            if use_indent_str.count > 0 {
                indented := tprint("%0%", indent_header, As_String(utf8_buffer.*));
                Render_Text_Line(renderer, *renderer.align_info_main, As_Array(indented, u8), color_buffer.*, render_line.y_offset);
                if renderer.view_layer.type == .FILE_EDITOR {
                    if selection_ends_in_text || selection_ends_at_end {
                        rendered_line.glyph_count = xx wrapped_text_selection_ends_at;
                        array_add(*renderer.view_layer.file_editor.rendered_text_data, rendered_line);
                    } else {
                        rendered_line.glyph_count = xx (partial_render_buf.count + indent_header.count);
                        array_add(*renderer.view_layer.file_editor.rendered_text_data, rendered_line);
                    }
                }
            } else {
                Render_Text_Line(renderer, *renderer.align_info_main, utf8_buffer.*, color_buffer.*, render_line.y_offset);
                if renderer.view_layer.type == .FILE_EDITOR {
                    if selection_ends_in_text || selection_ends_at_end {
                        rendered_line.glyph_count = xx wrapped_text_selection_ends_at;
                        array_add(*renderer.view_layer.file_editor.rendered_text_data, rendered_line);
                    } else {
                        rendered_line.glyph_count = xx partial_render_buf.count;
                        array_add(*renderer.view_layer.file_editor.rendered_text_data, rendered_line);
                    }
                }
            }
        }

        remaining_utf32.count -= partial_render_buf.count;
        remaining_utf32.data += partial_render_buf.count;
        if render_line.set_wrapped_text_selection_begin {
            wrapped_text_selection_begins_at = S64_MAX;
        } else {
            wrapped_text_selection_begins_at -= partial_render_buf.count;
        }
        if render_line.set_wrapped_text_selection_end {
            wrapped_text_selection_ends_at = S64_MAX;
        } else {
            wrapped_text_selection_ends_at -= partial_render_buf.count;
        }
        wrapped_line_ct += 1;
    }
    return wrapped_line_ct;
}

Initialize_Render_Line_Data :: (using render_line: *RenderLineData, renderer: *TextRenderer) {
    layer_cursor = Layer_Cursor(renderer.view_layer);
    start_line = renderer.text_view_clip.y;
    indent_width = Integer_Option_Value(.INDENT_WIDTH);
    wrap_indent = Integer_Option_Value(.SOFT_WRAP_INDENT_WIDTH);
    view_width = max(rendering_scissor_lr.x - renderer.align_info_main.screen_x, sdw(1));
    wrap_max_render_character_count = view_width / renderer.screen_char_width;
    if renderer.view_layer {
        do_line_wrap = Do_Line_Wrap(renderer.view_layer);
        wrapped_text_selection_begin = renderer.view_layer.file_editor.text_selection_begin;
        wrapped_text_selection_end = renderer.view_layer.file_editor.text_selection_end;
    } 
    initialized = true;
}

Do_Line_Wrap :: (layer: *ViewLayer) -> bool {
    return layer.type == .FILE_EDITOR && Bool_Option_Value(.SOFT_WRAP);
}

// TODO: soft wrap made a mess out of this
Render_Text_Buffer_Lines :: (view_layer: *ViewLayer, renderer: *TextRenderer, buffer: *TextBuffer, render_line_numbers: bool) {
    rendered_lines_at: [..]s32;
    rendered_lines_at.allocator = temp;

    {
        Scoped_Immediate_Text_Render();

        layer_cursor := Layer_Cursor(view_layer);

        text_scissor_ul := rendering_scissor_lr;
        text_scissor_ul.x = renderer.align_info_main.screen_x;
        Set_Scissor(text_scissor_ul, rendering_scissor_lr);

        utf8_buffer: [..]u8;
        utf8_buffer.allocator = temp;
        color_buffer: [..]TextColorLocation;
        color_buffer.allocator = temp;

        if view_layer && view_layer.type == .FILE_EDITOR {
            using view_layer.file_editor;
            text_selection_begin, text_selection_end = Cursor_Selection(layer_cursor);
            array_reset(*rendered_text_data);
            rendered_text_data.allocator = temp;
        }
        
        render_line: RenderLineData;
        Initialize_Render_Line_Data(*render_line, renderer);

        if render_line.layer_cursor {
            renderer.cursor_pos = .{render_line.layer_cursor.x, render_line.layer_cursor.y};
        }

        renderer.rendered_line_count = 0;
        for 0..renderer.line_count-1 {
            render_line.line_index = render_line.start_line + it;
            if render_line.line_index >= buffer.lines.count then break;
            if render_line.line_index < 0 {
                renderer.rendered_line_count += 1;
                continue;
            }

            marked_utf32 := Line_View(buffer, render_line.line_index);
            {
                using render_line;
                no_hz_clip = view_layer && view_layer.type == .FILE_EXPLORER;
                save_cursor_pos = layer_cursor && line_index == layer_cursor.y;
                save_cursor_pos_x = ifx layer_cursor then layer_cursor.x else 0;
                total_reindent_on_wrap = xx Get_Marked_Line_Indent(marked_utf32) * indent_width + wrap_indent;
                y_offset = Layer_Render_Line_Y_Offset(view_layer, line_index);
            }
            
            array_add(*rendered_lines_at, renderer.rendered_line_count);

            glyphs_in_view_horizontally := marked_utf32.count > renderer.text_view_clip.x;
            if glyphs_in_view_horizontally {
                marked_utf32.data += renderer.text_view_clip.x;
                marked_utf32.count -= renderer.text_view_clip.x;
            }

            if (render_line.no_hz_clip || glyphs_in_view_horizontally) && marked_utf32.count != 0 {
                if render_line.do_line_wrap {
                    Render_Wrapped_Line(renderer, *color_buffer, *utf8_buffer, marked_utf32, *render_line);
                } else {
                    Get_Unmarked_Utf8(marked_utf32, *utf8_buffer, *color_buffer);
                    Render_Text_Line(renderer, *renderer.align_info_main, utf8_buffer, color_buffer, render_line.y_offset);
                    if view_layer && view_layer.type == .FILE_EDITOR {
                        using view_layer.file_editor;
                        rendered_line := RenderedTextData.{render_line.line_index, xx marked_utf32.count, 0, false};
                        array_add(*rendered_text_data, rendered_line);
                    }
                }
            } else {
                if render_line.save_cursor_pos {
                    renderer.cursor_pos.x = 0;
                    renderer.cursor_pos.y = render_line.start_line + renderer.rendered_line_count;
                }
                if view_layer && view_layer.type == .FILE_EDITOR {
                    using view_layer.file_editor;
                    rendered_line := RenderedTextData.{render_line.line_index, 1, 0, false};
                    array_add(*rendered_text_data, rendered_line);
                    if render_line.do_line_wrap {
                        if view_layer.file_editor.text_selection_begin.y == render_line.line_index {
                            render_line.wrapped_text_selection_begin.x = 0;
                            render_line.wrapped_text_selection_begin.y = (render_line.start_line + renderer.rendered_line_count);
                            render_line.set_wrapped_text_selection_begin = true;
                        }
                        if view_layer.file_editor.text_selection_end.y == render_line.line_index {
                            render_line.wrapped_text_selection_end.x = 0;
                            render_line.wrapped_text_selection_end.y = (render_line.start_line + renderer.rendered_line_count);
                            render_line.set_wrapped_text_selection_end = true;
                        }
                    }
                }
                renderer.rendered_line_count += 1;
            }
        }

        if view_layer && view_layer.type == .FILE_EDITOR {
            using view_layer.file_editor;
            text_selection_begin = render_line.wrapped_text_selection_begin;
            text_selection_end = render_line.wrapped_text_selection_end;
        }
    }

    // TODO: check line numbers option
    if render_line_numbers {
        line_count := renderer.rendered_line_count;
        Render_Line_Numbers(renderer, line_count, rendered_lines_at);
    }
}

Render_Line_Numbers :: (renderer: *TextRenderer, line_count: s32, rendered_lines_at: []s32) {
    Scoped_Immediate_Text_Render();

    gutter_scissor_lr := rendering_scissor_lr;
    gutter_scissor_lr.x = renderer.align_info_main.screen_x;
    Set_Scissor(rendering_scissor_ul, gutter_scissor_lr);

    inactive_line_color := TextColorLocation.[.{.{110, 110, 110}, 0}];
    active_line_color := TextColorLocation.[.{.{180, 180, 180}, 0}];

    cursor := Layer_Cursor(renderer.view_layer);
    cursor_y := ifx cursor then cursor.y else 0;

    renderer.rendered_line_count = 0;
    start_row := renderer.text_view_clip.y + 1;
    rendered_number_ct := 0;

    for r : 0..line_count-1 {
        if rendered_number_ct >= rendered_lines_at.count {
            break;
        }
        if rendered_lines_at[rendered_number_ct] > r {
            renderer.rendered_line_count += 1;
            continue;
        }

        line_number_text: string;
        line_number := start_row + rendered_number_ct;
        relative_line_number := line_number - (cursor_y + 1);
        is_highlighted_line := relative_line_number == 0;

        line_color := ifx is_highlighted_line then *active_line_color else *inactive_line_color;

        if Bool_Option_Value(.RELATIVE_LINE_NUMBERS) {
            if is_highlighted_line {
                line_number_text = tprint("% ", line_number);
            } else {
                line_number_text = tprint("%", abs(relative_line_number));
            }
        } else {
            line_number_text = tprint("%", line_number);
        }
        Render_Text_Line(renderer, *renderer.align_info_gutter, As_Array(line_number_text, u8), line_color.*);
        rendered_number_ct += 1;
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

Text_To_Render_Space :: inline (using renderer: *TextRenderer, text_x: s32, text_y: s32, clip_x := true, clip_y := true) -> (render_x: s32, render_y: s32) {
    render_x, render_y : s32 = ---;
    if clip_x {
        render_x = align_info_main.screen_x + (text_x - text_view_clip.x) * screen_char_width;
    } else {
        render_x = align_info_main.screen_x + text_x * screen_char_width;
    }
    if clip_y {
        // this is one line too far, bottom lined up with bottom of letter
        render_y = screen_render_begin.y + (text_y - xx text_view_clip.y) * screen_line_height;
    } else {
        render_y = screen_render_begin.y + text_y * screen_line_height;
    }
    // center on line
    render_y -= screen_line_height * 3 / 4;
    render_y += Layer_Render_Line_Y_Offset(renderer.view_layer, text_y);
    return render_x, render_y;
}

Render_Text_Cursor :: (renderer: *TextRenderer, cursor: *Cursor, just_want_out_rect := false, depth := DEFAULT_DEPTH) -> (ul: IntVector2, lr: IntVector2) {
    ul_x, ul_y := Text_To_Render_Space(renderer, renderer.cursor_pos.x, renderer.cursor_pos.y);
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

Render_Cursor_Line_Block :: (renderer: *TextRenderer, cursor: *Cursor, alpha := 0.08, depth := DEFAULT_DEPTH) {
    _, ul_y := Text_To_Render_Space(renderer, renderer.cursor_pos.x, renderer.cursor_pos.y);
    ul_x := renderer.align_info_main.screen_x;
    lr_x := rendering_scissor_lr.x;
    lr_y := ul_y + renderer.screen_line_height;

    Set_Shader_For_Blended_Color();
    Render_Quad(IntVector2.{ul_x, ul_y}, IntVector2.{lr_x, lr_y}, .{rgb=fRGB_WHITE, a=alpha}, depth=depth);
    Flush_Draws();
}

Render_Text_Selection_Blocks :: (renderer: *TextRenderer, text_buffer: *TextBuffer, cursor: *Cursor) {
    Set_Shader_For_Blended_Color();
    start, end: IntVector2;
    if renderer.view_layer.type == .FILE_EDITOR {
        using renderer.view_layer;
        start, end = file_editor.text_selection_begin, file_editor.text_selection_end;
    } else {
        start, end = Cursor_Selection(cursor);
    }

    offset := renderer.screen_line_height / 4;

    Add_Debug_Text(sprint("start: %, end: %", start, end));
    start_ul_x, start_ul_y := Text_To_Render_Space(renderer, start.x, start.y);
    _, start_ul_y_plus1 := Text_To_Render_Space(renderer, start.x, start.y+1);
    end_ul_x, end_ul_y := Text_To_Render_Space(renderer, end.x, end.y);
    Add_Debug_Text(sprint("font height: %", Integer_Option_Value(.FONT_SIZE)));
    Add_Debug_Text(sprint("vp:    rx: %, ry: %", Upper_Left().x, Upper_Left().y));
    Add_Debug_Text(sprint("start: rx: %, ry: %, ry/f: %", start_ul_x, start_ul_y, start_ul_y / (Integer_Option_Value(.FONT_SIZE) + offset)));
    Add_Debug_Text(sprint("+1:    rx: %, ry: %, ry/f: %", start_ul_x, start_ul_y_plus1, start_ul_y_plus1 / (Integer_Option_Value(.FONT_SIZE) + offset)));
    Add_Debug_Text(sprint("end:   rx: %, ry: %, ry/f: %", end_ul_x, end_ul_y, end_ul_y / (Integer_Option_Value(.FONT_SIZE) + offset)));
    Add_Debug_Text(sprint("ys: %, datas: %", (end.y-start.y+1), renderer.view_layer.file_editor.rendered_text_data.count));
    Add_Debug_Text(sprint("---"));

    i := 0;
    for start.y..end.y {
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
            if renderer.view_layer.type == .FILE_EDITOR {
                using renderer.view_layer;
                idx := start.y + i;
                highlight_end_x = file_editor.rendered_text_data[idx].glyph_count;
                if file_editor.rendered_text_data[idx].wrapped {
                    highlight_begin_x += file_editor.rendered_text_data[idx].wrap_indent_length;
                }
            } else {
                highlight_end_x = xx Line_Count(text_buffer, it);
            }
        }

        ul_x, ul_y := Text_To_Render_Space(renderer, highlight_begin_x, it);
        lr_x, _ := Text_To_Render_Space(renderer, highlight_end_x, it);
        lr_y := ul_y + renderer.screen_line_height;
        // Add_Debug_Text(sprint("%: x: %, uly: %, lry: %, render: %", , ul_x, ul_y, lr_y, lr_y > 0));
        if lr_y <= 5 then continue;
        Render_Quad(.{ul_x, ul_y}, .{lr_x, lr_y}, color=.{rgb=fRGB_WHITE, a=0.2});
        i += 1;
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
    // set inside Render_Text_Buffer_Lines()
    cursor_pos: IntVector2;
    initialized: bool;
}

RenderLineData :: struct {
    // all lines
    layer_cursor: *Cursor;
    start_line: s32;
    indent_width: s32;
    wrap_indent: s32;
    view_width: s32;
    wrap_max_render_character_count: s32;
    do_line_wrap: bool;
    // per line
    no_hz_clip: bool;
    save_cursor_pos: bool;
    line_index: s32;
    save_cursor_pos_x: s32;
    total_reindent_on_wrap: s32;
    y_offset: s32;
    wrapped_text_selection_begin: IntVector2;
    wrapped_text_selection_end: IntVector2;
    set_wrapped_text_selection_begin: bool;
    set_wrapped_text_selection_end: bool;
    initialized: bool;
}


Render_Text_Line :: (renderer: *TextRenderer, align_info: *AlignInfo, utf8: []u8, colors: []TextColorLocation, y_offset: s32 = 0) {
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

        render_y := renderer.screen_render_begin.y + renderer.screen_line_height * renderer.rendered_line_count + y_offset;
        Generate_Quads_For_Prepared_Text(render_x, render_y, color = To_fRGBA(colors[it].color));
        total_width += text_width;
    }
    renderer.rendered_line_count += 1;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

font: *Dynamic_Font;
gutter_char_width: s32 = 6;
line_spacing_factor := 0.6;

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

LOTTA_SPACES :: "                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ";
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
