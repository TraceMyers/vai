
DEBUG_ECHO_ACTIONS      :: true;
DEBUG_ECHO_TEXT_INPUT   :: true;
DEBUG_ECHO_COMMANDS     :: false;
DEBUG_ENCODING          :: false;
DEBUG_RENDER_PARSE      :: false;
DEBUG_POOLS             :: false;
DEBUG_TEXT_BUFFERS      :: false;
DEBUG_GRAPHICS          :: false;
DEBUG_MEMORY            :: false;
ALWAYS_FULL_UPDATE      :: true;
SERIALIZE_DEBUG         :: false;
DEBUG_BIN_POOL          :: false;
DEBUG_UNDO_REDO         :: false;
DEBUG_TEXT_BUFFER       :: false;

MSAA :: 4;

// try force select using gpu as graphics device. less stuttering in my experience as a laptop user.
#program_export "NvOptimusEnablement"
NvOptimusEnablement: u32 = 1;
#program_export "AmdPowerXpressRequestHighPerformance"
AmdPowerXpressRequestHighPerformance: s32 = 1;