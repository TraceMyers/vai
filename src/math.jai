
Rect :: struct($NumberType: Type) {
    left, top, right, bottom: NumberType;
}

SRect :: Rect(s32);
URect :: Rect(u32);
FRect :: Rect(float32);

Respace :: (v: float, in_range: Vector2, out_range: Vector2) -> float {
    norm_val: float = ---;
    if in_range.y > in_range.x {
        in_range_width := in_range.y - in_range.x;
        norm_val = (clamp(v, in_range.x, in_range.y) - in_range.x) / in_range_width;
    } else {
        in_range_width := in_range.x - in_range.y;
        norm_val = 1.0 - (clamp(v, in_range.y, in_range.x) - in_range.y) / in_range_width;
    }
    out_range_width := out_range.y - out_range.x;
    return out_range.x + out_range_width * norm_val;
}

Is_Normalized :: (v: $VecType, tolerance := 0.0001) -> bool {
    return abs(length_squared(v) - 1.0) < tolerance;
}

IntVector2 :: struct {
    x: s32;
    y: s32;
}

As_Vector2 :: inline (v: IntVector2) -> Vector2 {
    return .{xx v.x, xx v.y};
}

To_IntVector2 :: inline (v: Vector2) -> IntVector2 {
    return .{xx v.x, xx v.y};
}

Div_Ceil :: inline (a: $IntType, b: IntType) -> IntType {
    return ((a - 1) / b) + 1;
}

Multiple_Of_Ceil :: inline (a: $IntType, b: IntType) -> IntType {
    return Div_Ceil(a, b) * b;
}

Multiple_Of_Floor :: inline (a: $IntType, b: IntType) -> IntType {
    return (a / b) * b;
}

Round_Away_From_Zero :: inline (a: $FloatType, $ToType := s32) -> ToType {
    t_val := cast(ToType)a;
    unit_part := a - cast(FloatType)t_val;
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
}

operator + :: inline (a: IntVector2, b: IntVector2) -> IntVector2 {
    return .{a.x + b.x, a.y + b.y};
}

operator - :: inline (a: IntVector2, b: IntVector2) -> IntVector2 {
    return .{a.x - b.x, a.y - b.y};
}

operator * :: inline (a: IntVector2, scalar: s32) -> IntVector2 #symmetric {
    return .{a.x * scalar, a.x * scalar};
}

operator == :: inline (a: IntVector2, b: IntVector2) -> bool {
    return (a.x == b.x) & (a.y == b.y);
}

Is_Power_Of_Two :: inline (value: s64) -> bool {
    return ((value >> 1) & value) == 0;
}

Add_Wrap :: inline (val: $T, amount: T, min: T, max: T) -> T {
    val += amount;
    if val > max {
        val = min;
    } else if val < min {
        val = max;
    }
    return val;
}

Increment_Wrap :: inline (val: $T, min: T, max: T) -> T {
    val += 1;
    if val > max {
        val = min;
    }
    return val;
}

Decrement_Wrap :: inline (val: $T, min: T, max: T) -> T {
    val -= 1;
    if val < min {
        val = max;
    }
    return val;
}