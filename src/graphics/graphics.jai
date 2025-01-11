
// Prepare_Window :: (wanted_msaa: s32) -> chosen_mssa: s32 {
    // Update_Window_Dimensions();
    // Post_Resize_Window();
    // return wanted_msaa;
// }

Post_Resize_Window :: () {
    Resize_Render_Target(window.width, window.height);
    Set_Projection(window.width, window.height);
}

// TODO: simple axis-aligned 2d projection means don't need matrix
Set_Projection :: (render_target_width: s32, render_target_height: s32) {
    // right-handed
    m := orthographic_projection_matrix(0, cast(float) render_target_width*1, 0, cast(float) render_target_height, -1.0, 1.0, true);
    Set_Parameter_On_All_Shaders("mvp", m);
}


#if OS == .WINDOWS {
    #load "win32_graphics.jai";
}


DEFAULT_DEPTH :: -1.0;

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// VaiTexture :: struct {
//     width, height: s32;
//     id: u32;
// }
