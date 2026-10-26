cmake_minimum_required(VERSION 3.25)

set(EXAMINE_INTERACTION_VERSION_FILE "${CMAKE_CURRENT_SOURCE_DIR}/../../VERSION")
if(NOT EXISTS "${EXAMINE_INTERACTION_VERSION_FILE}")
    message(FATAL_ERROR "Missing version file: ${EXAMINE_INTERACTION_VERSION_FILE}")
endif()

file(READ "${EXAMINE_INTERACTION_VERSION_FILE}" EXAMINE_INTERACTION_VERSION)
string(STRIP "${EXAMINE_INTERACTION_VERSION}" EXAMINE_INTERACTION_VERSION)
if(NOT EXAMINE_INTERACTION_VERSION MATCHES "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
    message(FATAL_ERROR "VERSION must contain exactly one semantic version in MAJOR.MINOR.PATCH form")
endif()

project(ExamineInteractionNative VERSION "${EXAMINE_INTERACTION_VERSION}" LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(EXAMINE_INTERACTION_PROFILE_NATIVE
    "Enable low-frequency native query profiling logs"
    OFF
)

include(FetchContent)

set(RED4EXT_SDK_ROOT "" CACHE PATH "Optional path to an existing RED4ext.SDK checkout")
if(NOT RED4EXT_SDK_ROOT AND DEFINED ENV{RED4EXT_SDK_ROOT})
    file(TO_CMAKE_PATH "$ENV{RED4EXT_SDK_ROOT}" RED4EXT_SDK_ROOT)
endif()

if(RED4EXT_SDK_ROOT)
    message(STATUS "Using RED4ext.SDK from ${RED4EXT_SDK_ROOT}")
else()
    FetchContent_Declare(
        RED4extSDK
        GIT_REPOSITORY https://github.com/wopss/RED4ext.SDK.git
        GIT_TAG 5246e659d783e5834cc08a90e56c8932c9ed3449
        GIT_SHALLOW FALSE
        SOURCE_SUBDIR cmake/fetch-only
    )
    FetchContent_MakeAvailable(RED4extSDK)
    set(RED4EXT_SDK_ROOT "${red4extsdk_SOURCE_DIR}")
    message(STATUS "Using fetched RED4ext.SDK from ${RED4EXT_SDK_ROOT}")
endif()

if(NOT EXISTS "${RED4EXT_SDK_ROOT}/include/RED4ext/RED4ext.hpp")
    message(FATAL_ERROR "RED4EXT_SDK_ROOT does not point to a valid RED4ext.SDK checkout: ${RED4EXT_SDK_ROOT}")
endif()

FetchContent_Declare(
    RedLib
    GIT_REPOSITORY https://github.com/psiberx/cp2077-red-lib.git
    GIT_TAG 398a7104a5aa60765db7221ddcaa48c6686d12ae
    GIT_SHALLOW FALSE
)
FetchContent_MakeAvailable(RedLib)

configure_file(
    src/Version.hpp.in
    "${CMAKE_CURRENT_BINARY_DIR}/generated/Version.hpp"
    @ONLY
)

add_library(ExamineInteractionNative SHARED
    src/Plugin.cpp
    src/ScriptBindings.cpp
    src/Dof/DofOverride.cpp
    src/Interaction/LootChoice.cpp
    src/World/WorldMesh.cpp
    src/World/WorldMeshInstances.cpp
)

target_include_directories(ExamineInteractionNative PRIVATE
    "${RED4EXT_SDK_ROOT}/include"
    "${CMAKE_CURRENT_BINARY_DIR}/generated"
)

target_link_libraries(ExamineInteractionNative PRIVATE RedLib)

target_compile_definitions(ExamineInteractionNative PRIVATE
    _CRT_SECURE_NO_WARNINGS
    NOMINMAX
    WIN32_LEAN_AND_MEAN
)

if(EXAMINE_INTERACTION_PROFILE_NATIVE)
    target_compile_definitions(ExamineInteractionNative PRIVATE
        EXAMINE_INTERACTION_PROFILE_NATIVE=1
    )
    target_compile_options(ExamineInteractionNative PRIVATE /Zi)
    target_link_options(ExamineInteractionNative PRIVATE
        /DEBUG:FULL
        /OPT:REF
        /OPT:ICF
    )
    set_target_properties(ExamineInteractionNative PROPERTIES
        COMPILE_PDB_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
        PDB_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    )
endif()

target_compile_options(ExamineInteractionNative PRIVATE
    /Zc:preprocessor
)

set_target_properties(ExamineInteractionNative PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)

# Ensure the SDK RTTI declarations precede generated native headers.
target_precompile_headers(ExamineInteractionNative PRIVATE <RED4ext/RED4ext.hpp>)
