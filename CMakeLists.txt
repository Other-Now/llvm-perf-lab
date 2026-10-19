cmake_minimum_required(VERSION 3.20)
project(llvm-perf-lab LANGUAGES CXX)

find_package(LLVM REQUIRED CONFIG)
if(NOT LLVM_VERSION_MAJOR EQUAL 20)
  message(WARNING "developed against LLVM 20, found ${LLVM_PACKAGE_VERSION}")
endif()
message(STATUS "LLVM ${LLVM_PACKAGE_VERSION} at ${LLVM_DIR}")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include_directories(SYSTEM ${LLVM_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})

# Out-of-tree pass plugin: symbols resolve against the host `opt`/`clang`.
add_library(RangeCheckVersioning MODULE pass/RangeCheckVersioning.cpp)
if(NOT LLVM_ENABLE_RTTI)
  target_compile_options(RangeCheckVersioning PRIVATE -fno-rtti)
endif()
target_compile_options(RangeCheckVersioning PRIVATE -Wall -Wextra -Wno-unused-parameter)
set_target_properties(RangeCheckVersioning PROPERTIES PREFIX "")
