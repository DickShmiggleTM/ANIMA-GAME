cmake_minimum_required(VERSION 3.18)
project(anima_core VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ── Options ─────────────────────────────────────────────────────────────────
option(ANIMA_BUILD_GDEXTENSION "Build Godot GDExtension (requires godot-cpp)" OFF)
option(ANIMA_BUILD_TESTS       "Build unit tests" ON)
option(ANIMA_BUILD_ANDROID     "Cross-compile for Android (set ANDROID_ABI/etc)" OFF)

# ── Core simulation library ──────────────────────────────────────────────────
add_library(anima_core_lib STATIC
    src/ecs/entity_manager.cpp
    src/systems/systems.cpp
)
target_include_directories(anima_core_lib PUBLIC include)
target_compile_options(anima_core_lib PRIVATE
    $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wall -Wextra -O2>
)

# ── GDExtension shared library ───────────────────────────────────────────────
if(ANIMA_BUILD_GDEXTENSION)
    find_path(GODOT_CPP_INCLUDE godot_cpp/core/class_db.hpp
        HINTS ${GODOT_CPP_DIR}/include
        REQUIRED)
    find_library(GODOT_CPP_LIB godot-cpp
        HINTS ${GODOT_CPP_DIR}/bin
        REQUIRED)

    add_library(anima_gdextension SHARED
        src/api/gdextension_wrapper.cpp
    )
    target_include_directories(anima_gdextension PRIVATE
        include ${GODOT_CPP_INCLUDE})
    target_compile_definitions(anima_gdextension PRIVATE
        ANIMA_BUILD_GDEXTENSION)
    target_link_libraries(anima_gdextension PRIVATE
        anima_core_lib ${GODOT_CPP_LIB})

    # Android: output to Godot project addons folder
    if(ANIMA_BUILD_ANDROID)
        set_target_properties(anima_gdextension PROPERTIES
            LIBRARY_OUTPUT_DIRECTORY
            "${CMAKE_SOURCE_DIR}/../anima-godot/addons/anima_core/bin/android/${ANDROID_ABI}")
    else()
        set_target_properties(anima_gdextension PROPERTIES
            LIBRARY_OUTPUT_DIRECTORY
            "${CMAKE_SOURCE_DIR}/../anima-godot/addons/anima_core/bin")
    endif()
endif()

# ── Unit tests ───────────────────────────────────────────────────────────────
if(ANIMA_BUILD_TESTS)
    enable_testing()
    add_executable(test_ecs
        tests/test_ecs.cpp
        src/ecs/entity_manager.cpp
        src/systems/systems.cpp
    )
    target_include_directories(test_ecs PRIVATE include)
    target_link_libraries(test_ecs PRIVATE m)
    add_test(NAME ecs_unit_tests COMMAND test_ecs)
endif()

# ── Install ──────────────────────────────────────────────────────────────────
install(TARGETS anima_core_lib
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib)
install(DIRECTORY include/ DESTINATION include)
