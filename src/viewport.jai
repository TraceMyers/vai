
// for use with Scoped_Construct
Viewports :: struct {

    Initialize :: () -> bool {
        array_reserve(*viewport_stack, 64);
        array_reserve(*viewport_rects, 64);
        array_add(*viewport_rects, Window_Viewport_Rect());
        return true;
    }

    Shutdown :: () {
        array_free(viewport_stack);
        array_free(viewport_rects);
    }

}

Window_Viewport_Rect :: inline () -> ViewportRect {
    return .{.{0, 0}, .{window.width, window.height}};
}

Clear_Viewports :: () {
    array_reset_keeping_memory(*viewport_stack);
    array_reset_keeping_memory(*viewport_rects);
    array_add(*viewport_rects, Window_Viewport_Rect());
}

Viewport_Push :: (v: Viewport, do_cache := false) -> s64 {
    // TODO: better validation
    if v.type == .PROPORTION {
        for o : v.offsets {
            assert(o >= 0.0);
        }
    } else if v.type == .PIXELS {
        for o : v.offsets {
            assert(o >= 0);
        }
    }

    if !v.inverted {
        num_nonzero := 0;
        for o : v.offsets {
            if o != 0 {
                num_nonzero += 1;
            }
        }
        // assert(num_nonzero == 1);
    }

    array_add(*viewport_stack, v);

    id := -1;
    if do_cache {
        id = Cache_Viewport_Rect();
    }
    return id;
}

Apply_Viewport_To_Rect :: inline (rect: *ViewportRect, v: *Viewport) {
    Shave_Rect_Dimension(*rect.x, *rect.dimensions.x, v, .LEFT);
    Shave_Rect_Dimension(*rect.y, *rect.dimensions.y, v, .TOP);
}

Viewport_Pop :: inline () {
    index := viewport_stack.count-1;
    array_unordered_remove_by_index(*viewport_stack, index);
}

Cache_Viewport_Rect :: () -> s64 {
    rect := Window_Viewport_Rect();
    for viewport_stack {
        Apply_Viewport_To_Rect(*rect, *it);
    }
    array_add(*viewport_rects, rect);
    return viewport_rects.count - 1;
}

Last_Cached_Viewport_Rect :: inline () -> ViewportRect {
    if viewport_rects.count == 0 
        then return Window_Viewport_Rect();
        else return viewport_rects[viewport_rects.count-1];
}

Viewport_Rect_Points :: inline (r: *ViewportRect, $T1: Type) -> $T2, T2
#modify {
    if T1 == s32 {
        T2 = IntVector2;
        return true;
    } else if T2 == float32 {
        T2 = Vector2;
        return true;
    } else return false;
} {
    return .{xx r.x, xx r.y}, .{xx (r.x + r.dimensions.x), xx (r.y + r.dimensions.y)};
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

Side2D :: enum u8 {
    LEFT; TOP; RIGHT; BOTTOM;
}

Opposite :: (side: Side2D) -> Side2D {
    if #complete side == {
    case .LEFT; 
        return .RIGHT;
    case .TOP; 
        return .BOTTOM;
    case .RIGHT; 
        return .LEFT;
    case .BOTTOM;
        return .TOP;
    }
}

ViewportOffsetType :: enum u8 {
    PROPORTION; PIXELS;
}

Viewport :: struct {
    left: float;
    top: float;
    right: float;
    bottom: float;
    type: ViewportOffsetType;
    inverted: bool;

#place left;
    left_pixels: s32;
    top_pixels: s32;
    right_pixels: s32;
    bottom_pixels: s32;
#place left;
    offsets: [4]float32;
#place left;
    pixel_offsets: [4]s32;
}

ViewportRect :: struct {
    using upper_left: IntVector2;
    dimensions: IntVector2;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

viewport_rects: [..]ViewportRect;

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

Shave_Rect_Dimension :: (rect_pivot: *s32, rect_dimension: *s32, v: *Viewport, min_side: Side2D) {
    side_a : s32 = xx min_side;
    side_b := side_a + 2;
    a_shave, b_shave: s32;
    if v.type == .PROPORTION {
        dimension_float: float = xx rect_dimension.*;
        a_shave = Ceil(cast(float32) rect_dimension.* * v.offsets[side_a]);
        b_shave = Ceil(cast(float32) rect_dimension.* * v.offsets[side_b]);
    } else {
        a_shave = v.pixel_offsets[side_a];
        b_shave = v.pixel_offsets[side_b];
    }
    if a_shave == 0 && b_shave == 0 then return;

    overshave := a_shave + b_shave - <<rect_dimension;
    if overshave > 0 {
        b_delta := min(overshave, b_shave);
        b_shave = max(b_shave - b_delta, 0);
        overshave -= b_delta;
        a_shave = max(a_shave - overshave, 0);
    }

    if !v.inverted {
        if a_shave > 0 {
            rect_dimension.* = a_shave;
        } else {
            shave_amt := (rect_dimension.* - b_shave);
            rect_dimension.* -= shave_amt;
            rect_pivot.* += shave_amt;
        }
    } else {
        rect_pivot.* += a_shave;
        rect_dimension.* -= a_shave + b_shave;
    }
}

viewport_stack: [..]Viewport;