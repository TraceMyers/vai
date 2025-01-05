
CircularBuffer :: struct($T: Type) {
    items: [..]T;
    begin: s64 = -1;
    end: s64 = -1;
    count: s64;
    allow_overwrite: bool;
}

Circular_Buffer_Initialize :: (buffer: *CircularBuffer($T), item_count: s64, allow_overwrite: bool) {
    array_reset_keeping_memory(*buffer.items);
    array_resize(*buffer.items, item_count);
    buffer.begin = -1;
    buffer.end = -1;
    buffer.count = 0;
    buffer.allow_overwrite = allow_overwrite;
}

Circular_Buffer_Reset :: (using buffer: *CircularBuffer($T)) {
    array_reset(*items);
    buffer.* = .{};
}

Push_Front :: (using buffer: *CircularBuffer($T), item: T) {
    if count == 0 {
        begin = 0;
        end = 0;
        count = 1;
    } else {
        begin = Decrement_Wrap(begin, 0, items.count-1);
        if count == items.count {
            assert(allow_overwrite);
            end = Decrement_Wrap(end, 0, items.count-1);
        } else {
            count += 1;
        }
    }
    items[begin] = item;
}

Push_Back :: (using buffer: *CircularBuffer($T), item: T) {
    if count == 0 {
        begin = 0;
        end = 0;
        count = 1;
    } else {
        end = Increment_Wrap(end, 0, items.count-1);
        if count == items.count {
            assert(allow_overwrite);
            begin = Increment_Wrap(begin, 0, items.count-1);
        } else {
            count += 1;
        }
    }
    items[end] = item;
}

Pop_Back :: inline (using buffer: *CircularBuffer($T)) -> T {
    assert(count > 0);
    count -= 1;
    item := items[end];
    end = Decrement_Wrap(end, 0, items.count-1);
    return item;
}

Pop_Front :: inline (using buffer: *CircularBuffer($T)) -> T {
    assert(count > 0);
    count -= 1;
    item := items[end];
    begin = Increment_Wrap(begin, 0, items.count-1);
    return item;
}

Peek_Back :: inline (using buffer: *CircularBuffer($T)) -> *T {
    assert(count > 0);
    return *items[end];
}

Seek_Back :: inline (using buffer: *CircularBuffer($T), item_in_array: *T) -> *T {
    current_index := Element_Index(item_in_array, items);
    if current_index == begin {
        return null;
    }
    prev_index := Decrement_Wrap(current_index, 0, items.count-1);
    return *items[prev_index];
}

Peek_Front :: inline (using buffer: *CircularBuffer($T)) -> *T {
    assert(count > 0);
    return *items[begin];
}

Is_Full :: inline (using buffer: *CircularBuffer($T)) -> bool {
    return buffer.count == buffer.items.count;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

OpposingCircularBuffer :: struct($T: Type) {
    items: [..]T;
    begin: s64;
    middle: s64;
    end: s64;
    count: s64;
    item_cleanup_proc: (*T);
    allow_overwrite: bool;
}

Opposing_Circular_Buffer_Initialize :: (buffer: *OpposingCircularBuffer($T), item_count: s64, cleanup_proc: (*T), allow_overwrite: bool) {
    array_resize(*buffer.items, item_count);
    buffer.item_cleanup_proc = cleanup_proc;
    buffer.allow_overwrite = allow_overwrite;
}

Opposing_Circular_Buffer_Reset :: (using buffer: *OpposingCircularBuffer($T)) {
    if count > 0 && item_cleanup_proc != null {
        item := Peek_Back(buffer);
        for 0..count-1 {
            item_cleanup_proc(item);
            item = Seek_Back(buffer, item);
        }
    }
    array_reset(*items);
    buffer.* = .{};
}

Push_Middle :: (using buffer: *OpposingCircularBuffer($T), item: T) {
    if count == 0 {
        count = 1;
    } else {
        old_middle := middle;
        middle = Increment_Wrap(middle, 0, items.count-1);
        if count == items.count {
            assert(allow_overwrite);
            begin = Increment_Wrap(begin, 0, items.count-1);
            if item_cleanup_proc != null {
                item_cleanup_proc(*items[middle]);
            }
        } else if end != old_middle {
            assert(allow_overwrite);
            if item_cleanup_proc != null {
                item_cleanup_proc(*items[middle]);
            }
            count += 1;
        } else {
            count += 1;
        }
        end = middle;
    }
    items[middle] = item;
}

Reset_Back :: inline (using buffer: *OpposingCircularBuffer($T)) {
    item := *items[end];
    while end != middle {
        if item_cleanup_proc {
            item_cleanup_proc(item);
        }
        end = Decrement_Wrap(end, 0, items.count-1);
        item = *items[end];
    }
    if item_cleanup_proc {
        item_cleanup_proc(item);
    }
}

Pop_Middle :: inline (using buffer: *OpposingCircularBuffer($T)) -> T {
    assert(count > 0);
    count -= 1;
    item := items[middle];
    middle = Decrement_Wrap(middle, 0, items.count-1);
    return item;
}


Push_Middle :: inline (using buffer: *OpposingCircularBuffer($T)) {
    if middle == end || count == items.count || Totally_Empty(buffer) {
        Push_Middle(buffer, .{});
    } else {
        middle = Increment_Wrap(middle, 0, items.count-1);
        count += 1;
    }
}

Peek_Back :: inline (using buffer: *OpposingCircularBuffer($T)) -> *T {
    assert(!Totally_Empty(buffer));
    return *items[end];
}

Peek_Middle :: inline (using buffer: *OpposingCircularBuffer($T)) -> *T {
    assert(!Totally_Empty(buffer));
    return *items[middle];
}

Peek_Front :: inline (using buffer: *OpposingCircularBuffer($T)) -> *T {
    assert(!Totally_Empty(buffer));
    return *items[begin];
}

Seek_Back :: inline (using buffer: *OpposingCircularBuffer($T), item_in_array: *T) -> *T {
    current_index := Element_Index(item_in_array, items);
    if current_index == begin {
        return null;
    }
    prev_index := Decrement_Wrap(current_index, 0, items.count-1);
    return *items[prev_index];
}

Is_Full :: inline (using buffer: *OpposingCircularBuffer($T)) -> bool {
    return count == items.count;
}

Totally_Empty :: inline (using buffer: *OpposingCircularBuffer($T)) -> bool {
    return begin == end && count == 0;
}