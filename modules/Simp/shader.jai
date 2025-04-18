#scope_export

Shader  :: struct {
    using platform: Shader_Platform;
}

set_projection :: () {
    t := context.simp.texture_render_target;
    if t {
        immediate_set_2d_projection(t.width, t.height);
    } else {
        c := *context.simp.current_window_info;
        immediate_set_2d_projection(c.window_width, c.window_height);
    }
}

set_shader_for_color :: (enable_blend := false) {
    CheckInit();
    shader := ifx enable_blend then *shader_color_with_blend else *shader_color;
    if state.current_shader != shader {
        immediate_set_shader(shader);
        set_projection();
    }
}

set_shader_for_text :: () {
    CheckInit();
    if state.current_shader != *shader_text {
        immediate_set_shader(*shader_text);
        set_projection();
    }
}

set_shader_for_images :: (texture: *Texture) {
    CheckInit();
    immediate_flush();

    target_shader := ifx context.simp.coordinate_system == .LEFT_HANDED then *shader_sprite_left_handed else *shader_sprite_right_handed;
    if state.current_shader != target_shader {
        immediate_set_shader(target_shader);
        set_projection();
    }

    immediate_set_texture(texture);
}

shader_text:   Shader;
shader_color:  Shader;
shader_color_with_blend:  Shader;
shader_sprite_right_handed: Shader;
shader_sprite_left\_handed: Shader;
