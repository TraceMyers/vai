// Tree-sitter driven syntax highlighting.
//
// Design (see plan): tree-sitter is used ONLY for highlighting.  We never mutate
// the editable buffer to carry colors (Commit_Utf32_To_Line re-encodes code
// points to UTF-8 without stripping markup, so color bits packed into a line
// would corrupt the saved file).  Instead, after parsing we build a per-document
// byte->color map and, at render time, derive per-glyph colors from it without
// touching buffer memory.
//
// M1 scope: whole-buffer reparse when dirty (no incremental ts_tree_edit yet),
// Jai grammar only, non-soft-wrapped lines.  M2 adds incremental edits and moves
// the grammar behind a per-language provider DLL.

// Color palette indices into text_colors (see Syntax_Highlight_Lazy_Init).
SyntaxColor :: enum u8 {
    DEFAULT     :: 0;
    COMMENT     :: 2;
    STRING      :: 3;
    NUMBER      :: 4;
    KEYWORD     :: 5;
    DIRECTIVE   :: 6;
    OPERATOR    :: 7;
    CONSTANT    :: 8;
}

BufferHighlight :: struct {
    enabled: bool;
    dirty:   bool;
    tree:    *TSTree;
    byte_color:       [..]u8;   // one color index per document byte
    line_byte_offset: [..]s32;  // start byte of each line in the reconstructed doc
}

Shutdown_Buffer_Highlight :: (using hl: *BufferHighlight) {
    if tree { ts_tree_delete(tree); tree = null; }
    array_reset(*byte_color);
    array_reset(*line_byte_offset);
    enabled = false;
    dirty = false;
}

// Enable highlighting for buffers we have a grammar for.  Extension-based for
// now; M2 routes this through the language-provider registry.
Maybe_Enable_Highlight :: (buffer: *TextBuffer) {
    if buffer.flags & (.FILE_EXPLORER | .PROJECT_EXPLORER | .OS_CONSOLE) then return;
    if !ends_with(buffer.file_path, ".jai") then return;
    buffer.highlight.enabled = true;
    buffer.highlight.dirty   = true;
}

// -----------------------------------------------------------------------------
// global tree-sitter state (main thread only)

highlight_initialized: bool;
highlight_parser:      *TSParser;
highlight_query:       *TSQuery;
highlight_capture_colors: [..]u8; // capture id -> color index

HIGHLIGHT_QUERY :: #string DONE
(line_comment)  @comment
(block_comment) @comment
(string)  @string
(number)  @number
(boolean) @constant
(keyword) @keyword
(directive) @directive
(operator) @operator
DONE

Syntax_Highlight_Lazy_Init :: () -> bool {
    if highlight_initialized then return highlight_parser != null && highlight_query != null;
    highlight_initialized = true;

    // Palette.  Index 0 stays the default text color set in main.jai.
    text_colors[cast(u8) SyntaxColor.COMMENT]   = .{106, 153,  85};
    text_colors[cast(u8) SyntaxColor.STRING]    = .{206, 145, 120};
    text_colors[cast(u8) SyntaxColor.NUMBER]    = .{181, 206, 168};
    text_colors[cast(u8) SyntaxColor.KEYWORD]   = .{ 86, 156, 214};
    text_colors[cast(u8) SyntaxColor.DIRECTIVE] = .{197, 134, 192};
    text_colors[cast(u8) SyntaxColor.OPERATOR]  = .{212, 212, 212};
    text_colors[cast(u8) SyntaxColor.CONSTANT]  = .{ 79, 193, 255};

    lang := tree_sitter_jai();
    highlight_parser = ts_parser_new();
    if !ts_parser_set_language(highlight_parser, lang) {
        Log_Warning("tree-sitter: failed to set jai language");
        return false;
    }

    err_offset: u32;
    err_type:   TSQueryError;
    highlight_query = ts_query_new(lang, HIGHLIGHT_QUERY.data, xx HIGHLIGHT_QUERY.count, *err_offset, *err_type);
    if highlight_query == null {
        Log_Warning("tree-sitter: highlight query error % at offset %", err_type, err_offset);
        return false;
    }

    // Map each capture id to a palette color by its name.
    Add_Capture :: (id: u32, color: SyntaxColor) #expand {
        while highlight_capture_colors.count <= id  array_add(*highlight_capture_colors, xx SyntaxColor.DEFAULT);
        highlight_capture_colors[id] = xx color;
    }
    capture_count := ts_query_capture_count(highlight_query);
    for id: 0..capture_count-1 {
        name_len: u32;
        name_ptr := ts_query_capture_name_for_id(highlight_query, id, *name_len);
        if name_ptr == null then continue;
        name: string;
        name.data  = name_ptr;
        name.count = xx name_len;
        color := SyntaxColor.DEFAULT;
        if name == {
            case "comment";   color = .COMMENT;
            case "string";    color = .STRING;
            case "number";    color = .NUMBER;
            case "keyword";   color = .KEYWORD;
            case "directive"; color = .DIRECTIVE;
            case "operator";  color = .OPERATOR;
            case "constant";  color = .CONSTANT;
        }
        Add_Capture(id, color);
    }
    return true;
}

// -----------------------------------------------------------------------------
// reparse

Highlight_Reparse_If_Dirty :: (buffer: *TextBuffer) {
    if !buffer.highlight.enabled || !buffer.highlight.dirty then return;
    if !Syntax_Highlight_Lazy_Init() { buffer.highlight.enabled = false; return; }
    buffer.highlight.dirty = false;

    using hl := *buffer.highlight;

    // Reconstruct the document as contiguous UTF-8 (lines joined with '\n'),
    // recording each line's start byte.  tree-sitter works in byte offsets, so
    // this is also the coordinate space of byte_color.
    array_reset_keeping_memory(*line_byte_offset);
    total := 0;
    for 0..buffer.lines.count-1 {
        array_add(*line_byte_offset, xx total);
        total += Get_Line_Bytes(buffer, it).count + 1; // +1 for '\n'
    }
    if total > 0 then total -= 1; // no trailing newline

    doc := Temp_Buffer(u8, total);
    dest := 0;
    for 0..buffer.lines.count-1 {
        b := Get_Line_Bytes(buffer, it);
        if b.count > 0 {
            memcpy(doc.data + dest, b.data, b.count);
            dest += b.count;
        }
        if it != buffer.lines.count-1 {
            doc.data[dest] = #char "\n";
            dest += 1;
        }
    }
    doc.count = dest;

    if tree { ts_tree_delete(tree); tree = null; }
    tree = ts_parser_parse_string(highlight_parser, null, doc.data, xx doc.count);

    array_resize(*byte_color, doc.count);
    memset(byte_color.data, xx SyntaxColor.DEFAULT, byte_color.count);
    if tree == null then return;

    cursor := ts_query_cursor_new();
    ts_query_cursor_exec(cursor, highlight_query, ts_tree_root_node(tree));
    match: TSQueryMatch;
    while ts_query_cursor_next_match(cursor, *match) {
        for 0..match.capture_count-1 {
            cap := match.captures[it];
            color: u8 = xx SyntaxColor.DEFAULT;
            if cap.index < xx highlight_capture_colors.count then color = highlight_capture_colors[cap.index];
            sb := ts_node_start_byte(cap.node);
            eb := ts_node_end_byte(cap.node);
            if eb > xx byte_color.count then eb = xx byte_color.count;
            for b: sb..eb-1  byte_color[b] = color;
        }
    }
    ts_query_cursor_delete(cursor);
}

// -----------------------------------------------------------------------------
// render support

// Produce a per-expanded-code-point color index array parallel to marked_utf32.
// Walks the expanded line while tracking the raw document byte position, so tab
// expansion (EXPANDED_TAB + TAB_EXPANDED_SPACE padding) maps back correctly.
Compute_Expanded_Line_Colors :: (buffer: *TextBuffer, row: s64, marked_utf32: []u32) -> []u8 {
    colors := Temp_Buffer(u8, marked_utf32.count);
    colors.count = marked_utf32.count;
    using hl := *buffer.highlight;
    if row >= line_byte_offset.count {
        memset(colors.data, xx SyntaxColor.DEFAULT, colors.count);
        return colors;
    }
    raw_byte := line_byte_offset[row];
    last_color: u8 = xx SyntaxColor.DEFAULT;
    for marked_utf32 {
        if Is_Tab_Expanded_Space(it) {
            colors[it_index] = last_color; // padding cell of a tab; do not advance
            continue;
        }
        c: u8 = xx SyntaxColor.DEFAULT;
        if raw_byte >= 0 && raw_byte < byte_color.count then c = byte_color[raw_byte];
        colors[it_index] = c;
        last_color = c;
        if Is_Expanded_Tab(it) {
            raw_byte += 1; // the '\t' is a single raw byte
        } else {
            utf32 := Marked_Code_Point_Utf32(it);
            utf8  := Utf32_To_Utf8(xx *utf32);
            raw_byte += xx utf8.count;
        }
    }
    return colors;
}

// Shift every color run right by `offset` bytes and prepend a default-colored run
// at 0.  Used when the wrapped-line renderer prepends an indent to the byte
// stream: the runs were computed relative to the un-indented content.
Offset_Color_Locations :: (color_buffer: *[..]TextColorLocation, offset: s32) {
    if offset <= 0 then return;
    for * color_buffer.*  it.location += offset;
    array_insert_at(color_buffer, TextColorLocation.{text_colors[0], 0}, 0);
}

// Colored analogue of Get_Unmarked_Utf8: emits the line's plain UTF-8 plus color
// runs, taking colors from hl_colors (parallel to in_utf32) instead of packed bits.
Get_Unmarked_Utf8_Colored :: (in_utf32: []u32, hl_colors: []u8, out_utf8: *[..]u8, out_colors: *[..]TextColorLocation) {
    array_reset_keeping_memory(out_utf8);
    array_reset_keeping_memory(out_colors);
    prev_color_index: s16 = -1;
    for in_utf32 {
        color_index := ifx it_index < hl_colors.count then hl_colors[it_index] else cast(u8) SyntaxColor.DEFAULT;
        if cast(s16) color_index != prev_color_index {
            array_add(out_colors, .{text_colors[color_index], xx out_utf8.count});
            prev_color_index = color_index;
        }
        utf32 := Marked_Code_Point_Utf32(it);
        utf8  := Utf32_To_Utf8(xx *utf32);
        for 0..utf8.count-1 {
            array_add(out_utf8, utf8.bytes[it]);
        }
    }
}
