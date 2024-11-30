Code_String :: ($code: Code) -> string {
    builder: String_Builder;
    assert(Program_Print.print_expression(*builder, Compiler.compiler_get_nodes(code)));
    return builder_to_string(*builder);
}

Is_Type :: (info: *Type_Info, base_name: string) -> bool {
    if info.type != .STRUCT return false;
    info_struct := cast(*Type_Info_Struct) info;
    return info_struct.name == base_name;
}

Is_Subtype :: (info: *Type_Info, base_name: string, $check_equal_base_type := false) -> bool {
    #if (check_equal_base_type) {
        using Type_Info_Tag;
        if info.type != STRUCT return false;
        info_struct := cast(*Type_Info_Struct) info;
        if info_struct.name == base_name {
            return true;
        }
    }
    return Compiler.is_subclass_of(info, base_name);
}

Mark_Temp :: () #expand {
    `auto_release_temp();
}