// Hand-written Jai bindings for the vendored tree-sitter runtime
// (third_party/tree-sitter, revision b40f342067a89cd6331bf4c27407588320f3c263).
//
// The runtime is language-agnostic and statically linked into the editor; it is
// used ONLY for syntax highlighting.  Go-to-definition / references / rename come
// from the Jai-compiler-backed semantic provider, not from these trees.
//
// The static libraries are produced by native_language/CMakeLists.txt and copied
// into <project>/libs by build.jai.  #library relative paths resolve against this
// source file's directory, hence "../libs/...".

tree_sitter :: #library,no_dll "../libs/tree-sitter";

// M1 links the Jai grammar directly into the editor.  In M2 this moves behind a
// provider DLL's get_grammar() export; tree_sitter_jai() then comes from the DLL.
jai_grammar :: #library,no_dll "../libs/jai-grammar";
tree_sitter_jai :: () -> *TSLanguage #foreign jai_grammar;

// ---- opaque handles ---------------------------------------------------------

TSParser      :: struct {}
TSTree        :: struct {}
TSLanguage    :: struct {}
TSQuery       :: struct {}
TSQueryCursor :: struct {}

// ---- value types (layout must match tree_sitter/api.h exactly) --------------

TSPoint :: struct {
    row:    u32;
    column: u32;
}

TSInputEdit :: struct {
    start_byte:    u32;
    old_end_byte:  u32;
    new_end_byte:  u32;
    start_point:   TSPoint;
    old_end_point: TSPoint;
    new_end_point: TSPoint;
}

// `context` is reserved in Jai; the field name is irrelevant to the C ABI.
TSNode :: struct {
    context_: [4]u32;
    id:       *void;
    tree:     *TSTree;
}

TSQueryCapture :: struct {
    node:  TSNode;
    index: u32;
}

TSQueryMatch :: struct {
    id:            u32;
    pattern_index: u16;
    capture_count: u16;
    captures:      *TSQueryCapture;
}

TSInputEncoding :: enum u32 {
    UTF8  :: 0;
    UTF16 :: 1;
}

TSQueryError :: enum u32 {
    NONE      :: 0;
    SYNTAX    :: 1;
    NODE_TYPE :: 2;
    FIELD     :: 3;
    CAPTURE   :: 4;
    STRUCTURE :: 5;
    LANGUAGE  :: 6;
}

// read: (payload, byte_index, position, *bytes_read) -> *u8 chunk
TSReadFn :: #type (payload: *void, byte_index: u32, position: TSPoint, bytes_read: *u32) -> *u8 #c_call;

TSInput :: struct {
    payload:  *void;
    read:     TSReadFn;
    encoding: TSInputEncoding;
}

// ---- parser -----------------------------------------------------------------

ts_parser_new          :: () -> *TSParser #foreign tree_sitter;
ts_parser_delete       :: (self: *TSParser) #foreign tree_sitter;
ts_parser_set_language :: (self: *TSParser, language: *TSLanguage) -> bool #foreign tree_sitter;
ts_parser_parse        :: (self: *TSParser, old_tree: *TSTree, input: TSInput) -> *TSTree #foreign tree_sitter;
ts_parser_parse_string :: (self: *TSParser, old_tree: *TSTree, str: *u8, length: u32) -> *TSTree #foreign tree_sitter;
ts_parser_reset        :: (self: *TSParser) #foreign tree_sitter;

// ---- tree / node ------------------------------------------------------------

ts_tree_delete    :: (self: *TSTree) #foreign tree_sitter;
ts_tree_edit      :: (self: *TSTree, edit: *TSInputEdit) #foreign tree_sitter;
ts_tree_root_node :: (self: *TSTree) -> TSNode #foreign tree_sitter;

ts_node_start_byte :: (self: TSNode) -> u32 #foreign tree_sitter;
ts_node_end_byte   :: (self: TSNode) -> u32 #foreign tree_sitter;
ts_node_type       :: (self: TSNode) -> *u8 #foreign tree_sitter;
ts_node_is_null    :: (self: TSNode) -> bool #foreign tree_sitter;
ts_node_child_count :: (self: TSNode) -> u32 #foreign tree_sitter;
ts_node_child       :: (self: TSNode, child_index: u32) -> TSNode #foreign tree_sitter;

// ---- query ------------------------------------------------------------------

ts_query_new    :: (language: *TSLanguage, source: *u8, source_len: u32, error_offset: *u32, error_type: *TSQueryError) -> *TSQuery #foreign tree_sitter;
ts_query_delete :: (self: *TSQuery) #foreign tree_sitter;
ts_query_capture_count :: (self: *TSQuery) -> u32 #foreign tree_sitter;
ts_query_capture_name_for_id :: (self: *TSQuery, index: u32, length: *u32) -> *u8 #foreign tree_sitter;

ts_query_cursor_new        :: () -> *TSQueryCursor #foreign tree_sitter;
ts_query_cursor_delete     :: (self: *TSQueryCursor) #foreign tree_sitter;
ts_query_cursor_exec       :: (self: *TSQueryCursor, query: *TSQuery, node: TSNode) #foreign tree_sitter;
ts_query_cursor_set_byte_range :: (self: *TSQueryCursor, start_byte: u32, end_byte: u32) #foreign tree_sitter;
ts_query_cursor_next_match :: (self: *TSQueryCursor, match: *TSQueryMatch) -> bool #foreign tree_sitter;
