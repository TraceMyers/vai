
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// basically, when you have a constant array like .[.{something, enum0}, .{something, enum1}, .{something, enum2}... ]
// and, optionally, if you want to generate a hash table for that data as .{key, value}, this allows you to define
// the enum and the mapping at the same time, (as well as the hash table and its initialization/shutdown procs.)

TempEnumMapping :: struct($InInputType: Type, $IN_ARRAY_COUNT: u32, $InExtensionType: Type = void) {
    #if IN_ARRAY_COUNT == 1 {
        input: InInputType;
    } else {
        input: [IN_ARRAY_COUNT]InInputType;
    }
    enum_name: string;
    #if InExtensionType != void {
        extension: InExtensionType;
    }
    InputType :: InInputType;
    ExtensionType :: InExtensionType;
    ARRAY_COUNT :: IN_ARRAY_COUNT;
    #run assert(IN_ARRAY_COUNT >= 1);
}

Generate_Struct_Enum_Mapping :: (enum_type_name: string, $EnumBackingType: Type, mapping_type_name: string, array_name: string, $TempType: Type, indexable: bool, enum_cast_proc_name := "", array_is_constant := true, mappings: string) -> string {
    builder_a: String_Builder;
    builder_b: String_Builder;

    enum_names: [..]string;

    out_type_has_extension := TempType.ExtensionType != void;

    // make the enum type and the array of mappings at the same time
    print_to_builder(*builder_a, "% :: enum % {\n", enum_type_name, EnumBackingType);
    if array_is_constant {
        print_to_builder(*builder_b, "% :: %.[\n", array_name, mapping_type_name);
    } else {
        print_to_builder(*builder_b, "% := %.[\n", array_name, mapping_type_name);
    }
    mappings_cur := mappings;
    while true {
        success_1, input_struct, right := split_from_left(mappings_cur, #char "]");
        if !success_1 then break;
        success_2, _1, begin_enum_name := split_from_left(right, #char "\"");
        assert(success_2);
        success_3, enum_name, end_line := split_from_left(begin_enum_name, #char "\"");
        assert(success_3);
        enum_is_duplicate := false;
        for enum_names {
            if it == enum_name {
                if indexable {
                    Log_Error("mapping marked as indexable, but a duplicate enum was found");
                    assert(false);
                } else {
                    enum_is_duplicate = true;
                    break;
                }
            }
        }
        if !enum_is_duplicate {
            // make one enum value
            array_add(*enum_names, enum_name);
            print_to_builder(*builder_a, "\t%;\n", enum_name);
        }
        // make one struct-enum mapping value
        _, _, input_struct = split_from_left(input_struct, #char "[");
        if TempType.ARRAY_COUNT > 1 {
            input_struct = tprint(".[%]", input_struct);
        }

        // if there's an extension type, pack it in
        extension: string;
        if out_type_has_extension {
            success_yech, _, begin_extension := split_from_left(end_line, #char ".");
            assert(success_yech);
            success_double_yech, capture_extension, actual_end_line := split_from_left(begin_extension, #char "}");
            assert(success_double_yech);
            extension = capture_extension;
            // include the '}'
            extension.count += 1;
            if indexable {
                extension = tprint(", %.%", TempType.ExtensionType, extension);
            } else {
                extension = tprint(" %.%,", TempType.ExtensionType, extension);
            }
            end_line = actual_end_line;
        }

        if indexable {
            print_to_builder(*builder_b, "\t%.{%0%},\n", mapping_type_name, input_struct, extension);
        } else {
            print_to_builder(*builder_b, "\t%.{%,% %.%},\n", mapping_type_name, input_struct, extension, enum_type_name, enum_name);
        }
        success_1, _, mappings_cur = split_from_left(end_line, #char ".");
        if success_1 {
            mappings_cur.data -= 1; // start on the next '.'
            mappings_cur.count += 1;
        }
    }
    print_to_builder(*builder_b, "];\n\n");
    print_to_builder(*builder_a, "}\n\n");

    // make the mapping struct type with the enum as a member
    struct_info := cast(*Type_Info_Struct)TempType;
    print_to_builder(*builder_a, "% :: struct {\n", mapping_type_name);
    print_to_builder(*builder_a, "\t%: %;\n", struct_info.members[0].name, (cast(*Type)(*struct_info.members[0].type)).*);
    extension := ifx TempType.ExtensionType != void then tprint("\textension: %;\n", TempType.ExtensionType) else "";
    if indexable {
        print_to_builder(*builder_a, "%}\n", extension, enum_type_name);
    } else {
        print_to_builder(*builder_a, "%\n\tenum_val: %;\n}\n", extension, enum_type_name);
    }

    // convenience procs for casting from integer to enum
    if indexable && enum_cast_proc_name.count > 0 {
        print_to_builder(*builder_b, "% :: inline (val: %) -> % { return cast(%)val; }\n", enum_cast_proc_name, EnumBackingType, enum_type_name, enum_type_name);
        print_to_builder(*builder_b, "% :: inline (val: s64) -> % { return cast(%)val; }\n", enum_cast_proc_name, enum_type_name, enum_type_name);
    }

    print_to_builder(*builder_a, "\n%", builder_to_string(*builder_b));
    return builder_to_string(*builder_a);
}