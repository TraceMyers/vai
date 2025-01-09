
Bit_Array_Group_Base_Mask :: (bit_group_count: int) -> u64  {
    return ifx bit_group_count == 64 then cast(u64)~0 else cast(u64)((1 << bit_group_count) - 1);
}

BitArray :: struct($BIT_GROUP_COUNT: int) {
    #run assert(Is_Power_Of_Two(BIT_GROUP_COUNT) && BIT_GROUP_COUNT <= 64);
    items: [..]u64;
    GROUP_COUNT :: BIT_GROUP_COUNT;
    GROUPS_PER_U64 :: 64 / BIT_GROUP_COUNT;
    GROUP_INDEXING_SHIFT :: #run Bit_Scan_Forward(GROUPS_PER_U64) - 1;
    GROUP_BASE_MASK :: #run Bit_Array_Group_Base_Mask(BIT_GROUP_COUNT);
}

Single_Bit_Mask :: inline (using array: *BitArray($COUNT), group: s64, in_group_index: s64) -> s64, u64 {
    assert(in_group_index >= 0 && in_group_index <= GROUP_COUNT);
    items_index := group >> GROUP_INDEXING_SHIFT;
    truncated_group_index := items_index << GROUP_INDEXING_SHIFT;
    group_index_in_u64 := group - truncated_group_index;
    bit_mask := cast(u64)(1 << (group_index_in_u64 * GROUP_COUNT + in_group_index));
    return items_index, bit_mask;
}

Group_Bit_Mask :: inline (using array: *BitArray($COUNT), group: s64) -> s64, u64 {
    assert(in_group_index >= 0 && in_group_index <= GROUP_COUNT);
    items_index := group >> GROUP_INDEXING_SHIFT;
    truncated_group_index := items_index << GROUP_INDEXING_SHIFT;
    group_index_in_u64 := group - truncated_group_index;
    return items_index, GROUP_BASE_MASK << (group_index_in_u64 * GROUP_COUNT);
}

Set_Bit :: inline (using array: *BitArray($COUNT), group: s64, in_group_index := 0) {
    index, mask := Single_Bit_Mask(array, group, in_group_index);
    items[index] |= mask;
}

Unset_Bit :: inline (using array: *BitArray($COUNT), group: s64, in_group_index := 0) {
    index, mask := Single_Bit_Mask(array, group, in_group_index);
    items[index] &= ~mask;
}

Is_Bit_Set :: inline (using array: *BitArray($COUNT), group: s64, in_group_index := 0) -> bool {
    index, mask := Single_Bit_Mask(array, group, in_group_index);
    return (items[index] & mask) != 0;
}

Set_Bit_Group :: inline (using array: *BitArray($COUNT), group: s64) {
    index, mask := Group_Bit_Mask(array, group);
    items[index] |= mask;
}

Unset_Bit_Group :: inline (using array: *BitArray($COUNT), group: s64) {
    index, mask := Group_Bit_Mask(array, group);
    items[index] &= ~mask;
}

Any_Bits_In_Group_Set :: inline (using array: *BitArray($COUNT), group: s64) -> bool {
    index, mask := Group_Bit_Mask(array, group);
    return (items[index] & mask) != 0;
}

All_Bits_In_Group_Set :: inline (using array: *BitArray($COUNT), group: s64) -> bool {
    index, mask := Group_Bit_Mask(array, group);
    return (items[index] & mask) == mask;
}

Set_Capacity :: (using array: *BitArray($COUNT), group_count: s64) {
    // might be one more than we need but it's fine
    items_count := (group_count >> GROUP_INDEXING_SHIFT) + 1;
    array_resize(*items, items_count);
}

Clear :: inline (using array: *BitArray($COUNT)) {
    if items.count > 0 {
        memset(items.data, 0, items.count * size_of(u64));
    }
}

Reset :: inline (using array: *BitArray($COUNT)) {
    array_reset(*items);
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

// needed to bring this in from Bit_Operations module, and make it *not* a macro to use it at compile time, otherwise no compile. not clear why.
Bit_Scan_Forward :: (input: $T) -> s32 {  // One plus the index of the first bit, when searching from LSB to MSB. A result of 0 means the input was 0.
    BITS :: size_of(T)*8;

    #if CPU == .X64 {
        #if BITS == 8 {  // There's no bsf for 8 bits. Sad.
            result: s16 = -1;
            #asm {
                movzxbw   temp:, input;
                bsf.16    result, temp;
            }
        } else {
            result: T = xx,no_check -1;
            #asm {
                bsf?T     result, input;
            }
        }

        return cast,trunc(s32)(result + 1);
    } else {
        // @Speed: Slow fallback for other CPUs.
        for i: 0..BITS-1 {
            if input & cast,no_check(T) (1 << i) return cast(s32) (i + 1);
        }
        
        return 0;
    }
}