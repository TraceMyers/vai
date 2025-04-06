
AllocConsole :: () -> bool #foreign kernel32;
SetConsoleScreenBufferSize :: (hConsoleInput: HANDLE, dwSize: COORD) -> BOOL #foreign kernel32;
CreatePseudoConsole :: (size: COORD, hInput: HANDLE, hOutput: HANDLE, dwFlags: DWORD, phPC: *HANDLE) -> HRESULT #foreign kernel32;
ClosePseudoConsole :: (handle: HANDLE) #foreign kernel32;
InitializeProcThreadAttributeList :: (attribute_list: *void, attribute_count: DWORD, flags: DWORD, size: *size_t) -> BOOL #foreign kernel32;
UpdateProcThreadAttribute :: (attribute_list: *void, flags: DWORD, attribute: *DWORD, lpValue: *void, cbSize: size_t, lpPreviousValue: *void, lpReturnSize: *size_t) -> BOOL #foreign kernel32;
// ReadConsoleOutput :: (console: HANDLE, out_buffer: *CHAR_INFO, out_cols_rows: COORD, out_ul_col_row: COORD, read_region_rect: *SMALL_RECT) -> BOOL #foreign kernel32;
GetConsoleMode :: (console_handle: *void, lpMode: *s32) -> BOOL #foreign kernel32;
SetConsoleMode :: (console_handle: *void, dwMode: s32) -> BOOL #foreign kernel32;

STARTUPINFOEX :: struct {
    info: STARTUPINFOA;
    attribute_list: *void; // LPPROC_THREAD_ATTRIBUTE_LIST
}
CHAR_INFO :: struct {
    char: union {
        utf16: u16;
        ansii: u8;
    }
    attributes: s16;
}

PROC_THREAD_ATTRIBUTE_REPLACE_VALUE : u32 : 1;
PROC_THREAD_ATTRIBUTE_PARENT_PROCESS : u32 : 131072;
PROC_THREAD_ATTRIBUTE_HANDLE_LIST : u32 : 131074;
PROC_THREAD_ATTRIBUTE_GROUP_AFFINITY : u32 : 196611;
PROC_THREAD_ATTRIBUTE_PREFERRED_NODE : u32 : 131076;
PROC_THREAD_ATTRIBUTE_IDEAL_PROCESSOR : u32 : 196613;
PROC_THREAD_ATTRIBUTE_UMS_THREAD : u32 : 196614;
PROC_THREAD_ATTRIBUTE_MITIGATION_POLICY : u32 : 131079;
PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES : u32 : 131081;
PROC_THREAD_ATTRIBUTE_PROTECTION_LEVEL : u32 : 131083;
PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE : u32 : 131094;
PROC_THREAD_ATTRIBUTE_MACHINE_TYPE : u32 : 131097;
PROC_THREAD_ATTRIBUTE_ENABLE_OPTIONAL_XSTATE_FEATURES : u32 : 196635;
PROC_THREAD_ATTRIBUTE_WIN32K_FILTER : u32 : 131088;
PROC_THREAD_ATTRIBUTE_JOB_LIST : u32 : 131085;
PROC_THREAD_ATTRIBUTE_CHILD_PROCESS_POLICY : u32 : 131086;
PROC_THREAD_ATTRIBUTE_ALL_APPLICATION_PACKAGES_POLICY : u32 : 131087;
PROC_THREAD_ATTRIBUTE_DESKTOP_APP_POLICY : u32 : 131090;
PROC_THREAD_ATTRIBUTE_MITIGATION_AUDIT_POLICY : u32 : 131096;
PROC_THREAD_ATTRIBUTE_COMPONENT_FILTER : u32 : 131098;
PROC_THREAD_ATTRIBUTE_NUMBER : u32 : 65535;
PROC_THREAD_ATTRIBUTE_THREAD : u32 : 65536;
PROC_THREAD_ATTRIBUTE_INPUT : u32 : 131072;
PROC_THREAD_ATTRIBUTE_ADDITIVE : u32 : 262144;

// #insert #run Generate_Enumerated_Array_CT("EscapeSequence", "u8", "escape_sequences", "Escape_Sequence", u8,
//     .{"SINGLE_SHIFT_TWO",               #char "N"},
//     .{"SINGLE_SHIFT_THREE",             #char "O"},
//     .{"DEVICE_CONTROL_STRING",          #char "P"},
//     .{"CONTROL_SEQUENCE_INTRODUCER",    #char "["},
//     .{"STRING_TERMINATOR",              #char "\\"},
//     .{"OPERATING_SYSTEM_COMMAND",       #char "]"},
//     .{"START_OF_STRING",                #char "X"},
//     .{"PRIVACY_MESSAGE",                #char "^"},
//     .{"APPLICATION_CONTROL_COMMAND",    #char "_"}
// );

EscapeCode :: enum u8 {
    SINGLE_SHIFT_TWO               :: #char "N";
    SINGLE_SHIFT_THREE             :: #char "O";
    DEVICE_CONTROL_STRING          :: #char "P";
    CONTROL_SEQUENCE_INTRODUCER    :: #char "[";
    STRING_TERMINATOR              :: #char "\\";
    OPERATING_SYSTEM_COMMAND       :: #char "]";
    START_OF_STRING                :: #char "X";
    PRIVACY_MESSAGE                :: #char "^";
    APPLICATION_CONTROL_COMMAND    :: #char "_";
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

// HANDLE OpenFileById(
//   [in]           HANDLE                hVolumeHint,
//   [in]           LPFILE_ID_DESCRIPTOR  lpFileId,
//   [in]           DWORD                 dwDesiredAccess,
//   [in]           DWORD                 dwShareMode,
//   [in, optional] LPSECURITY_ATTRIBUTES lpSecurityAttributes,
//   [in]           DWORD                 dwFlagsAndAttributes
// );

// typedef struct FILE_ID_DESCRIPTOR {
//   DWORD        dwSize;
//   FILE_ID_TYPE Type;
//   union {
//     LARGE_INTEGER FileId;
//     GUID          ObjectId;
//     FILE_ID_128   ExtendedFileId;
//   } DUMMYUNIONNAME;
// } FILE_ID_DESCRIPTOR, *LPFILE_ID_DESCRIPTOR;