
Options :: struct {

    Initialize :: () -> success: bool  {
        return true;
    }

    Shutdown :: () {

    }
}
Is_Bool_Option_Set :: (option: Option) -> bool {
    using option_mappings[option].extension;
    assert(type == .BOOL);
    return _bool;
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