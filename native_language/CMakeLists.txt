cmake_minimum_required(VERSION 3.22)
project(VaiLanguageServices LANGUAGES C)

# The tree-sitter runtime is language-agnostic and statically linked into the
# Vai editor executable.  Per-language grammars and semantic backends ship in
# separate provider DLLs and are built elsewhere.
#
# tree-sitter uses a unity build: lib/src/lib.c #includes every other core .c
# file, so compiling that single translation unit produces the whole runtime.
set(TREE_SITTER_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/tree-sitter/lib)

add_library(tree-sitter STATIC
    ${TREE_SITTER_DIR}/src/lib.c
)

target_include_directories(tree-sitter PRIVATE
    ${TREE_SITTER_DIR}/src
    ${TREE_SITTER_DIR}/include
)
target_include_directories(tree-sitter PUBLIC
    ${TREE_SITTER_DIR}/include
)
target_compile_definitions(tree-sitter PRIVATE _CRT_SECURE_NO_WARNINGS)

set_target_properties(tree-sitter PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/output
)

# Per-language grammar parsers.  In the M1 highlighting spike the Jai grammar is
# linked directly into the editor as a static lib and called via tree_sitter_jai().
# In M2 this moves behind a provider DLL's get_grammar() export; the parser.c
# source itself does not change.
set(JAI_GRAMMAR_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/tree-sitter-jai)

add_library(jai-grammar STATIC
    ${JAI_GRAMMAR_DIR}/src/parser.c
)
target_include_directories(jai-grammar PRIVATE
    ${JAI_GRAMMAR_DIR}/src
)
target_compile_definitions(jai-grammar PRIVATE _CRT_SECURE_NO_WARNINGS)

set_target_properties(jai-grammar PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/output
)
