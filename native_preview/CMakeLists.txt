cmake_minimum_required(VERSION 3.22)
project(VaiScenePreviewProvider LANGUAGES C CXX)

set(TINYUSDZ_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(TINYUSDZ_WITH_TYDRA ON CACHE BOOL "" FORCE)
set(TINYUSDZ_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(TINYUSDZ_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(TINYUSDZ_WITH_USDMTLX OFF CACHE BOOL "" FORCE)
set(TINYUSDZ_WITH_AUDIO OFF CACHE BOOL "" FORCE)
set(TINYUSDZ_WITH_EXR ON CACHE BOOL "" FORCE)
set(TINYUSDZ_WITH_TIFF ON CACHE BOOL "" FORCE)
set(TINYUSDZ_WITH_USD_TO_GLTF OFF CACHE BOOL "" FORCE)
set(TINYUSDZ_WITH_BUILTIN_IMAGE_LOADER OFF CACHE BOOL "" FORCE)
set(TINYUSDZ_WITH_PXR_COMPAT_API OFF CACHE BOOL "" FORCE)
set(TINYUSDZ_CXX_MP_FLAG ON CACHE BOOL "" FORCE)

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../third_party/tinyusdz ${CMAKE_BINARY_DIR}/tinyusdz)

add_library(vai_builtin_scene_preview SHARED
    vai_builtin_scene_preview.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ufbx/ufbx.c
)

target_compile_features(vai_builtin_scene_preview PRIVATE cxx_std_17)
target_compile_definitions(vai_builtin_scene_preview PRIVATE _CRT_SECURE_NO_WARNINGS)
target_include_directories(vai_builtin_scene_preview PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/cgltf
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ufbx
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/tinyusdz/src
)
target_link_libraries(vai_builtin_scene_preview PRIVATE tinyusdz_static)

set_target_properties(vai_builtin_scene_preview PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/output
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/output
)

add_executable(vai_scene_preview_smoke_test vai_scene_preview_smoke_test.cpp)
target_include_directories(vai_scene_preview_smoke_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/tinyusdz/src/external
)
target_link_libraries(vai_scene_preview_smoke_test PRIVATE tinyusdz_static)
set_target_properties(vai_scene_preview_smoke_test PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/output
)

add_executable(vai_image_preview_gl_smoke_test vai_image_preview_gl_smoke_test.cpp)
target_link_libraries(vai_image_preview_gl_smoke_test PRIVATE opengl32 gdi32 user32)
set_target_properties(vai_image_preview_gl_smoke_test PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/output
)
