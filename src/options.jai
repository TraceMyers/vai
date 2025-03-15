
Options :: struct {

    Initialize :: () -> success: bool  {
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

OptionSetting :: struct {
    using value: union {
        _bool: bool;
        _integer: s32;
        _string: string;
    }
    type: enum {
        BOOL;
        INTEGER;
        STRING;
    }
}