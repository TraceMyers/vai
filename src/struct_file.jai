
// ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////// 
// --------------------------------------------------------------------------------------- struct load/save w/ text file
// ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////// 
// a utility that auto-populates a text file with members of a struct (only some struct member types supported),
// and allows changing the values of the struct across runs either by editing the struct at runtime before saving
// to file, or by editing the text file representing the struct fields between runs. obviously something that should 
// only be sparsely if at all used in shipping code, but it is convenient to just get going with settings.


// creates if/else's checking if member_name matches any struct member's name.
// assigns parsed value to struct member if a match is found.
Struct_String_Assign :: (s: *$StructType, member_name: string, value: string) {
    gen_code :: ($StructType: Type) -> string {
        builder: String_Builder;
        // defer free_buffers(*builder);
        made_first_line := false;
        info_struct := cast(*Type_Info_Struct) type_info(StructType);
        size_count : s64;
        for info_struct.members {
            // ignore place'd at the end and other nonsimple stuff
            if it.flags != 0 then continue;
            next_size := size_count + it.type.runtime_size;
            if next_size > info_struct.runtime_size then break;
            // todo: more options
            parse_function := ifx it.type.type == .FLOAT then "parse_float"
                else ifx it.type.type == .INTEGER then "parse_int"
                else ifx it.type.type == .BOOL then "parse_bool"
                else ifx it.type.type == .STRING then "";
                // else ifx it.type.type == .ENUM then // would need to iterate through enum names.
            fmt_string: string;
            if it.type.type == .STRING {
                fmt_string = "if member_name == \"%\" { s.% = %value }\n";
            } else {
                fmt_string = ifx !made_first_line
                    then "if member_name == \"%\" { s.% = cast(%) %(*value); }\n"
                    else "else if member_name == \"%\" { s.% = cast(%) %(*value); }\n";
            }
            print_to_builder(
                *builder, 
                fmt_string,
                it.name, 
                it.name, 
                <<cast(*Type) *it.type,
                parse_function
            );
            made_first_line = true;
            size_count = next_size;
        }
        str := builder_to_string(*builder);
        // log("struct string assign body:\n%", str);
        return str;
    }
    #insert #run gen_code(StructType);
}

Struct_Text_File_Line_Iterate :: (
    s: *$StructType, file_substring: string, line_count: *s64, token_left: *string, token_right: *string
) -> bool {
    endline_index := find_index_from_left(file_substring, "\n", 0);
    if endline_index == -1 {
        endline_index = file_substring.count;
        <<line_count = endline_index;
    } else {
        <<line_count = endline_index + 1;
    }

    full_line := slice(file_substring, 0, endline_index);
    equals_index := find_index_from_left(full_line, "=", 0);
    
    if equals_index == -1 then return false;

    <<token_left = trim(slice(full_line, 0, equals_index));
    <<token_right = trim(slice(full_line, equals_index + 1, full_line.count - (equals_index + 1)));

    if token_left.count <= 0 || token_right.count <= 0 then return false;

    return true;
}

Load_Struct_From_Text_File :: (file_path: string, s: *$StructType) {
    <<s = StructType.{};
    struct_file, success := file_open(file_path, keep_existing_content=true);
    if success {
        defer file_close(*struct_file);
        file_string, success := read_entire_file(struct_file);
        if file_string.data != null {
            defer free(file_string.data);

            file_substring := file_string;
            line_count : s64 = 0;
            token_left : string;
            token_right : string;

            while true {
                file_substring = slice(file_substring, line_count, file_substring.count - line_count);
                // is in the set of shortest possible lines in this kind of file are all of length 3, eg "v=0"
                if file_substring.count < 3 then break;
                if (!Struct_Text_File_Line_Iterate(s, file_substring, *line_count, *token_left, *token_right)) {
                    continue;
                }
                Struct_String_Assign(s, token_left, token_right);
            }
        }
    }
}

Save_Struct_To_Text_File :: (file_path: string, s: *$StructType) {
    file_builder: String_Builder;
    // generates fn body that, per member in StructType, adds a line to the string builder:
    // "struct_member_name = [value of member]\n"
    gen_code :: ($StructType: Type) -> string {
        fn_builder: String_Builder;
        defer free_buffers(*fn_builder);
        info_struct := cast(*Type_Info_Struct) type_info(StructType);
        size_count := 0;
        for info_struct.members {
            // ignore place'd at the end and other nonsimple stuff
            if it.flags != 0 then continue;
            next_size := size_count + it.type.runtime_size;
            if next_size > info_struct.runtime_size then break;
            print_to_builder(*fn_builder, "print_to_builder(*file_builder, \"% = \%\\n\", s.%);\n", it.name, it.name);
            size_count = next_size;
        }
        return builder_to_string(*fn_builder);
    }
    #insert #run gen_code(StructType);
    write_entire_file(file_path, *file_builder);
}