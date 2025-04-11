
// TODO: flatten os console, delete 
OS_Console :: struct {

    Initialize :: () -> bool {
        input_buffer = NewArray(BUFFER_SIZE, u8);
        output_buffer = NewArray(BUFFER_SIZE, u8);
        input.data = input_buffer.data;
        output.data = output_buffer.data;
        Bin_Pool_Initialize(*info_strings);
        return true;
    }

    Shutdown :: () {
        Array_Delete(*input_buffer);
        Array_Delete(*output_buffer);
        input = .{};
        output = .{};
        Shutdown_Console(true);
        Bin_Pool_Shutdown(*info_strings);
    }
}

Render_Layer :: (using os_console: *OSConsole, is_active: bool, render_pass: ViewRenderPass) {
    view := *view_pool.items[tool_view_id];
    // hidden. hacky
    if view.viewport.left <= 0.0 {
        return;
    }
    if render_pass == {
    case .BACKGROUND;
    case .TEXT;
        Render_OS_Console_Text(os_console, is_active);
    case .LINES;
    }
}

Render_OS_Console_Text :: no_inline (using os_console: *OSConsole, is_active: bool) {
    if pseudoconsole == null {
        if !Initialize_Console(os_console) {
            Shutdown_Console(false);
            return;
        } 
        Test(os_console);
    }

    // for testing
    if io_state == .RECEIVE_OUTPUT || io_state == .SEND_INPUT {
        return;
    }
    if io_state == .OUTPUT_READY_AND_COMPLETE {
        if test_input_queue.count > 0 {
            input.count = test_input_queue[0].count;
            memcpy(input.data, test_input_queue[0].data, test_input_queue[0].count);
            array_ordered_remove_by_index(*test_input_queue, 0);
            io_state = .SEND_INPUT;
        }
    }
}

Parse_OS_Console_Output :: (output: []u8, cur_attributes: *TextAttributes) {
    if output.count == 0 {
        return;
    }
    current_text: []u8;
    // Log("output: %", output);

    Print_Hex_Dump(output);
    process_escape_sequence: bool;

    for i : 0..output.count-1 {
        if process_escape_sequence {
            if i == output.count-1 {
                break;
            }
            remain_output := string.{output.count-1, *output[i+1]};
            sequence: string;
            if cast(EscapeCode) output[i] == {
            case .SINGLE_SHIFT_TWO;
            case .SINGLE_SHIFT_THREE;
            case .DEVICE_CONTROL_STRING;
            case .CONTROL_SEQUENCE_INTRODUCER;
                sequence = Get_Control_Sequence(remain_output);
            case .STRING_TERMINATOR;
            case .OPERATING_SYSTEM_COMMAND;
                sequence = Get_OS_Command_Sequence(remain_output);
            case .START_OF_STRING;
            case .PRIVACY_MESSAGE;
            case .APPLICATION_CONTROL_COMMAND; 
            case;
            }
            i += sequence.count;
            process_escape_sequence = false;
        } else if output[i] == #char "\x1b" {
            process_escape_sequence = true;
        } else {
            if current_text.data == null {
                current_text.data = xx *output[i];
                current_text.count = 1;
            } else {
                current_text.count += 1;
            }
            if i + 1 == output.count || output[i+1] == #char "\x1b" {
                if current_text.count > 0 {
                    str := As_String(current_text);
                    print(str);
                }
                current_text = u8.[];
            }
        }
    }
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

// SequenceData :: struct {
//     sequence: string;

// }

Advance :: (str: *string, count := 1, $ASSERT_CHARS_REMAIN := false) {
    count_min := #ifx ASSERT_CHARS_REMAIN then count+1 else count;
    assert(str.count >= count_min);
    str.count -= count;
    str.data += count;
}

Extract_Number_From_Sequence :: (sequence: *string) -> number: s32, number_is_explicit: bool {
    n: s32;
    explicit_number_found := false;
    while sequence.count > 0 && sequence.*[0] >= #char "0" && sequence.*[0] <= #char "9" {
        digit := sequence.*[0] - #char "0";
        n *= 10;
        n += digit;
        explicit_number_found = true;
        assert(n <= S16_MAX); // required by win32 api
        Advance(sequence, 1, true);
    }
    return max(n, sdw(1)), explicit_number_found;
}

// TODO: return data bout the sequence, not just the string
Get_Control_Sequence :: (str: string) -> string {
    assert(str.count > 0);

    sequence := str;

    // these dimensions are optional, representing distance of movement and such
    y, explicit_distance := Extract_Number_From_Sequence(*sequence);
    x: s32 = ---;
    if sequence[0] == #char ";" {
        Advance(*sequence, 1, true);
        x, _ = Extract_Number_From_Sequence(*sequence);
    } else {
        x = 1;
    }

    if sequence[0] == {
    case #char " ";
        assert(explicit_distance);
        assert(sequence.count > 1 && sequence[1] == #char "q");
        Advance(*sequence, 2);
    case #char "?";
        assert(!explicit_distance);
        last_consumed_byte: u8 = 0;
        while sequence.count > 0 && last_consumed_byte != #char "l" && last_consumed_byte != #char "h" {
            last_consumed_byte = sequence[0];
            Advance(*sequence);
        }
    case #char "m";
        Advance(*sequence);
    case #char "H";
        Advance(*sequence);
    case #char "S";
        Advance(*sequence);
    case #char "T";
        Advance(*sequence);
    case #char "A";
        Advance(*sequence);
    case #char "B";
        Advance(*sequence);
    case #char "C";
        Advance(*sequence);
    case #char "D";
        Advance(*sequence);
    case #char "E";
        Advance(*sequence);
    case #char "F";
        Advance(*sequence);
    case #char "G";
        Advance(*sequence);
    case #char "d";
        Advance(*sequence);
    case #char "s";
        Advance(*sequence);
    case #char "u";
        Advance(*sequence);
    case #char "J";
        Advance(*sequence);
    }
    
    return string.{sequence.data - str.data, str.data};
}

Get_OS_Command_Sequence :: (str: string) -> string {
    assert(str.count > 0);
    sequence := string.{str.count, str.data};
    for 0..str.count-2 {
        // if str[it] == #char "\x1b" {
        //     if str[it+1] == xx EscapeCode.STRING_TERMINATOR {
        //         sequence.count = it+2;
        //         break;
        //     }
        // }
        // 7 ???
        if str[it] == 0x7 {
            sequence.count = it + 1;
        }
    }
    return sequence;
}

Send_Input_Loop :: (t: *Thread) -> s64 {
    console_layer := OS_Console_Layer();
    while io_state != .SHUTTING_DOWN {
        assert(io_state != .INACTIVE);
        if io_state == .SEND_INPUT {
            Send_Input(*console_layer.os_console, input);
            io_state = .RECEIVE_OUTPUT;
        }
        reset_temporary_storage();
        sleep_milliseconds(1);
    }
    return 0;
}

Receive_Output_Loop :: (t: *Thread) -> s64 {
    console_layer := OS_Console_Layer();
    while io_state != .SHUTTING_DOWN {
        assert(io_state != .INACTIVE);
        if io_state == .RECEIVE_OUTPUT {
            Receive_Output(*console_layer.os_console);        
            while Pipe_Bytes_Available(console_layer.os_console.output_read) > 0 {
                Receive_Output(*console_layer.os_console);        
            }
            io_state = .OUTPUT_READY_AND_COMPLETE;
        }
        reset_temporary_storage();
        sleep_milliseconds(1);
    }
    return 0;
}

Send_Input :: (using os_console: *OSConsole, utf8_str: string) {
    bytes_written: u32;
    write_data := To_Command(utf8_str);
    // Log("writing %", write_data);
    if !WriteFile(input_write, write_data.data, xx write_data.count, *bytes_written, null) {
        Log_Warning("unable to write % to os console pipe", utf8_str);
    }
}

Receive_Output :: (using os_console: *OSConsole) {
    bytes_read: u32;
    buffer: [2048]u8;
    if !ReadFile(output_read, buffer.data, 2048-1, *bytes_read, null) {
        Log_Warning("unable to read from os console output pipe");
    } else {
        read_in := string.{bytes_read, buffer.data};
        Parse_OS_Console_Output(As_Array(read_in, u8), null);
    }
}

To_Command :: inline (utf8_str: string) -> string {
    str := tprint("%\r\n\0", utf8_str);
    str.count -= 1;
    return str;
}

Is_Digit :: inline (c: u16) -> bool {
    return c >= #char "0" && c <= #char "9";
}

TextAttributes :: struct {
    color: s32;
}

Pipe_Bytes_Available :: (pipe: *void) -> u32 {
    bytes_available: u32;
    result := PeekNamedPipe(pipe, null, 0, null, *bytes_available, null);
    if result == .FALSE {
        return 0;
    } else return bytes_available;
}

Initialize_Console :: (using os_console: *OSConsole) -> bool {
    assert(io_state == .INACTIVE);

    // TODO: allow retry
    if init_failure {
        return false;
    }
    
    success := true;

    security_attributes: SECURITY_ATTRIBUTES;
    {
        using security_attributes;
        nLength = size_of(SECURITY_ATTRIBUTES);
        bInheritHandle = .TRUE;
    }

    if success && !CreatePipe(*output_read, *output_write, *security_attributes, 0) {
        Log_Error("unable to create stdout pipe for os console");
        success = false;
    }
    if success && !CreatePipe(*input_read, *input_write, *security_attributes, 0) {
        Log_Error("unable to create stdin pipe for os console");
        success = false;
    }
    if success {
        result := CreatePseudoConsole(.{200,1000}, input_read, output_write, 0, *pseudoconsole);
        if FAILED(result) {
            Log_Error("failed to create a pseudo console, win32 error: %", GetLastError());
            success = false;
        }
    }

    startup_info: STARTUPINFOEX;
    defer if startup_info.attribute_list != null then free(startup_info.attribute_list);

    if success {
        attribute_list_size: size_t;
        InitializeProcThreadAttributeList(null, 1, 0, *attribute_list_size);

        startup_info.info.cb = size_of(STARTUPINFOEX);
        startup_info.attribute_list = alloc(xx attribute_list_size);

        if startup_info.attribute_list == null {
            success = false;
        } else {
            success = xx InitializeProcThreadAttributeList(startup_info.attribute_list, 1, 0, *attribute_list_size);
            if !success {
                Log_Error("failed to initilalize proc attribute list, win32 error: %", GetLastError());
            }
        }
    }

    if success {
        attribute := PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE;
        success = xx UpdateProcThreadAttribute(startup_info.attribute_list, 0, xx attribute, pseudoconsole, size_of(*void), null, null);
        if !success {
            Log_Error("failed to update proc thread attribute, win32 error: %", GetLastError());
        }
    }

    if success {
        child_app_name := Encode("cmd.exe", .UTF8, .UTF16, append_null=true);
        process_info: PROCESS_INFORMATION;
        if !CreateProcessW(null, xx child_app_name.data, null, null, .FALSE, EXTENDED_STARTUPINFO_PRESENT, null, null, xx *startup_info, *process_info) {
            success = false;
            Log_Error("unable to create child process for os console, win32 error: %", GetLastError());
        } else {
            // invalid
            // terminal = process_info.hProcess;
            // terminal_id = process_info.dwProcessId;
        }
    }

    if success {
        io_state = .RECEIVE_OUTPUT;
        thread_init(*input_thread, Send_Input_Loop);
        thread_init(*output_thread, Receive_Output_Loop);
        thread_start(*input_thread);
        thread_start(*output_thread);
    }

    init_failure = !success;
    if init_failure {
        Log_Error("failed to initialize os console");
    } else {
        Log("succeeded initializing os console");
    }

    return success;
}

Shutdown_Console :: (reset: bool) {
    os_console_layer := OS_Console_Layer();
    os_console := *os_console_layer.os_console;
    Shutdown_Terminal(os_console);
    Shutdown_Threads();
    Shutdown_Pseudoconsole(os_console);
    Shutdown_Pipes(os_console);
    if reset then os_console.init_failure = false;
}

Shutdown_Pipe :: (using os_console: *OSConsole, $NAME: string) #expand {
    Generate_Proc :: () -> string {
        return tprint(SHUTDOWN_PIPE_BODY, NAME, NAME, NAME);
    }
    #insert #run Generate_Proc();
}

Shutdown_Pipes :: (using os_console: *OSConsole) {
    Shutdown_Pipe(os_console, "input_read");
    Shutdown_Pipe(os_console, "input_write");
    Shutdown_Pipe(os_console, "output_read");
    Shutdown_Pipe(os_console, "output_write");
}

Shutdown_Pseudoconsole :: (using os_console: *OSConsole) {
    if pseudoconsole == null then return;
    ClosePseudoConsole(pseudoconsole);
    CloseHandle(pseudoconsole);
    pseudoconsole = null;
}

Shutdown_Terminal :: (using os_console: *OSConsole) {
    if io_state != .INACTIVE {
        // catch-all to try to breeze through i/o states to one where threads are done working.
        Prepare_For_Input(os_console);
        Write_Command_To_Input("exit");
        Prepare_For_Input(os_console);
        wait_result := WaitForSingleObject(os_console.terminal, 100);
        TERMINAL_ENDED_EXECUTION :: WAIT_OBJECT_0;
        if wait_result == TERMINAL_ENDED_EXECUTION {
            CloseHandle(terminal);
        } // else, ClosePseudoConsole will terminate the process
    } else {
        assert(terminal == null);
    }
    os_console.terminal = null;
    os_console.terminal_id = 0;
}

Shutdown_Threads :: () {
    if io_state != .INACTIVE {
        io_state = .SHUTTING_DOWN;
        while !thread_is_done(*input_thread, 1) {;}
        while !thread_is_done(*output_thread, 1) {;}
        thread_deinit(*input_thread);
        thread_deinit(*output_thread);
        io_state = .INACTIVE;
    }
}

Test :: (using os_console: *OSConsole) {
    array_add(*test_input_queue, "python");
    array_add(*test_input_queue, "a=5");
    array_add(*test_input_queue, "b=2");
    array_add(*test_input_queue, "quit()");

//     sleep_milliseconds(100);

//     bytes_read: u32;
//     buffer: [2048]u8;
//     if !ReadFile(output_read, buffer.data, 2048-1, *bytes_read, null) {
//         Log_Warning("unable to read from os console output pipe");
//     } else {
//         read_in := string.{bytes_read, buffer.data};
//         Parse_OS_Console_Output(As_Array(read_in, u8), null);
//     }

//     sleep_milliseconds(100);

//     more := false;

//     for i : 0..4 {
//         write_data: string;
//         if i == 0 {
//             write_data = "python\r\n";
//         } else if i == 1 {
//             write_data = "a = 5\r\n";
//         } else if i == 2 {
//             write_data = "b = 2\r\n";
//         } else if i == 3 {
//             write_data = "a * b\r\n";
//         } else {
//             write_data = "quit()\r\n";
//         }
//         more = false;
//         bytes_written: u32;
//         if !WriteFile(input_write, write_data.data, xx write_data.count, *bytes_written, null) {
//             Log_Warning("unable to write to pipe");
//         }

//         sleep_milliseconds(100);
// ;
//         while Pipe_Bytes_Available(output_read) > 0 {
//             memset(buffer.data, 0, 2048);
//             if !ReadFile(output_read, buffer.data, 2048-1, *bytes_read, null) {
//                 Log_Warning("unable to read from os console output pipe");
//             } else {
//                 read_in := string.{bytes_read, buffer.data};
//                 Parse_OS_Console_Output(As_Array(read_in, u8), null);
//             }
//             sleep_milliseconds(100);
//         }
//     }
}

Prepare_For_Input :: (using os_console: *OSConsole) {
    if #complete io_state == {
    case .IDLE;
    case .SEND_INPUT;
        assert(false, "cannot prepare for input while input is being sent");
    case .SEND_INPUT_FAILURE;
    case .RECEIVE_OUTPUT;
        assert(false, "cannot prepare for input while output is being received");
    case .RECEIVE_OUTPUT_FAILURE;
    case .OUTPUT_READY_AND_COMPLETE;
    case .OUTPUT_READY_AND_INCOMPLETE;
    case .INACTIVE;
    case .SHUTTING_DOWN;
    }

    Clear_Input();
    Clear_Output();
}

Write_Command_To_Input :: (str: string) #expand {
    Write_To_Input(To_Command(str));
}

Write_To_IO :: ($BUF_NAME: string, in_str: string) -> bool {
    Generate_Proc :: () -> string {
        return tprint(WRITE_TO_IO_PROC_BODY, BUF_NAME, BUF_NAME, BUF_NAME, BUF_NAME, BUF_NAME);
    }
    #insert #run Generate_Proc();
}
Write_To_Input :: #bake_arguments Write_To_IO(BUF_NAME="input");
Write_To_Output :: #bake_arguments Write_To_IO(BUF_NAME="output");

Clear_Input :: () {
    if input.count > 0 {
        memset(input_buffer.data, 0, input.count);
    }
    input.count = 0;
}

Clear_Output :: () {
    if output.count > 0 {
        memset(output_buffer.data, 0, output.count);
    }
    output.count = 0;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

BUFFER_SIZE :: 32768;
text_attributes: TextAttributes;

IOState :: enum {
    INACTIVE;
    IDLE;
    SEND_INPUT;
    SEND_INPUT_FAILURE;
    RECEIVE_OUTPUT;
    RECEIVE_OUTPUT_FAILURE;
    OUTPUT_READY_AND_INCOMPLETE;
    OUTPUT_READY_AND_COMPLETE;
    SHUTTING_DOWN;
}

OSTextInfoHeader :: struct {

}

info_strings: BinPool(8, u8);

io_state := IOState.INACTIVE;

test_input_queue: [..]string;

input_thread: Thread;
input_buffer: []u8;
input: string;

output_thread: Thread;
output_buffer: []u8;
output: string;


WRITE_TO_IO_PROC_BODY :: #string HERE
    copy_str := in_str;
    copy_str.count = min(copy_str.count, %_buffer.count-%.count);
    if copy_str.count <= 0 {
        return false;
    }
    memcpy(%_buffer.data + %.count, copy_str.data, copy_str.count);
    %.count += copy_str.count;
    return true;
HERE

SHUTDOWN_PIPE_BODY :: #string HERE
    if % != null {
        CloseHandle(%);
        % = null;
    }
HERE