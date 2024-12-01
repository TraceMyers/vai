


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