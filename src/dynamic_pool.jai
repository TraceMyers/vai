
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// -------------------------------------------------------------------------------------------------------- dynamic pool
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// TODO: test expanding/shrinking more

PoolResizeBehavior :: enum {
    DEFAULT;
    ALLOW;
    DISALLOW;
}

DynamicPool :: struct($ItemType: Type) {
    items: [..]ItemType;
    in_use: [..]u8;
    mutex: Mutex;
    top: s32 = -1;
    shrink_to_min : s32 = 16;
    allow_grow_default := true;
    allow_shrink_default := true;
}

Initialize :: (using pool: *DynamicPool($T), reserve_count := 32) {
    BYTE_BITS :: 8;
    init(*mutex, "Dynamic Pool");
    reserve_byte_count := Div_Ceil(reserve_count, BYTE_BITS);
    reserve_item_count := reserve_byte_count * BYTE_BITS;
    array_resize(*pool.items, reserve_item_count);
    array_resize(*pool.in_use, reserve_byte_count);
}

Shutdown :: (using pool: *DynamicPool($T), Deinit_Item_Proc: (*T) = null) {
    if Deinit_Item_Proc then for i : 0..in_use.count-1 {
        in_use_chunk := in_use[i];
        if (in_use_chunk & U8_MAX) != 0 {
            for shift : 0..7 {
                shifted_bit := ub(1) << shift;
                if (in_use_chunk & shifted_bit) != 0 {
                    item_index := Byte_Index_To_Item_Index(i, shift);
                    Deinit_Item_Proc(*items[item_index]);
                }
            }
        }
    }
    array_reset(*items);
    array_reset(*in_use);
}

Is_Empty :: inline (using pool: *DynamicPool($T)) -> bool {
    return top == -1;
}

Is_Item_In_Use :: inline (using pool: *DynamicPool($T), i: s64) -> bool {
    byte, bit := Item_Index_To_Byte_Index(i);
    return (in_use[byte] & (ub(1) << bit)) != 0;
}

Request_Item :: (using pool: *DynamicPool($T), grow_behavior := PoolResizeBehavior.DEFAULT) -> s64 {
    lock(*mutex);
    defer unlock(*mutex);

    index := Find_Inactive(in_use, "in_use[byte] |= shifted_flags;");
    if index != -1 {
        if index > top then top = xx index;
        return index;
    }

    do_allow_grow := ifx grow_behavior == .DEFAULT 
        then allow_grow_default 
        else grow_behavior == .ALLOW;
    if !do_allow_grow then return -1;

    prev_item_count := items.count;
    top = xx prev_item_count;

    new_item_count := items.count + 8;
    array_resize(*items, new_item_count);
    array_add(*in_use, 0);
    in_use[in_use.count-1] |= 1;

    return prev_item_count;
}

Find_Item :: (using pool: *DynamicPool($T), user_data: $T2, Compare: (*T, T2) -> bool) -> s64 {
    lock(*mutex);
    defer unlock(*mutex);
    i := -1;
    while true {
        i = Find_Active(in_use, i + 1);
        if i == -1 then break;
        if Compare(*items[i], user_data) then return i;
    }
    return -1;
}

Get_Item :: (using pool: *DynamicPool($T), item: s64) -> *T {
    lock(*mutex);
    defer unlock(*mutex);
    assert(item >= 0 && item < items.count);
    assert(Is_Item_In_Use(pool, item));
    return *items[item];
}

Get_Item_Index :: inline (using pool: *DynamicPool($T), item: *T, $do_lock := true) -> s64 #expand {
    #if do_lock {
        lock(*mutex);
        defer unlock(*mutex);
    }
    i := (cast(s64) item - cast(s64) *items[0]) / size_of(T);
    assert(i >= 0 && i < items.count);
    return i;
}

Return_Item :: (using pool: *DynamicPool($T), i: s64, shrink_behavior := PoolResizeBehavior.DEFAULT) {
    lock(*mutex);
    defer unlock(*mutex);
    assert(i >= 0 && i < items.count);

    #if type_info(T).type == .STRUCT {
        items[i] = T.{};
    } else #if type_info(T).type == .INTEGER || type_info(T).type == .FLOAT {
        items[i] = 0;
    }

    byte_index, bit_index := Item_Index_To_Byte_Index(i);
    in_use[byte_index] &= ~(cast(u8) 1 << bit_index);

    if i == top {
        top = xx Find_Active_Backwards_From(in_use, top);
        do_allow_shrink := ifx shrink_behavior == .DEFAULT 
            then allow_shrink_default 
            else shrink_behavior == .ALLOW;

        if do_allow_shrink && items.count > shrink_to_min {
            top_count := top + 1;

            // div by 2 repeatedly until we find the threshold we're under
            test_threshold := items.count >> 1;
            while top_count < test_threshold {
                test_threshold >>= 1;
            }

            // only shrink by up to half the space we could shrink, to leave room for incoming adds
            test_threshold <<= 2;
            if test_threshold >= items.count then return;

            // make sure shrink_to_min is a multiple of 8, so that our 8 to 1 mapping of items to bytes works
            shrink_to_min = Multiple_Of_Ceil(shrink_to_min, 8);
            new_count := max(test_threshold, shrink_to_min);
            new_byte_count := Div_Ceil(new_count, 8);
            array_resize(*items, new_count);
            array_resize(*in_use, new_byte_count);
        }
    }
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

Byte_Index_To_Item_Index :: (byte: s64, bit: s64) -> s64 #expand {
    return byte * 8 + bit;
}

Item_Index_To_Byte_Index :: (i: s64) -> s32, s32 #expand {
    byte_index: s32 = xx (i >> 3);
    bit_index: s32 = xx (i - (byte_index << 3));
    return byte_index, bit_index;
}

Find_Active_Backwards_From :: (in_use: [..]u8, item_index: s64) -> s64 #expand {
    start_byte, start_bit := Item_Index_To_Byte_Index(item_index);
    for < byte : start_byte..0 {
        in_use_chunk := in_use[byte];
        if (in_use_chunk & U8_MAX) != 0 {
            for < bit_index : start_bit..0 {
                bit := ub(1) << bit_index;
                if (in_use_chunk & bit) != 0 {
                    item_index := Byte_Index_To_Item_Index(byte, bit_index);
                    return item_index;
                }
            }
        }
        start_bit = 7;
    }
    return -1;
}

Find_Active :: (in_use: [..]u8, from_index := 0, $INDEXING_INFO := PoolUsageIndexingInfo(1)) -> s64 #expand {
    start_byte, start_bit := Item_Index_To_Byte_Index(from_index);
    for byte : start_byte..in_use.count-1 {
        in_use_chunk := in_use[byte];
        if (in_use_chunk & U8_MAX) != 0 {
            for shift_count : 0..INDEXING_INFO.STEP_COUNT-1 {
                shift := (INDEXING_INFO.STEP_SIZE * shift_count);
                shifted_flags := INDEXING_INFO.FLAGS << shift;
                if (in_use_chunk & shifted_flags) != 0 && shifted_flags >= start_bit {
                    item_index := Byte_Index_To_Item_Index(byte, shift);
                    return item_index;
                }
            }
        }
        start_bit = 0;
    }
    return -1;
}

Find_Inactive :: (in_use: [..]u8, $c: string, from_index := 0, $INDEXING_INFO := PoolUsageIndexingInfo(1)) -> s64 #expand {
    start_byte, start_bit := Item_Index_To_Byte_Index(from_index);
    for byte : start_byte..in_use.count-1 {
        in_use_chunk := in_use[byte];
        if in_use_chunk != U8_MAX {
            for shift_count : 0..INDEXING_INFO.STEP_COUNT-1 {
                shift := (INDEXING_INFO.STEP_SIZE * shift_count);
                shifted_flags := INDEXING_INFO.FLAGS << shift;
                if (in_use_chunk & shifted_flags) == 0 && shifted_flags >= start_bit {
                    item_index := Byte_Index_To_Item_Index(byte, shift);
                    #insert c;
                    return item_index;
                }
            }
        }
        start_bit = 0;
    }
    return -1;
}

#scope_module // -------------------------------------------------------------------------------------------- { MODULE }

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ------------------------------------------------------------------------------------------------- contiguous bin pool
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

BinPoolAllocationType :: enum u8 {
    SMALL;
    MASSIVE;
}

BinID :: struct {
    index: s32 = -1;
    bin_count: u16;
    type: BinPoolAllocationType;
}

PoolTracker :: struct {
    in_use: [..]u8;
    top: s32 = -1;
    shrink_to_min: s32 = 96;
    allow_grow_default := true;
    allow_shrink_default := true;
}

BinPool :: struct($BASE_BIN_SIZE: s64, $ItemType: Type) {
    small_data: [..][BASE_BIN_SIZE]ItemType;
    massive_data: [..][..]ItemType;
    small_mark: s32;
    medium_mark: s32;
    large_mark: s32;
    very_large_mark: s32;
    massive_mark: s32;
    // mutex: Mutex;
    trackers: [2]PoolTracker;

    SMALL_BIN_COUNT             :: 1;
    MEDIUM_BIN_COUNT            :: 2;
    LARGE_BIN_COUNT             :: 4;
    VERY_LARGE_BIN_COUNT        :: 8;

    SMALL_BIN_SIZE              :: BASE_BIN_SIZE;
    MEDIUM_BIN_SIZE             :: BASE_BIN_SIZE * MEDIUM_BIN_COUNT;
    LARGE_BIN_SIZE              :: BASE_BIN_SIZE * LARGE_BIN_COUNT;
    VERY_LARGE_BIN_SIZE         :: BASE_BIN_SIZE * VERY_LARGE_BIN_COUNT;

    SHRINK_TO_SMALL_MAX         :: (SMALL_BIN_SIZE      * 3) / 4;
    SHRINK_TO_MEDIUM_MAX        :: (MEDIUM_BIN_SIZE     * 3) / 4;
    SHRINK_TO_LARGE_MAX         :: (LARGE_BIN_SIZE      * 3) / 4;
    SHRINK_TO_VERY_LARGE_MAX    :: (VERY_LARGE_BIN_SIZE * 3) / 4;

    #run assert((BASE_BIN_SIZE % 2) == 0 && SHRINK_TO_SMALL_MAX >= 6);
}

Assign_Bin_Pool_Allocator :: (using pool: *BinPool($SIZE, $T), allocator: Allocator) {
    small_data.allocator = allocator;
    massive_data.allocator = allocator;
    trackers[0].in_use.allocator = allocator; 
    trackers[1].in_use.allocator = allocator;
}

Bin_Pool_Initialize :: (using pool: *BinPool($SIZE, $T), small_reserve_count := 256, massive_reserve_count := 16) {
    BYTE_BITS :: 8;

    small_reserve_byte_count := Div_Ceil(small_reserve_count, BYTE_BITS);
    small_reserve_item_count := small_reserve_byte_count * BYTE_BITS;
    array_resize(*small_data, small_reserve_item_count);
    array_resize(*trackers[BinPoolAllocationType.SMALL].in_use, small_reserve_byte_count);

    massive_reserve_byte_count := Div_Ceil(massive_reserve_count, BYTE_BITS);
    massive_reserve_item_count := massive_reserve_byte_count * BYTE_BITS;
    array_resize(*massive_data, massive_reserve_item_count);
    array_resize(*trackers[BinPoolAllocationType.MASSIVE].in_use, massive_reserve_byte_count);
    Initialize_Massive_Allocators_From(pool, 0);
}

Bin_Pool_Shutdown :: (using pool: *BinPool($SIZE, $T)) {
    array_reset(*trackers[BinPoolAllocationType.SMALL].in_use);
    array_reset(*trackers[BinPoolAllocationType.MASSIVE].in_use);
    array_reset(*small_data);
    if (massive_data.allocator.proc != temp.proc || massive_data.allocator.data != temp.data) then for *massive_data {
        array_reset(it);
    }
    array_reset(*massive_data);
}

Bin_In_Use_Check_Data :: inline (using id: BinID) -> u32, u8 {
    #if DEBUG_POOLS then assert(bin_count <= 8);
    byte, bit := Item_Index_To_Byte_Index(id.index);
    flags := (ub(0xff) >> (ub(8) - bin_count)) << bit;
    return xx byte, flags;
}

Is_Item_In_Use :: inline (using pool: *BinPool($SIZE, $T), id: BinID) -> bool {
    tracker := *trackers[id.type];
    byte, flags := Bin_In_Use_Check_Data(id);
    #if DEBUG_POOLS {
        val := tracker.in_use[byte] & flags;
        is_zero := val == 0;
        is_exact_match := val == flags;
        assert(is_zero || is_exact_match);
        return is_exact_match;
    } else {
        return (tracker.in_use[byte] & flags) != 0;
    }
}

Request_Bin :: (using pool: *BinPool($SIZE, $T), min_size: s64, grow_behavior := PoolResizeBehavior.DEFAULT) -> BinID {
    if min_size <= 0 then return .{};

    id: BinID = ---;
    id.type = .SMALL;
    tracker: *PoolTracker = ---;
    base_alloc_flags: u8;
    mark: *s32;

    Try_Alloc :: (t: s32, $BIN_COUNT: u8, use_mark: *s32) #expand {
        `id.index = xx Find_Inactive(trackers[t].in_use, "in_use[byte] |= shifted_flags;", use_mark.*, PoolUsageIndexingInfo(BIN_COUNT));
        `id.bin_count = BIN_COUNT;
        `tracker = *trackers[t];
        base_alloc_flags = PoolUsageIndexingInfo(BIN_COUNT).FLAGS;
        `mark = *use_mark.*;
    }

    if min_size <= SMALL_BIN_SIZE {
        Try_Alloc(0, 1, *small_mark);
    } else if min_size <= MEDIUM_BIN_SIZE {
        Try_Alloc(0, 2, *medium_mark);
    } else if min_size <= LARGE_BIN_SIZE {
        Try_Alloc(0, 4, *large_mark);
    } else if min_size <= VERY_LARGE_BIN_SIZE {
        Try_Alloc(0, 8, *very_large_mark);
    } else {
        Try_Alloc(1, 1, *massive_mark);
        id.type = .MASSIVE;
    }

    if id.index != -1 {
        mark.* = id.index;
        if id.index > tracker.top then tracker.top = id.index;
        if id.type == .MASSIVE then array_resize(*massive_data[id.index], min_size);
        return id;
    }

    do_allow_grow := ifx grow_behavior == .DEFAULT 
        then tracker.allow_grow_default 
        else grow_behavior == .ALLOW;
    if !do_allow_grow then return .{index=-1};

    prev_item_count: s64 = ---;
    if id.type == .MASSIVE {
        prev_item_count = massive_data.count;
        new_item_count := massive_data.count + 8;
        assert(new_item_count <= S32_MAX);
        array_resize(*massive_data, new_item_count);
        Initialize_Massive_Allocators_From(pool, prev_item_count);
        array_resize(*massive_data[prev_item_count], min_size);
    } else {
        prev_item_count = small_data.count;
        new_item_count := small_data.count + 8;
        assert(new_item_count <= S32_MAX);
        array_resize(*small_data, new_item_count);
    }

    id.index = xx prev_item_count;
    mark.* = id.index;
    tracker.top = xx prev_item_count;
    array_add(*tracker.in_use, 0);
    tracker.in_use[tracker.in_use.count-1] |= base_alloc_flags;

    return id;
}

Release_Bin :: (using pool: *BinPool($SIZE, $T), id: *BinID, shrink_behavior := PoolResizeBehavior.DEFAULT) {
    // todo: shrink
    #if DEBUG_POOLS {
        assert(Is_Item_In_Use(pool, id.*));
    }

    byte, flags := Bin_In_Use_Check_Data(id.*);
    #if DEBUG_POOLS {
        assert(byte < trackers[id.type].in_use.count);
    }
    trackers[id.type].in_use[byte] &= ~flags;

    if id.type == .SMALL {
        #if DEBUG_POOLS {
            assert(id.index + id.bin_count <= small_data.count);
        }
        memset(small_data.data + id.index, 0, id.bin_count * SMALL_BIN_SIZE);

        Move_Mark_Back :: (mark: *s32) #expand { if `id.index < mark.* then mark.* = id.index; }
        if id.bin_count == {
        case SMALL_BIN_COUNT;
            Move_Mark_Back(*small_mark);
        case MEDIUM_BIN_COUNT;
            Move_Mark_Back(*medium_mark);
        case LARGE_BIN_COUNT;
            Move_Mark_Back(*large_mark);
        case VERY_LARGE_BIN_COUNT;
            Move_Mark_Back(*very_large_mark);
        }
    } else {
        #if DEBUG_POOLS {
            assert(id.index < massive_data.count);
        }
        array_reset(*massive_data[id.index]);
        if id.index < massive_mark then massive_mark = id.index;
    }
    id.* = .{};
}

Get_Bin :: (using pool: *BinPool($SIZE, $T), id: BinID) -> []T {
    bin: []T;
    #if DEBUG_POOLS {
        assert(Is_Item_In_Use(pool, id));
    }
    if id.type == .SMALL {
        #if DEBUG_POOLS {
            assert(id.bin_count <= 8 && id.bin_count >= 1 && Is_Power_Of_Two(id.bin_count));
            assert(id.index >= 0 && id.index < small_data.count);
        }
        bin.data = xx (small_data.data + id.index);
        bin.count = id.bin_count * SMALL_BIN_SIZE;
    } else {
        #if DEBUG_POOLS {
            assert(id.index >= 0 && id.index < massive_data.count);
        }
        bin.data = massive_data[id.index].data;
        bin.count = massive_data[id.index].count;
    }
    return bin;
}

// TODO: failure behavior?
Set_Bin_Data :: (using pool: *BinPool($SIZE, $T), id: *BinID, new_data: []T, shrink_behavior := PoolResizeBehavior.DEFAULT, grow_behavior := PoolResizeBehavior.DEFAULT) {
    bin := Get_Bin(pool, id.*);
    if bin.count < new_data.count {
        Release_Bin(pool, id, shrink_behavior);
        id.* = Request_Bin(pool, new_data.count, grow_behavior);
        assert(id.index != -1);
        bin = Get_Bin(pool, id.*);
    }
    memcpy(bin.data, new_data.data, new_data.count * size_of(T));
}

// TODO: shrink
Resize_Bin :: (using pool: *BinPool($SIZE, $T), id: *BinID, new_count: s64) {
    bin := Get_Bin(pool, id.*);
    if bin.count < new_count {
        old_size := bin.count * size_of(T);
        old_data := xx talloc(old_size);
        memcpy(*old_data, bin.data, old_size);
        Release_Bin(pool, id, .DEFAULT);
        id.* = Request_Bin(pool, new_count, .DEFAULT);
        assert(id.index != -1);
        bin = Get_Bin(pool, id.*);
        memcpy(*bin.data, old_data, old_size);
    }
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

PoolUsageIndexingInfo :: struct($BIN_COUNT: u8) {
    #if BIN_COUNT == 1 {
        FLAGS: u8: 0x01;
        STEP_SIZE: u8 : 1;
        STEP_COUNT: u8 : 8;
    } else #if BIN_COUNT == 2 {
        FLAGS: u8: 0x03;
        STEP_SIZE: u8 : 2;
        STEP_COUNT: u8 : 4;
    } else #if BIN_COUNT == 4 {
        FLAGS: u8: 0x0f;
        STEP_SIZE: u8 : 4;
        STEP_COUNT: u8 : 2;
    } else #if BIN_COUNT == 8 {
        FLAGS: u8: 0xff;
        STEP_SIZE: u8 : 8;
        STEP_COUNT: u8 : 1;
    } else {
        #run assert(false);
    }
}

Initialize_Massive_Allocators_From :: (using pool: *BinPool($SIZE, $T), start_index: s64) {
    for i : start_index..massive_data.count - 1 {
        massive_data[i].allocator = massive_data.allocator;
    }
}