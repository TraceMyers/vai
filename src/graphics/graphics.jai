
Prepare_Window :: (wanted_msaa: s32) -> chosen_mssa: s32 {
    Update_Window();
    return wanted_msaa;
}

Update_Window :: () {
    prev_width, prev_height := window.width, window.height;
    window.width, window.height = Get_Render_Dimensions(*window);
    if window.width != prev_width || window.height != prev_height {
        // Resize_Render_Target(window);
        Set_Projection(window.width, window.height);
    }
}

// TODO: simple axis-aligned 2d projection means don't need matrix
Set_Projection :: (render_target_width: s32, render_target_height: s32) {
    
}

#if OS == .WINDOWS {
    #load "win32_graphics.jai";
}