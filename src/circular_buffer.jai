
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
        count += 1;
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
        count += 1;
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
