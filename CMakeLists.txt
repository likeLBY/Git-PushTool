cmake_minimum_required(VERSION 3.16)

project(Git VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickDialogs2 Widgets Concurrent)

qt_standard_project_setup(REQUIRES 6.8)

# Windows application icon
set(APP_ICON_RESOURCE_WINDOWS "${CMAKE_CURRENT_SOURCE_DIR}/appicon.rc")

qt_add_executable(appGit
    main.cpp
    gitmanager.h
    gitmanager.cpp
    resources.qrc
    ${APP_ICON_RESOURCE_WINDOWS}
)

qt_add_qml_module(appGit
    URI Git
    QML_FILES
        Main.qml
        FilePanel.qml
        FileItem.qml
        ActionButton.qml
        IconButton.qml
        Toast.qml
        MacTitleBar.qml
    RESOURCES
        images/icon.ico
        images/wallpaper.png
        images/wallpaper-dark.png
        images/git.png
        images/github.png
        images/github.com-favicon.ico
        images/gitee.com-favicon.ico
        fonts/fontawesome/Font\ Awesome\ 6\ Free-Solid-900.otf
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(appGit PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.appGit
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appGit
    PRIVATE Qt6::Quick Qt6::QuickDialogs2 Qt6::Widgets Qt6::Concurrent
)

include(GNUInstallDirs)
install(TARGETS appGit
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
