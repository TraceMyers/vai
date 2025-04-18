
ub  :: inline (val: s64) -> u8  #expand { return cast(u8)val;  }
uw  :: inline (val: s64) -> u16 #expand { return cast(u16)val; }
udw :: inline (val: s64) -> u32 #expand { return cast(u32)val; }
uqw :: inline (val: s64) -> u64 #expand { return cast(u64)val; }
sb  :: inline (val: s64) -> s8  #expand { return cast(s8)val;  }
sw  :: inline (val: s64) -> s16 #expand { return cast(s16)val; }
sdw :: inline (val: s64) -> s32 #expand { return cast(s32)val; }
sqw :: inline (val: s64) -> s64 #expand { return cast(s64)val; }
sqw :: inline (val: u64) -> s64 #expand { return cast(s64)val; }

pub  :: inline (val: s64) -> *u8  #expand { return cast(*u8)val;  }
puw  :: inline (val: s64) -> *u16 #expand { return cast(*u16)val; }
pudw :: inline (val: s64) -> *u32 #expand { return cast(*u32)val; }
puqw :: inline (val: s64) -> *u64 #expand { return cast(*u64)val; }
psb  :: inline (val: s64) -> *s8  #expand { return cast(*s8)val;  }
psw  :: inline (val: s64) -> *s16 #expand { return cast(*s16)val; }
psdw :: inline (val: s64) -> *s32 #expand { return cast(*s32)val; }
psqw :: inline (val: s64) -> *s64 #expand { return cast(*s64)val; }


tub  :: inline (val: s64) -> u8  #expand { return cast,trunc(u8)val;  }
tuw  :: inline (val: s64) -> u16 #expand { return cast,trunc(u16)val; }
tudw :: inline (val: s64) -> u32 #expand { return cast,trunc(u32)val; }
tuqw :: inline (val: s64) -> u64 #expand { return cast,trunc(u64)val; }
tsb  :: inline (val: s64) -> s8  #expand { return cast,trunc(s8)val;  }
tsw  :: inline (val: s64) -> s16 #expand { return cast,trunc(s16)val; }
tsdw :: inline (val: s64) -> s32 #expand { return cast,trunc(s32)val; }
tsqw :: inline (val: s64) -> s64 #expand { return cast,trunc(s64)val; }

uqw :: inline (val: *void) -> u64 #expand { return cast,force(u64)val; }

pub :: inline (val: *void) -> *u8 #expand { return cast,force(*u8)val;  }
// sqw :: inline (val: *void) -> s64 #expand { return cast,force(s64)val; }

Is_Number_Type :: inline (InType: Type) -> bool {
    return (cast(*Type_Info)InType).type == .INTEGER || (cast(*Type_Info)InType).type == .FLOAT;
}

Min_Value :: inline (number: $NumberType) -> NumberType #expand {
    return Min_Value(type_of(number));
}

Max_Value :: inline (number: $NumberType) -> NumberType #expand {
    return Max_Value(type_of(number));
}

Min_Value :: inline ($NumberType: Type) -> NumberType
#modify {
    return Is_Number_Type(NumberType);
} {
    #if NumberType == {
    case u8;
        return 0;
    case u16; 
        return 0;
    case u32; 
        return 0;
    case u64;
        return 0;
    case s8;
        return S8_MIN;
    case s16;
        return S16_MIN;
    case s32;
        return S32_MIN;
    case s64;
        return S64_MIN;
    case float32;
        return FLOAT32_MIN;
    case float64;
        return FLOAT64_MIN;
    case;
        return 0;
    }
}

Max_Value :: inline ($NumberType: Type) -> NumberType
#modify {
    return Is_Number_Type(NumberType);
} {
    #if NumberType == {
    case u8;
        return U8_MAX;
    case u16;
        return U16_MAX;
    case u32;
        return U32_MAX;
    case u64;
        return U64_MAX;
    case s8;
        return S8_MAX;
    case s16;
        return S16_MAX;
    case s32;
        return S32_MAX;
    case s64;
        return S64_MAX;
    case float32;
        return FLOAT32_MAX;
    case float64;
        return FLOAT64_MAX;
    case;
        return 0;
    }
}

Round :: inline (a: float64, $IntType := s32) -> IntType 
#modify {
    return (cast(*Type_Info)IntType).type == .INTEGER;
} {
    // edge cases are everybody's favorite. max values cause issues.
    #if IntType == s64 {
        if (a >= 9_223_372_036_854_775_807.0) {
            return 9_223_372_036_854_775_807;
        }
    }
    #if IntType == u64 {
        if (a >= 18_446_744_073_709_551_615.0) {
            return 18_446_744_073_709_551_615;
        }
    }
    rounded_toward_zero := cast(IntType)a;
    diff := a - cast(float64)rounded_toward_zero;
    if diff > 0.5 {
        return rounded_toward_zero + 1;
    } else if diff < -0.5 {
        return rounded_toward_zero - 1;
    } else {
        return rounded_toward_zero;
    }
}

CeilFunction :: enum {
    TOWARD_LARGE_NUMBERS; // rounds negative numbers toward negative infinity, and vice-versa
    TOWARD_POSITIVE_INFINITY; // all numbers get rounded up, away from negative infinity
}

Ceil :: inline (a: $FloatType, $ToType := s32, $FUNC := CeilFunction.TOWARD_POSITIVE_INFINITY) -> ToType {
    t_val := cast(ToType)a;
    unit_part := a - cast(FloatType)t_val;

    #if FUNC == .TOWARD_LARGE_NUMBERS {
        if abs(unit_part) < 0.0001 {
            return t_val;
        } else if unit_part > 0 {
            if t_val == Max_Value(ToType) {
                return t_val;
            } else {
                return t_val + 1;
            }
        } else {
            if t_val == Min_Value(ToType) {
                return t_val;
            } else {
                return t_val - 1;
            }
        }
    } else { // toward positive infinity
        if abs(unit_part) < 0.0001 || t_val == Max_Value(ToType) {
            return t_val;
        } else {
            return t_val + 1;
        }
    }
}

FloorFunction :: enum {
    TOWARD_ZERO;
    TOWARD_NEGATIVE_INFINITY;
}

Floor :: inline (a: $FloatType, $ToType := s32, $FUNC := FloorFunction.TOWARD_ZERO) -> ToType {
    casted := cast(ToType) a;
    #if FUNC == .TOWARD_ZERO {
        return casted;
    } else {
        if a < 0.0 {
            if casted == Min_Value(ToType) {
                return casted;
            } else {
                return casted - 1;
            }
        }
    }
}

Clamp_Cast :: inline (number: $InType, $OutType: Type, $NORMALIZED_FLOAT := false, $ROUND_TO_INT := true) -> OutType
#modify {
    return Is_Number_Type(InType) && Is_Number_Type(OutType);
} {
    MIN_IN :: #run Min_Value(InType);
    MAX_IN :: #run Max_Value(InType);
    IN_DIFF :: MAX_IN - MIN_IN;
    MIN_OUT :: #run Min_Value(OutType);
    MAX_OUT :: #run Max_Value(OutType);
    OUT_DIFF :: MAX_OUT - MIN_OUT;
    IN_IS_FLOAT :: #run type_info(InType).type == .FLOAT;
    OUT_IS_FLOAT :: #run type_info(OutType).type == .FLOAT;
    FLOAT_TO_INT :: IN_IS_FLOAT && !OUT_IS_FLOAT;
    INT_TO_FLOAT :: !IN_IS_FLOAT && OUT_IS_FLOAT;

    #if NORMALIZED_FLOAT {
        #if FLOAT_TO_INT {
            #if ROUND_TO_INT {
                return Round(cast(float64)MIN_OUT + (cast(float64)MAX_OUT - cast(float64)MIN_OUT) * xx number, OutType);
            } else {
                return xx (cast(float64)MIN_OUT + (cast(float64)MAX_OUT - cast(float64)MIN_OUT) * xx number);
            }
        } else #if INT_TO_FLOAT {
            return clamp((cast(float64)number - cast(float64)MIN_IN) / cast(float64)IN_DIFF, 0.0, 1.0);
        } else {
            assert(false);
        }
    } else {
        if number < MIN_OUT {
            return MIN_OUT;
        } else if number > MAX_OUT {
            return MAX_OUT;
        } else {
            #if FLOAT_TO_INT && ROUND_TO_INT {
                return Round(number, OutType);
            } 
            return xx number;
        }
    }
    return xx 0;
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

#import "Basic";
#import "Math";