
#insert #run Generate_Struct_Enum_Mapping("Action", u16, "ComptimeActionBinding", "DEFAULT_ACTION_BINDINGS", TempEnumMapping(string, 1, VimModeContainer), true, "As_Action", true,
#string HERE
    .{.["j"],                   "SCROLL_DOWN",                                  .{.NORMAL}},
    .{.["k"],                   "SCROLL_UP",                                    .{.NORMAL}},
    .{.["h"],                   "SCROLL_LEFT",                                  .{.NORMAL}},
    .{.["l"],                   "SCROLL_RIGHT",                                 .{.NORMAL}},
    .{.["gg"],                  "SCROLL_TO_TOP_OF_FILE",                        .{.NORMAL}},
    .{.["G"],                   "SCROLL_TO_BOTTOM_OF_FILE",                     .{.NORMAL}},
    .{.["$"],                   "SCROLL_TO_LINE_END",                           .{.NORMAL}},
    .{.["^"],                   "SCROLL_TO_LINE_NON_WHITESPACE_BEGIN",          .{.NORMAL}},
    .{.["0"],                   "SCROLL_TO_LINE_ZERO",                          .{.NORMAL}},
    .{.["<C-w><C-w>"],          "SCROLL_FILE_EDITORS",                          .{.NORMAL}},
    .{.[":"],                   "ENTER_COMMAND_MODE",                           .{.NORMAL}},
    .{.["<CR>"],                "ENTER_NORMAL_MODE",                            .{.COMMAND}},
    .{.["<CR>"],                "INSERT_NEW_LINE"           ,                   .{.INSERT}},
    .{.["i"],                   "ENTER_INSERT_MODE_PREPEND",                    .{.NORMAL}},
    .{.["a"],                   "ENTER_INSERT_MODE_APPEND",                     .{.NORMAL}},
    .{.["\x08"],                "BACKSPACE",                                    .{.COMMAND | .INSERT}},            
    .{.["<Esc>"],               "VOID_INPUT",                                   .{.ALL}},
    .{.["x"],                   "DELETE_CHARACTER",                             .{.NORMAL}},
    .{.["o"],                   "APPEND_NEW_LINE_AND_INSERT",                   .{.NORMAL}},
    .{.["O"],                   "PREPEND_NEW_LINE_AND_INSERT",                  .{.NORMAL}},
    .{.["dd"],                  "DELETE_LINE",                                  .{.NORMAL}},
    .(.["w"],                   "SCROLL_FORWARD_SMALL_WORD",                    .{.NORMAL}),
    .(.["W"],                   "SCROLL_FORWARD_LARGE_WORD",                    .{.NORMAL}),
    .(.["b"],                   "SCROLL_BACKWARD_SMALL_WORD",                   .{.NORMAL}),
    .(.["B"],                   "SCROLL_BACKWARD_LARGE_WORD",                   .{.NORMAL}),
    .{.["__INTERNAL__"],        "CLAMP_CURSOR_X_TO_BOUNDS"                      .{.NONE}},
    .{.["__INTERNAL__"],        "NONE",                                         .{.NONE}}
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
