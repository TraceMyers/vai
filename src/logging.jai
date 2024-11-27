
Log_Error :: (fmt: string, args: ..Any, log_location := true, caller_loc := #caller_location) #expand {
    log_context := #procedure_name();
    Log_Impl(fmt, ..args, log_context=log_context, log_location, caller_loc, "ERROR");
}

Log_Warning :: (fmt: string, args: ..Any, log_location := true, caller_loc := #caller_location) #expand {
    log_context := #procedure_name();
    Log_Impl(fmt, ..args, log_context=log_context, log_location, caller_loc, "WARNING");
}

Log :: (fmt: string, args: ..Any, log_location := false, caller_loc := #caller_location, header := "LOG") #expand {
    log_context := #procedure_name();
    Log_Impl(fmt, ..args, log_context=log_context, log_location, caller_loc, header);
}

Log_Impl :: (
    fmt: string, 
    args: ..Any, 
    log_context: string, 
    log_location: bool, 
    caller_loc: Source_Code_Location, 
    header: string
) {
    MAX_HEADER_COUNT :: 8;
    MAX_CONTEXT_COUNT :: 32;
    BRACKETS_COUNT :: 4;
    END_LEAD_SPACE :: 1;
    LEAD_BUFFER_SIZE :: MAX_HEADER_COUNT + MAX_CONTEXT_COUNT + BRACKETS_COUNT;

    lead_buffer := talloc(LEAD_BUFFER_SIZE);
    lead_buffer_string := string.{0, xx lead_buffer};
    Print_Lead_Item_To_Buffer_String(*lead_buffer_string, header, MAX_HEADER_COUNT);
    Print_Lead_Item_To_Buffer_String(*lead_buffer_string, log_context, MAX_CONTEXT_COUNT);

    use_location: string;
    if log_location {
        use_location = tprint("\n          >> (location: %)", caller_loc);
    }

    msg := tprint(fmt, ..args);
    log("% % %", lead_buffer_string, msg, use_location);
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

Print_Char_To_Buffer_String :: inline (bufstr: *string, char: u8) {
    bufstr.count += 1;
    bufstr.*[bufstr.count-1] = char;
}

Print_Lead_Item_To_Buffer_String :: inline (bufstr: *string, lead_item: string, $MAX_COUNT: s64) {
    Print_Char_To_Buffer_String(bufstr, #char "[");
    remain_space := MAX_COUNT - lead_item.count;
    for c : 0..lead_item.count-1 {
        if c >= MAX_COUNT then break;
        else if remain_space < 0 && (c == MAX_COUNT-2 || c == MAX_COUNT-1) {
            Print_Char_To_Buffer_String(bufstr, #char ".");
        } else {
            Print_Char_To_Buffer_String(bufstr, lead_item[c]);
        }
    }
    Print_Char_To_Buffer_String(bufstr, #char "]");

    for i : 0..remain_space-1 {
        Print_Char_To_Buffer_String(bufstr, #char " ");
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#import "Basic";
#import "Math";
