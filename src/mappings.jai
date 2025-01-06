
#insert #run Generate_Struct_Enum_Mapping("Action", u16, "ComptimeActionBinding", "DEFAULT_ACTION_BINDINGS", TempEnumMapping(string, 1, ActionDataContainer), true, "As_Action", true,
#string HERE
    .{.["j"],                   "SCROLL_DOWN",                                  .{modes=.NORMAL | .VISUAL,                      proc=Cursor_Scroll_Down}},
    .{.["k"],                   "SCROLL_UP",                                    .{modes=.NORMAL | .VISUAL,                      proc=Cursor_Scroll_Up}},
    .{.["h"],                   "SCROLL_LEFT",                                  .{modes=.NORMAL | .VISUAL,                      proc=Cursor_Scroll_Left}},
    .{.["l"],                   "SCROLL_RIGHT",                                 .{modes=.NORMAL | .VISUAL,                      proc=Cursor_Scroll_Right}},
    .{.["gg"],                  "SCROLL_TO_TOP_OF_FILE",                        .{modes=.NORMAL | .VISUAL,                      proc=Cursor_Scroll_To_Top}},
    .{.["G"],                   "SCROLL_TO_BOTTOM_OF_FILE",                     .{modes=.NORMAL | .VISUAL,                      proc=Cursor_Scroll_To_Bottom}},
    .{.["$"],                   "SCROLL_TO_LINE_END",                           .{modes=.NORMAL | .VISUAL,                      proc=Cursor_Scroll_To_Line_End}},
    .{.["^"],                   "SCROLL_TO_LINE_NON_WHITESPACE_BEGIN",          .{modes=.NORMAL | .VISUAL,                      proc=Cursor_Scroll_To_Line_Begin}},
    .{.["0"],                   "SCROLL_TO_LINE_ZERO",                          .{modes=.NORMAL | .VISUAL,                      proc=Cursor_Scroll_To_Line_Zero}},
    .{.["<C-w><C-w>"],          "SCROLL_TO_NEXT_EDITOR",                        .{modes=.NORMAL | .VISUAL,                      proc=Scroll_To_Next_Editor}},
    .{.[":"],                   "ENTER_COMMAND_MODE",                           .{modes=.NORMAL}},
    .{.["v"],                   "ENTER_VISUAL_MODE",                            .{modes=.NORMAL,                                proc=Enter_Visual_Mode}},
    .{.["<CR>"],                "EXECUTE_COMMANDS_AND_ENTER_NORMAL_MODE",       .{modes=.COMMAND}},
    .{.["<CR>"],                "INSERT_NEW_LINE"           ,                   .{modes=.INSERT, is_change=true,                proc=Insert_New_Line}},
    .{.["i"],                   "ENTER_INSERT_MODE_PREPEND",                    .{modes=.NORMAL,                                proc=Enter_Insert_Mode_Prepend}},
    .{.["a"],                   "ENTER_INSERT_MODE_APPEND",                     .{modes=.NORMAL,                                proc=Enter_Insert_Mode_Append}},
    .{.["\x08"],                "BACKSPACE",                                    .{modes=.COMMAND | .INSERT, is_change=true,     proc=Backspace}},            
    .{.["<Esc>"],               "ENTER_NORMAL_MODE",                            .{modes=.ALL,                                   proc=Enter_Normal_Mode}},
    .{.["x"],                   "DELETE_CHARACTER",                             .{modes=.NORMAL, is_change=true,                proc=Delete_Character}},
    .{.["o"],                   "APPEND_NEW_LINE_AND_INSERT",                   .{modes=.NORMAL, is_change=true,                proc=Append_Line_And_Enter_Insert_Mode}},
    .{.["O"],                   "PREPEND_NEW_LINE_AND_INSERT",                  .{modes=.NORMAL, is_change=true,                proc=Prepend_Line_And_Enter_Insert_Mode}},
    .{.["dd"],                  "DELETE_LINE",                                  .{modes=.NORMAL, is_change=true,                proc=Delete_Line}},
    .(.["w"],                   "SCROLL_FORWARD_SMALL_WORD",                    .{modes=.NORMAL | .VISUAL,                      proc=Word_Scroll_Forward_Small}),
    .(.["W"],                   "SCROLL_FORWARD_LARGE_WORD",                    .{modes=.NORMAL | .VISUAL,                      proc=Word_Scroll_Forward_Large}),
    .(.["b"],                   "SCROLL_BACKWARD_SMALL_WORD",                   .{modes=.NORMAL | .VISUAL,                      proc=Word_Scroll_Backward_Small}),
    .(.["B"],                   "SCROLL_BACKWARD_LARGE_WORD",                   .{modes=.NORMAL | .VISUAL,                      proc=Word_Scroll_Backward_Large}),
    .{.["e"],                   "SCROLL_FORWARD_TO_END_OF_SMALL_WORD",          .{modes=.NORMAL | .VISUAL,                      proc=Word_Scroll_To_End_Small}},
    .{.["E"],                   "SCROLL_FORWARD_TO_END_OF_LARGE_WORD",          .{modes=.NORMAL | .VISUAL,                      proc=Word_Scroll_To_End_Large}},
    .{.["dw"],                  "DELETE_WORD",                                  .{modes=.NORMAL, is_change=true,                proc=Delete_Word_Small}},
    .{.["diw"],                 "DELETE_INSIDE_WORD",                           .{modes=.NORMAL, is_change=true,                proc=Delete_Word_Inside_Small}},
    .{.["."],                   "REPEAT_LAST_CHANGE",                           .{modes=.NORMAL,                                proc=Repeat_Last_Change}},
    .{.["d"],                   "DELETE_SELECTION",                             .{modes=.VISUAL, is_change=true,                proc=Delete_Selection_And_Enter_Normal_Mode}},
    .{.["<C-/>"],               "TOGGLE_COMMENT_SELECTION"                      .{modes=.NORMAL | .VISUAL, is_change=true,      proc=Toggle_Comment_Selection}},
    .{.["c"],                   "REPLACE_SELECTION",                            .{modes=.VISUAL,                                proc=Replace_Selection}},
    .{.["cc"],                  "REPLACE_LINE",                                 .{modes=.NORMAL, is_change=true,                proc=Replace_Line}},
    .{.["cw"],                  "REPLACE_WORD",                                 .{modes=.NORMAL, is_change=true,                proc=Replace_Word_Small}},
    .{.["ciw"],                 "REPLACE_INSIDE_WORD",                          .{modes=.NORMAL, is_change=true,                proc=Replace_Word_Inside_Small}},
    .{.["d0"],                  "DELETE_TOWARD_LINE_ZERO",                      .{modes=.NORMAL, is_change=true,                proc=Delete_Toward_Line_Zero}},
    .{.["c0"],                  "REPLACE_TOWARD_LINE_ZERO",                     .{modes=.NORMAL, is_change=true,                proc=Replace_Toward_Line_Zero}},
    .{.["u"],                   "UNDO",                                         .{modes=.NORMAL,                                proc=Undo}},
    .{.["<C-r>"],               "REDO"              ,                           .{modes=.NORMAL,                                proc=Redo}},
    .{.["<C-p>"],               "PLAY_INPUT_RECORD"             ,               .{modes=.NORMAL,                                proc=Play_Input_Record}},
    .{.["__INTERNAL__"],        "CLAMP_CURSOR_X_TO_BOUNDS"                      .{modes=.NONE}},
    .{.["__INTERNAL__"],        "NONE",                                         .{modes=.NONE}},
    .{.["__INTERNAL__"],        "INTERNAL_MOVE_CURSOR_TO_POSITION",             .{modes=.ALL    ,                               proc=Internal_Move_Cursor_To_Position}}
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
