#include <windows.h>
#include <GL/gl.h>

#include <array>
#include <cstddef>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <vector>

#define STB_IMAGE_IMPLEMENTATION
#include "../third_party/tinyusdz/src/external/stb_image.h"

#ifndef GL_ARRAY_BUFFER
#define GL_ARRAY_BUFFER 0x8892
#define GL_STATIC_DRAW 0x88E4
#define GL_VERTEX_SHADER 0x8B31
#define GL_FRAGMENT_SHADER 0x8B30
#define GL_COMPILE_STATUS 0x8B81
#define GL_LINK_STATUS 0x8B82
#define GL_INFO_LOG_LENGTH 0x8B84
#define GL_TEXTURE0 0x84C0
#define GL_RGBA8 0x8058
#define GL_CLAMP_TO_EDGE 0x812F
#define GL_UNPACK_ROW_LENGTH 0x0CF2
#endif

#ifndef APIENTRYP
#define APIENTRYP APIENTRY *
#endif

using GLchar = char;
using GLsizeiptr = std::ptrdiff_t;
using PFNGLGENVERTEXARRAYSPROC = void (APIENTRYP)(GLsizei, GLuint*);
using PFNGLBINDVERTEXARRAYPROC = void (APIENTRYP)(GLuint);
using PFNGLDELETEVERTEXARRAYSPROC = void (APIENTRYP)(GLsizei, const GLuint*);
using PFNGLGENBUFFERSPROC = void (APIENTRYP)(GLsizei, GLuint*);
using PFNGLBINDBUFFERPROC = void (APIENTRYP)(GLenum, GLuint);
using PFNGLDELETEBUFFERSPROC = void (APIENTRYP)(GLsizei, const GLuint*);
using PFNGLBUFFERDATAPROC = void (APIENTRYP)(GLenum, GLsizeiptr, const void*, GLenum);
using PFNGLCREATESHADERPROC = GLuint (APIENTRYP)(GLenum);
using PFNGLSHADERSOURCEPROC = void (APIENTRYP)(GLuint, GLsizei, const GLchar* const*, const GLint*);
using PFNGLCOMPILESHADERPROC = void (APIENTRYP)(GLuint);
using PFNGLGETSHADERIVPROC = void (APIENTRYP)(GLuint, GLenum, GLint*);
using PFNGLGETSHADERINFOLOGPROC = void (APIENTRYP)(GLuint, GLsizei, GLsizei*, GLchar*);
using PFNGLDELETESHADERPROC = void (APIENTRYP)(GLuint);
using PFNGLCREATEPROGRAMPROC = GLuint (APIENTRYP)();
using PFNGLATTACHSHADERPROC = void (APIENTRYP)(GLuint, GLuint);
using PFNGLLINKPROGRAMPROC = void (APIENTRYP)(GLuint);
using PFNGLGETPROGRAMIVPROC = void (APIENTRYP)(GLuint, GLenum, GLint*);
using PFNGLGETPROGRAMINFOLOGPROC = void (APIENTRYP)(GLuint, GLsizei, GLsizei*, GLchar*);
using PFNGLUSEPROGRAMPROC = void (APIENTRYP)(GLuint);
using PFNGLDELETEPROGRAMPROC = void (APIENTRYP)(GLuint);
using PFNGLGETUNIFORMLOCATIONPROC = GLint (APIENTRYP)(GLuint, const GLchar*);
using PFNGLUNIFORM1IPROC = void (APIENTRYP)(GLint, GLint);
using PFNGLUNIFORMMATRIX4FVPROC = void (APIENTRYP)(GLint, GLsizei, GLboolean, const GLfloat*);
using PFNGLVERTEXATTRIBPOINTERPROC = void (APIENTRYP)(GLuint, GLint, GLenum, GLboolean, GLsizei, const void*);
using PFNGLENABLEVERTEXATTRIBARRAYPROC = void (APIENTRYP)(GLuint);
using PFNGLACTIVETEXTUREPROC = void (APIENTRYP)(GLenum);

struct GLFunctions {
    PFNGLGENVERTEXARRAYSPROC GenVertexArrays = nullptr;
    PFNGLBINDVERTEXARRAYPROC BindVertexArray = nullptr;
    PFNGLDELETEVERTEXARRAYSPROC DeleteVertexArrays = nullptr;
    PFNGLGENBUFFERSPROC GenBuffers = nullptr;
    PFNGLBINDBUFFERPROC BindBuffer = nullptr;
    PFNGLDELETEBUFFERSPROC DeleteBuffers = nullptr;
    PFNGLBUFFERDATAPROC BufferData = nullptr;
    PFNGLCREATESHADERPROC CreateShader = nullptr;
    PFNGLSHADERSOURCEPROC ShaderSource = nullptr;
    PFNGLCOMPILESHADERPROC CompileShader = nullptr;
    PFNGLGETSHADERIVPROC GetShaderiv = nullptr;
    PFNGLGETSHADERINFOLOGPROC GetShaderInfoLog = nullptr;
    PFNGLDELETESHADERPROC DeleteShader = nullptr;
    PFNGLCREATEPROGRAMPROC CreateProgram = nullptr;
    PFNGLATTACHSHADERPROC AttachShader = nullptr;
    PFNGLLINKPROGRAMPROC LinkProgram = nullptr;
    PFNGLGETPROGRAMIVPROC GetProgramiv = nullptr;
    PFNGLGETPROGRAMINFOLOGPROC GetProgramInfoLog = nullptr;
    PFNGLUSEPROGRAMPROC UseProgram = nullptr;
    PFNGLDELETEPROGRAMPROC DeleteProgram = nullptr;
    PFNGLGETUNIFORMLOCATIONPROC GetUniformLocation = nullptr;
    PFNGLUNIFORM1IPROC Uniform1i = nullptr;
    PFNGLUNIFORMMATRIX4FVPROC UniformMatrix4fv = nullptr;
    PFNGLVERTEXATTRIBPOINTERPROC VertexAttribPointer = nullptr;
    PFNGLENABLEVERTEXATTRIBARRAYPROC EnableVertexAttribArray = nullptr;
    PFNGLACTIVETEXTUREPROC ActiveTexture = nullptr;
};

void* GLProc(const char* name) {
    void* procedure = reinterpret_cast<void*>(wglGetProcAddress(name));
    if (procedure && procedure != reinterpret_cast<void*>(1) && procedure != reinterpret_cast<void*>(2)
        && procedure != reinterpret_cast<void*>(3) && procedure != reinterpret_cast<void*>(-1)) {
        return procedure;
    }
    return reinterpret_cast<void*>(GetProcAddress(GetModuleHandleA("opengl32.dll"), name));
}

bool LoadGL(GLFunctions* gl) {
#define LOAD_GL(name) \
    gl->name = reinterpret_cast<decltype(gl->name)>(GLProc("gl" #name)); \
    if (!gl->name) { std::fprintf(stderr, "missing OpenGL entry point gl%s\\n", #name); return false; }
    LOAD_GL(GenVertexArrays)
    LOAD_GL(BindVertexArray)
    LOAD_GL(DeleteVertexArrays)
    LOAD_GL(GenBuffers)
    LOAD_GL(BindBuffer)
    LOAD_GL(DeleteBuffers)
    LOAD_GL(BufferData)
    LOAD_GL(CreateShader)
    LOAD_GL(ShaderSource)
    LOAD_GL(CompileShader)
    LOAD_GL(GetShaderiv)
    LOAD_GL(GetShaderInfoLog)
    LOAD_GL(DeleteShader)
    LOAD_GL(CreateProgram)
    LOAD_GL(AttachShader)
    LOAD_GL(LinkProgram)
    LOAD_GL(GetProgramiv)
    LOAD_GL(GetProgramInfoLog)
    LOAD_GL(UseProgram)
    LOAD_GL(DeleteProgram)
    LOAD_GL(GetUniformLocation)
    LOAD_GL(Uniform1i)
    LOAD_GL(UniformMatrix4fv)
    LOAD_GL(VertexAttribPointer)
    LOAD_GL(EnableVertexAttribArray)
    LOAD_GL(ActiveTexture)
#undef LOAD_GL
    return true;
}

bool CheckGL(const char* stage) {
    const GLenum error = glGetError();
    if (error == GL_NO_ERROR) return true;
    std::fprintf(stderr, "OpenGL error after %s: 0x%04x\\n", stage, error);
    return false;
}

GLuint CompileShader(GLFunctions* gl, GLenum type, const char* source) {
    const GLuint shader = gl->CreateShader(type);
    gl->ShaderSource(shader, 1, &source, nullptr);
    gl->CompileShader(shader);
    GLint compiled = GL_FALSE;
    gl->GetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (compiled == GL_TRUE) return shader;
    std::array<char, 2048> log = {};
    gl->GetShaderInfoLog(shader, static_cast<GLsizei>(log.size()), nullptr, log.data());
    std::fprintf(stderr, "shader compilation failed: %s\\n", log.data());
    gl->DeleteShader(shader);
    return 0;
}

bool IsColor(const std::array<unsigned char, 4>& actual, unsigned char r, unsigned char g, unsigned char b) {
    constexpr int tolerance = 3;
    return std::abs(static_cast<int>(actual[0]) - r) <= tolerance
        && std::abs(static_cast<int>(actual[1]) - g) <= tolerance
        && std::abs(static_cast<int>(actual[2]) - b) <= tolerance
        && actual[3] == 255;
}

int main(int argument_count, char** arguments) {
    const char* png_path = argument_count > 1 ? arguments[1] : "screenshot.png";
    const char* class_name = "VaiImagePreviewGLSmoke";
    WNDCLASSA window_class = {};
    window_class.lpfnWndProc = DefWindowProcA;
    window_class.hInstance = GetModuleHandleA(nullptr);
    window_class.lpszClassName = class_name;
    RegisterClassA(&window_class);

    HWND window = CreateWindowExA(0, class_name, class_name, WS_POPUP,
        0, 0, 64, 64, nullptr, nullptr, window_class.hInstance, nullptr);
    if (!window) {
        std::fprintf(stderr, "could not create GL smoke-test window\\n");
        return 1;
    }
    HDC device_context = GetDC(window);
    PIXELFORMATDESCRIPTOR pixel_format = {};
    pixel_format.nSize = sizeof(pixel_format);
    pixel_format.nVersion = 1;
    pixel_format.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pixel_format.iPixelType = PFD_TYPE_RGBA;
    pixel_format.cColorBits = 32;
    pixel_format.cDepthBits = 24;
    pixel_format.iLayerType = PFD_MAIN_PLANE;
    const int pixel_format_index = ChoosePixelFormat(device_context, &pixel_format);
    if (pixel_format_index == 0 || !SetPixelFormat(device_context, pixel_format_index, &pixel_format)) {
        std::fprintf(stderr, "could not select GL smoke-test pixel format\\n");
        ReleaseDC(window, device_context);
        DestroyWindow(window);
        return 1;
    }
    HGLRC context = wglCreateContext(device_context);
    if (!context || !wglMakeCurrent(device_context, context)) {
        std::fprintf(stderr, "could not make GL smoke-test context current\\n");
        if (context) wglDeleteContext(context);
        ReleaseDC(window, device_context);
        DestroyWindow(window);
        return 1;
    }

    GLFunctions gl = {};
    int result = 1;
    GLuint texture = 0, vertex_array = 0, vertex_buffer = 0, vertex_shader = 0, fragment_shader = 0, program = 0;
    do {
        if (!LoadGL(&gl)) break;

        // Decode and upload a real PNG from the repository. A successful
        // decode alone would not catch stale GL pixel-store state or a bad
        // source pointer, so compare the GPU texture with the RGBA data too.
        int png_width = 0, png_height = 0, png_channels = 0;
        stbi_uc* decoded_png = stbi_load(png_path, &png_width, &png_height, &png_channels, 4);
        if (!decoded_png || png_width <= 0 || png_height <= 0) {
            std::fprintf(stderr, "could not decode PNG fixture %s\n", png_path);
            if (decoded_png) stbi_image_free(decoded_png);
            break;
        }
        const size_t png_byte_count = static_cast<size_t>(png_width) * static_cast<size_t>(png_height) * 4;
        std::vector<unsigned char> png_pixels(decoded_png, decoded_png + png_byte_count);
        stbi_image_free(decoded_png);
        bool has_opaque_pixel = false;
        for (size_t index = 3; index < png_pixels.size(); index += 4) {
            has_opaque_pixel |= png_pixels[index] == 255;
        }
        if (!has_opaque_pixel) {
            std::fprintf(stderr, "PNG fixture %s unexpectedly has no opaque pixels\n", png_path);
            break;
        }

        constexpr std::array<unsigned char, 16> texture_pixels = {
            255, 0, 0, 255,       0, 255, 0, 255,
            0, 0, 255, 255,       255, 255, 255, 255,
        };
        std::array<unsigned char, 16> readback = {};
        glGenTextures(1, &texture);
        gl.ActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, texture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        // Mirror Vai's upload: Simp previously set a wider font-atlas stride.
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 4);
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, texture_pixels.data());
        glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, readback.data());
        if (!CheckGL("texture upload") || readback != texture_pixels) {
            std::fprintf(stderr, "uploaded texture pixels differ from their RGBA source\\n");
            break;
        }
        std::vector<unsigned char> png_readback(png_byte_count);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, png_width, png_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, png_pixels.data());
        glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, png_readback.data());
        if (!CheckGL("PNG texture upload") || png_readback != png_pixels) {
            std::fprintf(stderr, "PNG texture pixels differ from the decoded RGBA data\n");
            break;
        }
        // Restore the small color fixture so the framebuffer assertions below
        // can identify exactly which texels were sampled.
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, texture_pixels.data());

        constexpr const char* vertex_source = R"(#version 330 core
layout(location=0) in vec3 vert_position;
layout(location=1) in vec4 vert_color;
layout(location=2) in vec2 vert_uv;
out vec2 tex_coords;
out vec4 f_color;
uniform mat4 mvp;
void main() { gl_Position = mvp * vec4(vert_position, 1.0); f_color = vert_color; tex_coords = vert_uv; }
)";
        constexpr const char* fragment_source = R"(#version 330 core
in vec2 tex_coords;
in vec4 f_color;
out vec4 color;
uniform sampler2D image_sampler;
void main() { color = texture(image_sampler, tex_coords) * f_color; }
)";
        vertex_shader = CompileShader(&gl, GL_VERTEX_SHADER, vertex_source);
        fragment_shader = CompileShader(&gl, GL_FRAGMENT_SHADER, fragment_source);
        if (!vertex_shader || !fragment_shader) break;
        program = gl.CreateProgram();
        gl.AttachShader(program, vertex_shader);
        gl.AttachShader(program, fragment_shader);
        gl.LinkProgram(program);
        GLint linked = GL_FALSE;
        gl.GetProgramiv(program, GL_LINK_STATUS, &linked);
        if (linked != GL_TRUE) {
            std::array<char, 2048> log = {};
            gl.GetProgramInfoLog(program, static_cast<GLsizei>(log.size()), nullptr, log.data());
            std::fprintf(stderr, "shader linking failed: %s\\n", log.data());
            break;
        }

        constexpr float vertices[] = {
            -1, -1, 0,  1, 1, 1, 1,  0, 0,
             1, -1, 0,  1, 1, 1, 1,  1, 0,
             1,  1, 0,  1, 1, 1, 1,  1, 1,
            -1, -1, 0,  1, 1, 1, 1,  0, 0,
             1,  1, 0,  1, 1, 1, 1,  1, 1,
            -1,  1, 0,  1, 1, 1, 1,  0, 1,
        };
        gl.GenVertexArrays(1, &vertex_array);
        gl.BindVertexArray(vertex_array);
        gl.GenBuffers(1, &vertex_buffer);
        gl.BindBuffer(GL_ARRAY_BUFFER, vertex_buffer);
        gl.BufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
        constexpr GLsizei stride = 9 * sizeof(float);
        gl.VertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, reinterpret_cast<void*>(0));
        gl.EnableVertexAttribArray(0);
        gl.VertexAttribPointer(1, 4, GL_FLOAT, GL_TRUE, stride, reinterpret_cast<void*>(3 * sizeof(float)));
        gl.EnableVertexAttribArray(1);
        gl.VertexAttribPointer(2, 2, GL_FLOAT, GL_TRUE, stride, reinterpret_cast<void*>(7 * sizeof(float)));
        gl.EnableVertexAttribArray(2);
        gl.UseProgram(program);
        const GLint sampler = gl.GetUniformLocation(program, "image_sampler");
        const GLint mvp = gl.GetUniformLocation(program, "mvp");
        const std::array<float, 16> identity = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};
        gl.Uniform1i(sampler, 0);
        gl.UniformMatrix4fv(mvp, 1, GL_FALSE, identity.data());
        // Match the explorer's composited drawing state: the checkerboard is
        // below the image, while the image itself is alpha blended and clipped
        // to the preview rectangle.
        glDisable(GL_DEPTH_TEST);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glEnable(GL_SCISSOR_TEST);
        glScissor(0, 0, 64, 64);
        glViewport(0, 0, 64, 64);
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLES, 0, 6);
        std::array<unsigned char, 4> lower_left = {};
        std::array<unsigned char, 4> upper_right = {};
        glReadPixels(16, 16, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, lower_left.data());
        glReadPixels(48, 48, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, upper_right.data());
        if (!CheckGL("image shader draw") || !IsColor(lower_left, 255, 0, 0) || !IsColor(upper_right, 255, 255, 255)) {
            std::fprintf(stderr, "image shader framebuffer output does not match the texture: lower-left=(%u,%u,%u,%u), upper-right=(%u,%u,%u,%u)\\n",
                lower_left[0], lower_left[1], lower_left[2], lower_left[3], upper_right[0], upper_right[1], upper_right[2], upper_right[3]);
            break;
        }
        std::printf("decoded, uploaded, rendered, and read back %s\n", png_path);
        result = 0;
    } while (false);

    if (program) gl.DeleteProgram(program);
    if (vertex_shader) gl.DeleteShader(vertex_shader);
    if (fragment_shader) gl.DeleteShader(fragment_shader);
    if (vertex_buffer) gl.DeleteBuffers(1, &vertex_buffer);
    if (vertex_array) gl.DeleteVertexArrays(1, &vertex_array);
    if (texture) glDeleteTextures(1, &texture);
    wglMakeCurrent(nullptr, nullptr);
    wglDeleteContext(context);
    ReleaseDC(window, device_context);
    DestroyWindow(window);
    return result;
}
