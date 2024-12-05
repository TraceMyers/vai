
#insert #run Generate_Struct_Enum_Mapping("Action", u16, "ComptimeActionBinding", "DEFAULT_ACTION_BINDINGS", TempEnumMapping(string, 1, ActionDataContainer), true, "As_Action", true,
#string HERE
    .{.["j"],                   "SCROLL_DOWN",                                  .{modes=.NORMAL, proc=Cursor_Scroll_Down}},
    .{.["k"],                   "SCROLL_UP",                                    .{modes=.NORMAL, proc=Cursor_Scroll_Up}},
    .{.["h"],                   "SCROLL_LEFT",                                  .{modes=.NORMAL, proc=Cursor_Scroll_Left}},
    .{.["l"],                   "SCROLL_RIGHT",                                 .{modes=.NORMAL, proc=Cursor_Scroll_Right}},
    .{.["gg"],                  "SCROLL_TO_TOP_OF_FILE",                        .{modes=.NORMAL, proc=Cursor_Scroll_To_Top}},
    .{.["G"],                   "SCROLL_TO_BOTTOM_OF_FILE",                     .{modes=.NORMAL, proc=Cursor_Scroll_To_Bottom}},
    .{.["$"],                   "SCROLL_TO_LINE_END",                           .{modes=.NORMAL, proc=Cursor_Scroll_To_Line_End}},
    .{.["^"],                   "SCROLL_TO_LINE_NON_WHITESPACE_BEGIN",          .{modes=.NORMAL}},
    .{.["0"],                   "SCROLL_TO_LINE_ZERO",                          .{modes=.NORMAL}},
    .{.["<C-w><C-w>"],          "SCROLL_FILE_EDITORS",                          .{modes=.NORMAL}},
    .{.[":"],                   "ENTER_COMMAND_MODE",                           .{modes=.NORMAL}},
    .{.["<CR>"],                "ENTER_NORMAL_MODE",                            .{modes=.COMMAND}},
    .{.["<CR>"],                "INSERT_NEW_LINE"           ,                   .{modes=.INSERT}},
    .{.["i"],                   "ENTER_INSERT_MODE_PREPEND",                    .{modes=.NORMAL}},
    .{.["a"],                   "ENTER_INSERT_MODE_APPEND",                     .{modes=.NORMAL}},
    .{.["\x08"],                "BACKSPACE",                                    .{modes=.COMMAND | .INSERT}},            
    .{.["<Esc>"],               "VOID_INPUT",                                   .{modes=.ALL}},
    .{.["x"],                   "DELETE_CHARACTER",                             .{modes=.NORMAL}},
    .{.["o"],                   "APPEND_NEW_LINE_AND_INSERT",                   .{modes=.NORMAL}},
    .{.["O"],                   "PREPEND_NEW_LINE_AND_INSERT",                  .{modes=.NORMAL}},
    .{.["dd"],                  "DELETE_LINE",                                  .{modes=.NORMAL}},
    .(.["w"],                   "SCROLL_FORWARD_SMALL_WORD",                    .{modes=.NORMAL}),
    .(.["W"],                   "SCROLL_FORWARD_LARGE_WORD",                    .{modes=.NORMAL}),
    .(.["b"],                   "SCROLL_BACKWARD_SMALL_WORD",                   .{modes=.NORMAL}),
    .(.["B"],                   "SCROLL_BACKWARD_LARGE_WORD",                   .{modes=.NORMAL}),
    .{.["__INTERNAL__"],        "CLAMP_CURSOR_X_TO_BOUNDS"                      .{modes=.NONE}},
    .{.["__INTERNAL__"],        "NONE",                                         .{modes=.NONE}}
HERE
);

#insert #run Generate_Struct_Enum_Mapping("Option", u16, "OptionMapping", "option_mappings", TempEnumMapping(string, 2, OptionSetting), true, "As_Option", false,
#string HERE
    .{.["number", "nu"],        "LINE_NUMBERS",                 .{type=.BOOL, _bool=true}},
    .{.["smartcase", "scs"],    "PATTERN_SEARCH_SMART_CASE",    .{type=.BOOL, _bool=true}},
    .{.["indentation", "ind"],  "INDENTATION_WIDTH"             .{type=.INTEGER, _integer=4}},
    .{.["softwrap", "swp"],     "SOFT_WRAP_INDENTATION_WIDTH"   .{type=.INTEGER, _integer=2}}
HERE
);

#insert #run Generate_Struct_Enum_Mapping("Command", u32, "CommandBinding", "COMPTIME_COMMAND_BINDINGS", TempEnumMapping(string, 1), true, "As_Command", true,
#string HERE
    .{.["none"],        "NONE"},
    .{.["quit"],        "QUIT"},
    .{.["edit"],        "OPEN_FILE"},
    .{.["bnext"],       "NEXT_BUFFER"},
    .{.["bprev"],       "PREVIOUS_BUFFER"},
    .{.["vsplit"],      "VERTICAL_SPLIT"},
    .{.["split"],       "HORIZONTAL_SPLIT"},
    .{.["set"],         "INTERACT_WITH_OPTIONS"},
    .{.["write"],       "WRITE_TO_FILE"},
HERE
);
