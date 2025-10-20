cmake_minimum_required(VERSION 3.20)
project(DataMonitor LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)

set(SOURCES src/main.mm)
set(RESOURCE_FILES resources/DataMonitorIcon.png resources/DataMonitorIcon.icns)

add_executable(DataMonitor MACOSX_BUNDLE ${SOURCES})

target_link_libraries(DataMonitor
    "-framework Cocoa"
)

set_target_properties(DataMonitor PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_ICON_FILE "DataMonitorIcon"
)

foreach(resource ${RESOURCE_FILES})
    get_filename_component(filename ${resource} NAME)
    add_custom_command(TARGET DataMonitor POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy
        ${CMAKE_SOURCE_DIR}/${resource}
        $<TARGET_BUNDLE_DIR:DataMonitor>/Contents/Resources/${filename}
    )
endforeach()
