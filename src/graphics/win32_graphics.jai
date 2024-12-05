
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// mostly copies Simp, but boiled down to only the things needed by vai

// for use with Scoped_Construct
Graphics_Backend :: struct {

    Initialize :: () -> success: bool {
        gl_context, device_context, chosen_msaa = wgl_create_context(window.handle, null, 3, 3, false, DEBUG_GRAPHICS, 1);
        if gl_context == null {
            Log_Error("failed creating gl and/or device context");
        }

        // primarily loading a giant vtable of procedures that will be used shortly. (some are already linked, but most aren't)
        gl_load(*gl);

        // initliaze gl state --->
        Resize_Render_Target(window.width, window.height);
        glClearColor(1,1,1,1);
        Enable_Depth_Test();
        glBlendEquation(GL_FUNC_ADD);
        glEnable(GL_SCISSOR_TEST);
        // glEnable(GL_CULL_FACE);
        glLineWidth(0.5); // for view layer outlines

        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 1);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

        // create & bind buffers --->
        glGenVertexArrays(1, *va);
        glBindVertexArray(va);
        glGenBuffers(1, *vb);
        glBindBuffer(GL_ARRAY_BUFFER, vb);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
        // glGenFramebuffers(1, *fb);

        // for glBlitFramebuffer calls, which is read and which is write
        glReadBuffer(GL_FRONT);
        glDrawBuffer(GL_BACK);

        // create shaders --->
        success: bool;
        overall_success := true;
        basic_color_shader, success = Create_Shader(BASIC_COLOR_VERTEX_SHADER, BASIC_COLOR_FRAGMENT_SHADER);
        overall_success &= success;
        text_shader, success = Create_Shader(TEXT_VERTEX_SHADER, TEXT_FRAGMENT_SHADER);
        overall_success &= success;

        if !overall_success {
            Log_Error("failed compiling shaders or creating shader objects");
            return false;
        }

        basic_color_shader.uniform_mvp_loc = glGetUniformLocation(basic_color_shader.id, temp_c_string("mvp"));
        text_shader.uniform_mvp_loc = glGetUniformLocation(text_shader.id, temp_c_string("mvp"));
        // turn off default attribute locations for shaders that don't have those attributes
        basic_color_shader.uv_loc = -1;

        // copy id & attribute locations
        alpha_blend_color_shader = basic_color_shader;
        invert_color_shader = basic_color_shader;
        line_shader = basic_color_shader;

        basic_color_shader.blend_style = .NONE;
        alpha_blend_color_shader.blend_style = .ALPHA_BLEND;
        invert_color_shader.blend_style = .INVERT_COLOR_BEHIND;
        text_shader.blend_style = .ALPHA_BLEND;
        line_shader.blend_style = .ALPHA_BLEND;
        line_shader.draw_style = .LINES;

        text_shader.texture_sampler_loc = glGetUniformLocation(text_shader.id, "text_sampler");

        vertices.data = vertex_buffer.data;

        DumpGLErrors("context");

        return true;
    }

    Shutdown :: () {
        ReleaseDC(window.handle, device_context);
        wglDeleteContext(gl_context);
    }

}

Copy_Previous_Render_Target :: () {
    glBlitFramebuffer(0, 0, window.width, window.height, 0, 0, window.width, window.height, GL_COLOR_BUFFER_BIT, GL_NEAREST);
}

Disable_Depth_Test :: inline () {
    glDisable(GL_DEPTH);
}

Enable_Depth_Test :: inline () {
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
}

Resize_Render_Target :: (width: s32, height: s32) {
    assert(width > 0 && height > 0);
    glViewport(0, 0, xx width, xx height);
    glScissor(0, 0, xx width, xx height);
}

Set_Scissor :: (ul: IntVector2, lr: IntVector2) {
    dx := cast(u32)max(lr.x-ul.x, 0); 
    dy := cast(u32)max(lr.y-ul.y, 0);
    glScissor(ul.x, window.height-lr.y, dx, dy);
}

Begin_Draw_Frame :: (full_update: bool) {
    Clear_Viewports();
    Set_Scissor(.{}, .{window.width, window.height});
    if full_update {
        glClearColor(window.clear_color.r, window.clear_color.g, window.clear_color.b, 1.0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    } else {
        glClear(GL_DEPTH_BUFFER_BIT);
    }
}

End_Draw_Frame :: () {
    if quit then return;
    Flush_Draws();
    if !wglSwapLayerBuffers(device_context, WGL_SWAP_MAIN_PLANE) {
        Log_Error("failed to swap buffers");
    }
}

Use_Shader :: (shader: *Shader) {
    assert(shader != null);
    if current_shader != shader {
        Flush_Draws();
    }
    current_shader = shader;
    if shader.blend_style == {
    case .NONE;
        glDisable(GL_BLEND);
    case .ALPHA_BLEND;
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    case .INVERT_COLOR_BEHIND;
        glEnable(GL_BLEND);
        glBlendFunc(GL_ONE_MINUS_DST_COLOR, GL_ZERO);
    }
    glUseProgram(shader.id);
}

Set_Shader_For_Color :: inline ()           { Use_Shader(*basic_color_shader);       }
Set_Shader_For_Lines :: inline ()           { Use_Shader(*line_shader);              }
Set_Shader_For_Blended_Color :: inline ()   { Use_Shader(*alpha_blend_color_shader); }
Set_Shader_For_Color_Inversion :: inline () { Use_Shader(*invert_color_shader);      }
Set_Shader_For_Text :: inline ()            { Use_Shader(*text_shader);              }

Set_Parameter_On_All_Shaders :: ($PARAM_NAME: string, m: Matrix4) {
    for unique_shaders {
        Set_Shader_Parameter(it, PARAM_NAME, m);
    }
}

Set_Shader_Parameter :: (shader: *Shader, $PARAM_NAME: string, m: Matrix4) #expand {
    #insert -> string {
        return tprint("glUniformMatrix4fv(shader.uniform_%_loc, 1, GL_TRUE, m.floats.data);", PARAM_NAME);
    }
}

Render_Line :: (a: IntVector2, b: IntVector2, color := fRGBA_WHITE, uv1 := Vector2.{}, uv2 := Vector2.{}, depth := DEFAULT_DEPTH) {
    assert(current_shader.draw_style == .LINES);
    if vertices.count + 2 > MAX_VERTICES then Flush_Draws();
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=As_Vector2(a), z=depth}, xx color, .{}});
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=As_Vector2(b), z=depth}, xx color, .{}});
}

Render_Quad_Lines :: (ul: IntVector2, lr: IntVector2, color := fRGBA_WHITE, depth := DEFAULT_DEPTH) {
    assert(current_shader.draw_style == .LINES);
    if vertices.count + 8 > MAX_VERTICES then Flush_Draws();
    // left side
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=As_Vector2(ul), z=depth}, xx color, .{}});
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=.{xx ul.x, xx lr.y}, z=depth}, xx color, .{}});
    // bottom side
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=.{xx ul.x, xx lr.y}, z=depth}, xx color, .{}});
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=As_Vector2(lr), z=depth}, xx color, .{}});
    // right side
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=As_Vector2(lr), z=depth}, xx color, .{}});
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=.{xx lr.x, xx ul.y}, z=depth}, xx color, .{}});
    // top side
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=.{xx lr.x, xx ul.y}, z=depth}, xx color, .{}});
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=As_Vector2(ul), z=depth}, xx color, .{}});
}

Render_Quad :: inline (ul: IntVector2, lr: IntVector2, color := fRGBA_WHITE, uv1 := Vector2.{}, uv2 := Vector2.{}, depth := DEFAULT_DEPTH) {
    if vertices.count + 6 > MAX_VERTICES then Flush_Draws();
    // tri 1
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=As_Vector2(ul), z=depth}, xx color, uv1});
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=.{xx ul.x, xx lr.y}, z=depth}, xx color, .{uv1.x, uv2.y}});
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=As_Vector2(lr), z=depth}, xx color, uv2});
    // tri 2
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=As_Vector2(ul), z=depth}, xx color, uv1});
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=As_Vector2(lr), z=depth}, xx color, uv2});
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=.{xx lr.x, xx ul.y}, z=depth}, xx color, .{uv2.x, uv1.y}});
}

Render_Quad :: inline (ul: Vector2, lr: Vector2, color := fRGBA_WHITE, uv1 := Vector2.{}, uv2 := Vector2.{}, depth := DEFAULT_DEPTH) {
    if vertices.count + 6 > MAX_VERTICES then Flush_Draws();
    // tri 1
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=ul, z=depth}, xx color, uv1});
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=.{ul.x, lr.y}, z=depth}, xx color, .{uv1.x, uv2.y}});
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=lr, z=depth}, xx color, uv2});
    // tri 2
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=ul, z=depth}, xx color, uv1});
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=lr, z=depth}, xx color, uv2});
    Inline_Buffer_Append(*vertices, .{Vector3.{xy=.{lr.x, ul.y}, z=depth}, xx color, .{uv2.x, uv1.y}});
}

Flush_Draws :: () {
    if vertices.count == 0 {
        return;
    }
    if !current_shader {
        assert(false, "tried to draw batch with no shader.");
        vertices.count = 0;
        return;
    }

    Set_Projection(window.width, window.height); 

    Set_Vertex_Format(current_shader);
    
    glBufferData(GL_ARRAY_BUFFER, size_of(Vertex) * vertices.count, vertices.data, GL_STREAM_DRAW);
    DumpGLErrors("glBufferData in Flush_Draws");

    if current_shader.draw_style == .TRIANGLES {
        glDrawArrays(GL_TRIANGLES, 0, xx vertices.count);
    } else { // lines
        glDrawArrays(GL_LINES, 0, xx vertices.count);
    }
    DumpGLErrors("draw arrays in Flush_Draws");

    vertices.count = 0;
}

Set_Vertex_Format :: (shader: *Shader) {
    VERTEX_STRIDE: u32: #run size_of(Vertex);

    DumpGLErrors("Set_Vertex_Format: before starting");

    if shader.position_loc != -1 {
        glVertexAttribPointer(xx shader.position_loc, 3, GL_FLOAT, xx false, VERTEX_STRIDE, xx Offset_Of(Vertex, "position"));
        glEnableVertexAttribArray(xx shader.position_loc);
        DumpGLErrors("Set_Vertex_Format: position");
    }
    if shader.color_loc != -1 {
        glVertexAttribPointer(xx shader.color_loc, 4, GL_FLOAT, xx true, VERTEX_STRIDE, xx Offset_Of(Vertex, "color"));
        glEnableVertexAttribArray(xx shader.color_loc);
        DumpGLErrors("Set_Vertex_Format: color");
    }
    if shader.uv_loc != -1 {
        glVertexAttribPointer(xx shader.uv_loc, 2, GL_FLOAT, xx true, VERTEX_STRIDE, xx Offset_Of(Vertex, "uv"));
        glEnableVertexAttribArray(xx shader.uv_loc);
        DumpGLErrors("Set_Vertex_Format: uv");
    }
}

Render_Quads_Generated_For_Text :: () {
    Set_Shader_For_Text();

    // Draw_Letter_Quad :: inline (font: *Dynamic_Font, quad: Font_Quad) {
    //     page := quad.glyph.page;

    //     // if page.bitmap_data.width  <= 1 return;
    //     // if page.bitmap_data.height <= 1 return;

    //     using quad;
    //     Render_Quad(ul, lr, xx color, uv0, uv1);
    // }

    last_texture: s64 = -1;

    for quad, i: font.current_quads {
        page := quad.glyph.page;
        map  := *page.texture;

        if page.dirty {
            page.dirty = false;
            texture_load_from_bitmap(map, page.bitmap_data);
        }

        if map.gl_handle != last_texture {
            Flush_Draws();
            handle := map.gl_handle;
            last_texture = handle;

            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, handle);  // Bind handle to slot 0.
            glUniform1i(current_shader.texture_sampler_loc, 0);
        }

        Render_Quad(quad.ul, quad.lr, xx quad.color, quad.uv0, quad.uv1);
        // Draw_Letter_Quad(font, quad);
    }

    array_reset_keeping_memory(*font.current_quads);
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// shader logistics

INVALID_SHADER_ID : u32 : U32_MAX;

ShaderBlendStyle :: enum u8 {
    NONE;
    ALPHA_BLEND;
    INVERT_COLOR_BEHIND;
}

ShaderDrawStyle :: enum u8 {
    TRIANGLES;
    LINES;
}

Shader :: struct {
    id : u32 = INVALID_SHADER_ID;

    position_loc: s32 = 0;
    color_loc: s32 = 1;
    uv_loc: s32 = 2;

    uniform_mvp_loc: s32;
    texture_sampler_loc: s32;

    blend_style: ShaderBlendStyle;
    draw_style: ShaderDrawStyle;
}

Create_Shader :: (vertex: string, fragment: string) -> Shader, success: bool {
    shader: Shader;
    shader.id = glCreateProgram();
    vertex_id := Compile_Shader(vertex, GL_VERTEX_SHADER);
    fragment_id := Compile_Shader(fragment, GL_FRAGMENT_SHADER);
    if vertex_id == INVALID_SHADER_ID || fragment_id == INVALID_SHADER_ID {
        return .{}, false;
    }

    glAttachShader(shader.id, vertex_id);
    glAttachShader(shader.id, fragment_id);
    glLinkProgram(shader.id);
    glValidateProgram(shader.id);

    glDeleteShader(vertex_id);
    glDeleteShader(fragment_id);

    return shader, true;
}

Compile_Shader :: (source: string, type: u32) -> u32 {
    id := glCreateShader(type);
    shader_length : s32 = xx source.count;
    glShaderSource(id, 1, *source.data, *shader_length);
    glCompileShader(id);

    result: s32;
    glGetShaderiv(id, GL_COMPILE_STATUS, *result); 
    if !result {
        msg_length: s32;
        glGetShaderiv(id, GL_INFO_LOG_LENGTH, *msg_length);
        if msg_length <= 0 {
            return INVALID_SHADER_ID;
        }
        buffer := cast(*u8) talloc(msg_length);
        msg := string.{xx msg_length, buffer};
        msg_length_unsigned : u32 = xx msg_length;
        glGetShaderInfoLog(id, msg_length_unsigned, *msg_length_unsigned, msg.data);
        Log_Error("%", msg);
        glDeleteShader(id);
        return INVALID_SHADER_ID;
    }

    return id;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// shaders

BASIC_COLOR_VERTEX_SHADER :: #string HERE
#version 330 core

out vec4 f_color;

layout(location=0) in vec3 vert_position;
layout(location=1) in vec4 vert_color;

uniform mat4 mvp;

void main() {
    vec4 pos = mvp * vec4(vert_position.xyz, 1.0);
    gl_Position = vec4(pos.x, -pos.y, pos.z, pos.w);
    f_color = vert_color;
}
HERE

BASIC_COLOR_FRAGMENT_SHADER :: #string HERE
#version 330 core

out vec4 color;

in vec4 f_color;

void main() {
    color = f_color;
}
HERE

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

TEXT_VERTEX_SHADER :: #string HERE
#version 330 core

out vec2 tex_coords;
out vec3 f_color;

layout(location=0) in vec3 vert_position;
layout(location=1) in vec3 vert_color;
layout(location=2) in vec2 vert_uv;

uniform mat4 mvp;

void main() {
    // vec4 pos = mvp * vec4(vert_position.xyz, 1.0);
    // gl_Position = vec4(pos.x, -pos.y, pos.z, pos.w);
    gl_Position =  mvp * vec4(vert_position.xyz, 1.0);
    f_color = vert_color;
    tex_coords = vert_uv;
}
HERE

TEXT_FRAGMENT_SHADER :: #string HERE
#version 330 core

out vec4 color;

in vec2 tex_coords;
in vec3 f_color;

uniform sampler2D text_sampler;

void main() {
    vec4 sample = texture(text_sampler, tex_coords);
    color = vec4(f_color.rgb, sample.a);
    if (sample.a < 0.2) {
        discard;
    }
}
HERE

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

gl_context: HGLRC;
device_context: HDC;
chosen_msaa: s32;

current_shader: *Shader;
basic_color_shader: Shader;
alpha_blend_color_shader: Shader;
invert_color_shader: Shader;
text_shader: Shader;
line_shader: Shader;
unique_shaders := *Shader.[*basic_color_shader, *text_shader];

va: u32; // vertex array
vb: u32; // vertex buffer
// fb: u32; // frame buffer

Vertex :: struct {
    position:       Vector3;
    color:          Vector4;
    uv:             Vector2;
}

MAX_VERTICES :: 4800;
vertex_buffer: [MAX_VERTICES] Vertex;
vertices: []Vertex;

DEFAULT_DEPTH :: -1.0;

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#import "GL";