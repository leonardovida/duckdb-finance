cmake_minimum_required(VERSION 3.10)

project(FinanceExtension)

set(TARGET_NAME finance)
set(EXTENSION_NAME ${TARGET_NAME}_extension)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include_directories(include)

set(EXTENSION_SOURCES
    src/finance_extension.cpp
    src/scalar.cpp
    src/macros.cpp
    src/aggregate.cpp
    src/table_functions.cpp)

build_static_extension(${TARGET_NAME} ${EXTENSION_SOURCES})

set(PARAMETERS "-warnings")
build_loadable_extension(${TARGET_NAME} ${PARAMETERS} ${EXTENSION_SOURCES})

install(
  TARGETS ${EXTENSION_NAME}
  EXPORT "${DUCKDB_EXPORT_SET}"
  LIBRARY DESTINATION "${INSTALL_LIB_DIR}"
  ARCHIVE DESTINATION "${INSTALL_LIB_DIR}")
