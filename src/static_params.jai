
DEBUG_ECHO_ACTIONS      :: false;
DEBUG_ECHO_TEXT_INPUT   :: false;
DEBUG_ECHO_COMMANDS     :: false;
DEBUG_ENCODING          :: false;
DEBUG_RENDER_PARSE      :: false;
DEBUG_POOLS             :: false;
DEBUG_TEXT_BUFFERS      :: true;
DEBUG_GRAPHICS          :: false;

MSAA :: 4;

// try force select using gpu as graphics device. less stuttering in my experience as a laptop user.
#program_export "NvOptimusEnablement"
NvOptimusEnablement: u32 = 1;
#program_export "AmdPowerXpressRequestHighPerformance"
AmdPowerXpressRequestHighPerformance: s32 = 1;