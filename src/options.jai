
Options :: struct {

    Initialize :: () -> success: bool  {
        for *option_mappings {
            it.extension.value = it.extension.default_value;
        }
        return true;
    }

    Shutdown :: () {

    }
}

Bool_Option_Value :: (option: Option) -> bool {
    using option_mappings[option].extension;
    assert(type == .BOOL);
    return _bool;
}

Integer_Option_Value :: (option: Option) -> s32 {
    using option_mappings[option].extension;
    assert(type == .INTEGER);
    return _integer;
}

Set_Option :: (option: Option, in_value: bool) {
    using option_mappings[option].extension;
    assert(type == .BOOL);
    Log("setting % to %", option, in_value);
    _bool = in_value;
}

Set_Option :: (option: Option, in_value: s32) {
    using option_mappings[option].extension;
    assert(type == .INTEGER);

    _integer = in_value;

    if option == {
    case .FONT_SIZE;
        Reinitialize_Font();
    }
}

Set_Option :: (option: Option, in_value: string) {
    using option_mappings[option].extension;
    assert(type == .STRING);

    if _string.data != default_value._string.data {
        free(_string);
    }
    _string = in_value;
}

OptionValue :: union {
    _bool: bool;
    _integer: s32;
    _string: string;
}

OptionSetting :: struct {
    using value: OptionValue;
    default_value: OptionValue;
    type: enum u8 {
        BOOL;
        INTEGER;
        STRING;
    }
}