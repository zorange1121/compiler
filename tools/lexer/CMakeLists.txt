# wy-lex: standalone Flex lexer that dumps the token stream of a .wy source file
# Don't inherit the compiler's include paths (src/ has its own compiler_util.h)
set_property(DIRECTORY PROPERTY INCLUDE_DIRECTORIES "")

FLEX_TARGET(
        LexerScanner
        ${CMAKE_CURRENT_SOURCE_DIR}/compiler.l
        ${CMAKE_CURRENT_BINARY_DIR}/lex.yy.c
)

add_executable(
        wy-lex
        ${CMAKE_CURRENT_SOURCE_DIR}/main.c
        ${CMAKE_CURRENT_SOURCE_DIR}/lib/chinese_number.c
        ${LIB_DIR}/utf8.c/utf8.c
        ${FLEX_LexerScanner_OUTPUTS}
)
target_include_directories(wy-lex PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/lib
        ${LIB_DIR}
)
target_link_libraries(wy-lex m)
