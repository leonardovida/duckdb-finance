# Included by DuckDB's build system when building this out-of-tree extension.
duckdb_extension_load(finance
    DONT_LINK
    LOAD_TESTS
    EXTENSION_VERSION 0.2.17
    SOURCE_DIR ${CMAKE_CURRENT_LIST_DIR}
    INCLUDE_DIR ${CMAKE_CURRENT_LIST_DIR}/include
    TEST_DIR ${CMAKE_CURRENT_LIST_DIR}/test/sql
)
