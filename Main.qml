import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Window
import Qt.labs.platform as Platform
import Git

ApplicationWindow {
    id: window
    width: 1012
    height: 680
    visible: true
    title: "Git 推送工具-Aby"
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.Window

    // Dark mode toggle - synced with settings
    property bool isDarkMode: trayManager.isDarkMode

    // Hitokoto (一言) properties
    property string hitokotoText: "用代码表达言语的魅力"
    property string hitokotoFrom: ""
    property string hitokotoAuthor: ""

    // Fetch hitokoto on startup and periodically
    Component.onCompleted: {
        fetchHitokoto()
    }

    Timer {
        id: hitokotoTimer
        interval: 5000  // 5 seconds
        running: true
        repeat: true
        onTriggered: fetchHitokoto()
    }

    function fetchHitokoto() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText)
                        hitokotoText = response.hitokoto || ""
                        hitokotoFrom = response.from || ""
                        hitokotoAuthor = response.from_who || ""
                    } catch (e) {
                        console.log("Failed to parse hitokoto:", e)
                    }
                }
            }
        }
        xhr.open("GET", "https://v1.hitokoto.cn?c=a&c=b&c=c&c=d&c=h&c=i&c=k")
        xhr.send()
    }

    // For window dragging
    property point dragStartPosition

    // Handle close event
    onClosing: function(close) {
        // Check if user has remembered choice
        if (trayManager.hasRememberedChoice()) {
            if (trayManager.minimizeToTray) {
                close.accepted = false
                window.hide()
            } else {
                close.accepted = true
                trayManager.quitApp()
            }
        } else {
            close.accepted = false
            closeDialog.open()
        }
    }

    // Main container with rounded corners
    Rectangle {
        id: mainContainer
        anchors.fill: parent
        anchors.margins: 1
        radius: 12
        color: isDarkMode ? "#1a1a1a" : "#f5f5f5"
        clip: true

        Behavior on color { ColorAnimation { duration: 300 } }

        // Drop area for dragging folders
        DropArea {
            id: dropArea
            anchors.fill: parent
            z: 999
            
            onEntered: function(drag) {
                if (drag.hasUrls) {
                    drag.accepted = true
                    dropOverlay.visible = true
                }
            }
            
            onExited: {
                dropOverlay.visible = false
            }
            
            onDropped: function(drop) {
                dropOverlay.visible = false
                if (drop.hasUrls && drop.urls.length > 0) {
                    var url = drop.urls[0]
                    var path = url.toString()
                    
                    // Handle file:/// URLs on Windows
                    if (path.startsWith("file:///")) {
                        // Windows: file:///C:/path -> C:/path
                        path = path.replace("file:///", "")
                    } else if (path.startsWith("file://")) {
                        // Unix: file:///path -> /path
                        path = path.replace("file://", "")
                    }
                    
                    // Decode URL encoding (spaces, Chinese characters, etc.)
                    path = decodeURIComponent(path)
                    
                    console.log("Dropped path:", path)
                    gitManager.repoPath = path
                }
            }
        }
        
        // Drop overlay visual feedback
        Rectangle {
            id: dropOverlay
            anchors.fill: parent
            color: isDarkMode ? "#3b82f680" : "#3b82f640"
            visible: false
            z: 998
            radius: 12
            
            Rectangle {
                anchors.centerIn: parent
                width: 300
                height: 150
                radius: 16
                color: isDarkMode ? "#1e293b" : "#ffffff"
                border.color: "#3b82f6"
                border.width: 3
                
                Column {
                    anchors.centerIn: parent
                    spacing: 12
                    
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "\uf07b"
                        font.family: fontAwesome.name
                        font.pixelSize: 48
                        color: "#3b82f6"
                    }
                    
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "释放以打开仓库"
                        font.pixelSize: 16
                        font.bold: true
                        color: isDarkMode ? "#ffffff" : "#1e293b"
                    }
                }
            }
        }

        // Background image with blur
        Image {
            id: backgroundImage
            anchors.fill: parent
            source: isDarkMode ? "images/wallpaper-dark.png" : "images/wallpaper.png"
            fillMode: Image.PreserveAspectCrop
            visible: false
        }

        // Frosted glass blur effect
        MultiEffect {
            anchors.fill: parent
            source: backgroundImage
            blur: 0.8
            blurMax: 64
            brightness: 0.1
        }

        // Light/Dark overlay
        Rectangle {
            anchors.fill: parent
            color: isDarkMode ? "#000000" : "#ffffff"
            opacity: isDarkMode ? 0.7 : 0.85
            Behavior on color { ColorAnimation { duration: 300 } }
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        // Custom title bar
        Rectangle {
            id: titleBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 36
            color: "transparent"
            z: 100

            // Drag area
            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: windowButtons.width + 10
                
                property point clickPos
                
                onPressed: function(mouse) {
                    clickPos = Qt.point(mouse.x, mouse.y)
                }
                
                onPositionChanged: function(mouse) {
                    if (pressed) {
                        var delta = Qt.point(mouse.x - clickPos.x, mouse.y - clickPos.y)
                        window.x += delta.x
                        window.y += delta.y
                    }
                }
                
                onDoubleClicked: {
                    if (window.visibility === Window.Maximized) {
                        window.showNormal()
                    } else {
                        window.showMaximized()
                    }
                }
            }

            // Window title
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "Git 推送工具-Aby 作者：YE"
                font.pixelSize: 13
                font.bold: true
                color: isDarkMode ? "#e0e0e0" : "#333333"
                Behavior on color { ColorAnimation { duration: 300 } }
            }

            // Hitokoto display area
            Item {
                anchors.left: parent.left
                anchors.leftMargin: 220
                anchors.right: windowButtons.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: hitokotoText
                        font.pixelSize: 11
                        color: isDarkMode ? "#b0b0b0" : "#555555"
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 400)
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on color { ColorAnimation { duration: 300 } }
                    }

                    Text {
                        visible: hitokotoFrom !== "" || hitokotoAuthor !== ""
                        text: {
                            if (hitokotoAuthor && hitokotoFrom) {
                                return "—— " + hitokotoAuthor + "「" + hitokotoFrom + "」"
                            } else if (hitokotoFrom) {
                                return "——「" + hitokotoFrom + "」"
                            } else if (hitokotoAuthor) {
                                return "—— " + hitokotoAuthor
                            }
                            return ""
                        }
                        font.pixelSize: 10
                        color: isDarkMode ? "#808080" : "#888888"
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on color { ColorAnimation { duration: 300 } }
                    }
                }
            }

            // Window buttons
            Row {
                id: windowButtons
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                // Dark mode toggle button
                Rectangle {
                    width: 40
                    height: 26
                    radius: 13
                    color: isDarkMode ? "#333333" : "#f0f0f0"
                    border.color: isDarkMode ? "#555555" : "#d0d0d0"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 300 } }
                    Behavior on border.color { ColorAnimation { duration: 300 } }

                    // Sun icon
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf185"
                        font.family: fontAwesome.name
                        font.pixelSize: 10
                        color: isDarkMode ? "#666666" : "#f59e0b"
                        opacity: isDarkMode ? 0.5 : 1
                        rotation: isDarkMode ? -360 : 0
                        scale: isDarkMode ? 0.6 : 1
                        
                        Behavior on rotation { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }
                        Behavior on scale { NumberAnimation { duration: 300 } }
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }

                    // Moon icon
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf186"
                        font.family: fontAwesome.name
                        font.pixelSize: 10
                        color: isDarkMode ? "#a78bfa" : "#666666"
                        opacity: isDarkMode ? 1 : 0.5
                        rotation: isDarkMode ? 0 : 360
                        scale: isDarkMode ? 1 : 0.6
                        
                        Behavior on rotation { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }
                        Behavior on scale { NumberAnimation { duration: 300 } }
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }

                    HoverHandler { id: themeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: trayManager.isDarkMode = !trayManager.isDarkMode }

                    ToolTip.visible: themeHover.hovered
                    ToolTip.delay: 300
                    ToolTip.text: isDarkMode ? "切换到浅色模式" : "切换到深色模式"
                }

                // Settings button
                Rectangle {
                    width: 32
                    height: 26
                    radius: 6
                    color: settingsBtnHover.hovered ? (isDarkMode ? "#333333" : "#e5e5e5") : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\uf013"
                        font.family: fontAwesome.name
                        font.pixelSize: 11
                        color: isDarkMode ? "#aaaaaa" : "#666666"
                    }

                    HoverHandler { id: settingsBtnHover }
                    TapHandler { onTapped: settingsDialog.open() }

                    ToolTip.visible: settingsBtnHover.hovered
                    ToolTip.delay: 300
                    ToolTip.text: "设置"
                }

                // Separator
                Rectangle {
                    width: 1
                    height: 16
                    color: isDarkMode ? "#444444" : "#d0d0d0"
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Minimize button
                Rectangle {
                    width: 32
                    height: 26
                    radius: 6
                    color: minHover.hovered ? (isDarkMode ? "#333333" : "#e5e5e5") : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\uf068"
                        font.family: fontAwesome.name
                        font.pixelSize: 10
                        color: isDarkMode ? "#aaaaaa" : "#666666"
                    }

                    HoverHandler { id: minHover }
                    TapHandler { onTapped: window.showMinimized() }
                }

                // Maximize button
                Rectangle {
                    width: 32
                    height: 26
                    radius: 6
                    color: maxHover.hovered ? (isDarkMode ? "#333333" : "#e5e5e5") : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: window.visibility === Window.Maximized ? "\uf2d2" : "\uf2d0"
                        font.family: fontAwesome.name
                        font.pixelSize: 10
                        color: isDarkMode ? "#aaaaaa" : "#666666"
                    }

                    HoverHandler { id: maxHover }
                    TapHandler {
                        onTapped: {
                            if (window.visibility === Window.Maximized) {
                                window.showNormal()
                            } else {
                                window.showMaximized()
                            }
                        }
                    }
                }

                // Close button
                Rectangle {
                    width: 32
                    height: 26
                    radius: 6
                    color: closeHover.hovered ? "#ff4d4f" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\uf00d"
                        font.family: fontAwesome.name
                        font.pixelSize: 11
                        color: closeHover.hovered ? "#ffffff" : (isDarkMode ? "#aaaaaa" : "#666666")
                    }

                    HoverHandler { id: closeHover }
                    TapHandler { onTapped: window.close() }
                }
            }
        }

        // Content area (below title bar)
        Item {
            id: contentArea
            anchors.top: titleBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
        }
    }

    FontLoader {
        id: fontAwesome
        source: "fonts/fontawesome/Font Awesome 6 Free-Solid-900.otf"
    }

    // Theme colors - adapts to dark/light mode
    QtObject {
        id: theme
        property color background: "transparent"
        property color surface: isDarkMode ? "#2a2a2a" : "#ffffff"
        property color surfaceLight: isDarkMode ? "#333333" : "#f0f0f0"
        property color primary: "#4a90d9"
        property color secondary: "#7c5cbf"
        property color success: "#52c41a"
        property color warning: "#faad14"
        property color error: "#ff4d4f"
        property color text: isDarkMode ? "#e0e0e0" : "#1a1a1a"
        property color textDim: isDarkMode ? "#999999" : "#666666"
        property color border: isDarkMode ? "#444444" : "#d9d9d9"
    }

    GitManager {
        id: gitManager
        onOperationSuccess: (msg) => toast.show(msg, "success")
        onOperationFailed: (msg) => toast.show(msg, "error")
        onRemoteFilesNeedRefresh: {
            // Auto refresh remote files list after file operations
            if (remoteFileBrowserDrawer.opened) {
                gitManager.loadRemoteFiles(gitManager.remoteCurrentPath)
            }
        }
        onIsValidRepoChanged: {
            // Auto fill commit template when repo becomes valid
            if (gitManager.isValidRepo && trayManager.commitTemplate && commitInput.text === "") {
                commitInput.text = trayManager.commitTemplate
            }
        }
    }

    // Global shortcuts
    Shortcut {
        sequence: trayManager.shortcutCommit
        context: Qt.ApplicationShortcut
        onActivated: {
            if (gitManager.isValidRepo && commitInput.text.trim() !== "" && 
                (gitManager.changedFiles.length > 0 || gitManager.stagedFiles.length > 0)) {
                gitManager.quickSync(commitInput.text)
                commitInput.text = trayManager.commitTemplate || ""
            }
        }
    }

    Shortcut {
        sequence: trayManager.shortcutCommitOnly
        context: Qt.ApplicationShortcut
        onActivated: {
            if (gitManager.isValidRepo && commitInput.text.trim() !== "" && gitManager.stagedFiles.length > 0) {
                gitManager.commit(commitInput.text)
                commitInput.text = trayManager.commitTemplate || ""
            }
        }
    }

    Shortcut {
        sequence: trayManager.shortcutRefresh
        context: Qt.ApplicationShortcut
        onActivated: {
            if (gitManager.isValidRepo) {
                gitManager.refresh()
            }
        }
    }

    Shortcut {
        sequence: trayManager.shortcutPush
        context: Qt.ApplicationShortcut
        onActivated: {
            if (gitManager.isValidRepo) {
                gitManager.push()
            }
        }
    }

    Shortcut {
        sequence: trayManager.shortcutPull
        context: Qt.ApplicationShortcut
        onActivated: {
            if (gitManager.isValidRepo) {
                gitManager.pull()
            }
        }
    }

    FolderDialog {
        id: folderDialog
        title: "选择 Git 仓库"
        onAccepted: gitManager.repoPath = selectedFolder
    }

    FolderDialog {
        id: cloneFolderDialog
        title: "选择克隆目标文件夹"
        onAccepted: {
            gitManager.cloneRepo(cloneUrlInput.text, selectedFolder)
            cloneDialog.close()
            cloneUrlInput.text = ""
        }
    }

    // Clone dialog
    Dialog {
        id: cloneDialog
        title: ""
        anchors.centerIn: parent
        width: 450
        modal: true
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "克隆仓库"
            onCloseClicked: cloneDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 16

            Text {
                text: "输入仓库地址"
                font.pixelSize: 14
                font.bold: true
                color: "#1a1a1a"
            }

            Rectangle {
                Layout.fillWidth: true
                height: 44
                radius: 8
                color: "#ffffff"
                border.color: cloneUrlInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                border.width: 1

                TextInput {
                    id: cloneUrlInput
                    anchors.fill: parent
                    anchors.margins: 12
                    color: "#1a1a1a"
                    font.pixelSize: 13
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    selectByMouse: true

                    Text {
                        anchors.fill: parent
                        anchors.verticalCenter: parent.verticalCenter
                        text: "https://github.com/user/repo.git"
                        color: "#9ca3af"
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        visible: !cloneUrlInput.text && !cloneUrlInput.activeFocus
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 30
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: cancelArea1.containsMouse ? "#3b82f6" : "#6b7280"
                    Behavior on color { ColorAnimation { duration: 150 } }
                    MouseArea {
                        id: cancelArea1
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            cloneDialog.close()
                            cloneUrlInput.text = ""
                        }
                    }
                }

                ActionButton {
                    text: "选择目录"
                    icon: "\uf07b"
                    fontFamily: fontAwesome.name
                    primary: true
                    enabled: cloneUrlInput.text.trim() !== ""
                    onClicked: cloneFolderDialog.open()
                }
            }
        }
    }

    // Branch management dialog
    Dialog {
        id: branchDialog
        title: ""
        anchors.centerIn: parent
        width: 500
        height: 450
        modal: true
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "分支管理"
            onCloseClicked: branchDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 12

            // Current branch info
            Rectangle {
                Layout.fillWidth: true
                height: 50
                radius: 8
                color: "#f0f4f8"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Text {
                        text: "当前分支:"
                        font.pixelSize: 13
                        color: "#666666"
                    }
                    Text {
                        text: gitManager.currentBranch
                        font.pixelSize: 14
                        font.bold: true
                        color: "#10b981"
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            // New branch input
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    radius: 8
                    color: "#ffffff"
                    border.color: newBranchInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                    border.width: 1

                    TextInput {
                        id: newBranchInput
                        anchors.fill: parent
                        anchors.margins: 10
                        color: "#1a1a1a"
                        font.pixelSize: 13
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true

                        Text {
                            anchors.fill: parent
                            text: "输入新分支名称..."
                            color: "#9ca3af"
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                            visible: !newBranchInput.text && !newBranchInput.activeFocus
                        }
                    }
                }

                ActionButton {
                    text: "新建"
                    icon: "\uf067"
                    fontFamily: fontAwesome.name
                    primary: true
                    enabled: newBranchInput.text.trim() !== ""
                    onClicked: {
                        gitManager.createBranch(newBranchInput.text.trim())
                        newBranchInput.text = ""
                    }
                }
            }

            // Branch list header
            Text {
                text: "所有分支 (" + gitManager.branches.length + ")"
                font.pixelSize: 13
                font.bold: true
                color: "#1a1a1a"
                Layout.topMargin: 4
            }

            // Branch list
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: "#ffffff"
                clip: true

                ListView {
                    id: branchListView
                    anchors.fill: parent
                    anchors.margins: 4
                    model: gitManager.branches
                    spacing: 2

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AlwaysOff
                    }

                    delegate: Rectangle {
                        id: branchDelegate
                        width: branchListView.width
                        height: 44
                        radius: 6
                        color: branchHover.hovered ? "#f3f4f6" : "transparent"

                        property bool isCurrent: modelData === gitManager.currentBranch
                        property bool isRemoteOnly: !gitManager.localBranches.includes(modelData)

                        HoverHandler {
                            id: branchHover
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            // Current indicator
                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: branchDelegate.isCurrent ? "#10b981" : "transparent"
                                border.color: branchDelegate.isCurrent ? "#10b981" : "#d1d5db"
                                border.width: 1
                            }

                            Text {
                                text: modelData
                                font.pixelSize: 13
                                font.bold: branchDelegate.isCurrent
                                color: branchDelegate.isCurrent ? "#10b981" : (branchDelegate.isRemoteOnly ? "#9ca3af" : "#1a1a1a")
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            // Remote tag
                            Rectangle {
                                visible: branchDelegate.isRemoteOnly
                                width: remoteTag.width + 8
                                height: 18
                                radius: 4
                                color: "#e5e7eb"

                                Text {
                                    id: remoteTag
                                    anchors.centerIn: parent
                                    text: "远程"
                                    font.pixelSize: 9
                                    color: "#6b7280"
                                }
                            }

                            // Switch button
                            Rectangle {
                                width: 50
                                height: 28
                                radius: 6
                                color: switchHover.hovered ? "#3b82f6" : "#dbeafe"
                                opacity: !branchDelegate.isCurrent && branchHover.hovered ? 1 : 0
                                visible: opacity > 0

                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "切换"
                                    font.pixelSize: 11
                                    color: switchHover.hovered ? "#ffffff" : "#3b82f6"
                                }

                                HoverHandler {
                                    id: switchHover
                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    onTapped: gitManager.switchBranch(modelData)
                                }
                            }

                            // Merge button
                            Rectangle {
                                width: 50
                                height: 28
                                radius: 6
                                color: mergeHover.hovered ? "#8b5cf6" : "#ede9fe"
                                opacity: !branchDelegate.isCurrent && branchHover.hovered ? 1 : 0
                                visible: opacity > 0

                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "合并"
                                    font.pixelSize: 11
                                    color: mergeHover.hovered ? "#ffffff" : "#8b5cf6"
                                }

                                HoverHandler {
                                    id: mergeHover
                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    onTapped: {
                                        mergeBranchName = modelData
                                        mergeConfirmDialog.open()
                                    }
                                }

                                ToolTip.visible: mergeHover.hovered
                                ToolTip.text: "将「" + modelData + "」分支合并到「" + gitManager.currentBranch + "」"
                                ToolTip.delay: 500
                            }

                            // Reset/Replace button
                            Rectangle {
                                width: 50
                                height: 28
                                radius: 6
                                color: resetHover.hovered ? "#f97316" : "#ffedd5"
                                opacity: !branchDelegate.isCurrent && branchHover.hovered ? 1 : 0
                                visible: opacity > 0

                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "替换"
                                    font.pixelSize: 11
                                    color: resetHover.hovered ? "#ffffff" : "#f97316"
                                }

                                HoverHandler {
                                    id: resetHover
                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    onTapped: {
                                        resetBranchName = modelData
                                        resetConfirmDialog.open()
                                    }
                                }

                                ToolTip.visible: resetHover.hovered
                                ToolTip.text: "将「" + modelData + "」分支替换到「" + gitManager.currentBranch + "」"
                                ToolTip.delay: 500
                            }

                            // Delete button
                            Rectangle {
                                width: 28
                                height: 28
                                radius: 6
                                color: deleteHover.hovered ? "#fee2e2" : "transparent"
                                opacity: !branchDelegate.isCurrent && branchHover.hovered ? 1 : 0
                                visible: opacity > 0

                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf1f8"
                                    font.family: fontAwesome.name
                                    font.pixelSize: 12
                                    color: "#ef4444"
                                }

                                HoverHandler {
                                    id: deleteHover
                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    onTapped: {
                                        deleteBranchName = modelData
                                        deleteBranchConfirmDialog.open()
                                    }
                                }

                                ToolTip.visible: deleteHover.hovered
                                ToolTip.text: "删除「" + modelData + "」分支"
                                ToolTip.delay: 500
                            }
                        }
                    }
                }
            }

            // Close button - simple text
            Item {
                Layout.fillWidth: true
                height: 36
                
                Text {
                    anchors.centerIn: parent
                    text: "关闭"
                    font.pixelSize: 13
                    color: closeArea.containsMouse ? "#3b82f6" : "#6b7280"
                    
                    Behavior on color { ColorAnimation { duration: 150 } }
                    
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        anchors.margins: -10
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: branchDialog.close()
                    }
                }
            }
        }
    }

    // Large files cleanup dialog
    Dialog {
        id: largeFilesDialog
        title: ""
        anchors.centerIn: parent
        width: 550
        height: 500
        modal: true
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "清理大文件"
            onCloseClicked: largeFilesDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 12

            // Warning message
            Rectangle {
                Layout.fillWidth: true
                height: 60
                radius: 8
                color: "#fef3c7"
                border.color: "#f59e0b"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    Text {
                        text: "\uf071"
                        font.family: fontAwesome.name
                        font.pixelSize: 20
                        color: "#f59e0b"
                    }

                    Text {
                        text: "以下文件超过 50MB，可能导致推送失败。\n清理后需要强制推送 (git push --force)"
                        font.pixelSize: 12
                        color: "#92400e"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Refresh button
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "历史中的大文件 (" + largeFilesList.count + " 个)"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#1a1a1a"
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 70
                    height: 28
                    radius: 6
                    color: refreshLargeHover.hovered ? "#e5e7eb" : "#f3f4f6"

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: "\uf021"
                            font.family: fontAwesome.name
                            font.pixelSize: 11
                            color: "#6b7280"
                        }
                        Text {
                            text: "刷新"
                            font.pixelSize: 11
                            color: "#6b7280"
                        }
                    }

                    HoverHandler { id: refreshLargeHover }
                    TapHandler {
                        onTapped: gitManager.findLargeFiles(50)
                    }
                }
            }

            // Large files list
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: "#ffffff"
                clip: true

                ListView {
                    id: largeFilesList
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 4
                    model: gitManager.largeFilesList

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        width: largeFilesList.width - 8
                        height: 56
                        radius: 6
                        color: largeFileHover.hovered ? "#f3f4f6" : "transparent"

                        HoverHandler { id: largeFileHover }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            // File icon
                            Rectangle {
                                width: 36
                                height: 36
                                radius: 8
                                color: "#fee2e2"

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf1c0"
                                    font.family: fontAwesome.name
                                    font.pixelSize: 16
                                    color: "#ef4444"
                                }
                            }

                            // File info
                            Column {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: modelData.path || ""
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: "#1a1a1a"
                                    elide: Text.ElideMiddle
                                    width: parent.width
                                }

                                Text {
                                    text: modelData.sizeStr || ""
                                    font.pixelSize: 11
                                    color: "#ef4444"
                                }
                            }

                            // Delete button
                            Rectangle {
                                width: 60
                                height: 28
                                radius: 6
                                color: cleanBtnHover.hovered ? "#ef4444" : "#fee2e2"
                                visible: largeFileHover.hovered

                                Text {
                                    anchors.centerIn: parent
                                    text: "清理"
                                    font.pixelSize: 11
                                    color: cleanBtnHover.hovered ? "#ffffff" : "#ef4444"
                                }

                                HoverHandler { id: cleanBtnHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        cleanConfirmPath = modelData.path
                                        cleanConfirmDialog.open()
                                    }
                                }
                            }
                        }
                    }

                    // Empty state
                    Text {
                        anchors.centerIn: parent
                        visible: largeFilesList.count === 0
                        text: "没有发现大文件 ✓"
                        font.pixelSize: 14
                        color: "#10b981"
                    }
                }
            }

            // Force push button
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "关闭"
                    font.pixelSize: 13
                    color: closeLargeArea.containsMouse ? "#3b82f6" : "#6b7280"
                    
                    MouseArea {
                        id: closeLargeArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: largeFilesDialog.close()
                    }
                }

                ActionButton {
                    text: "强制推送"
                    icon: "\uf093"
                    fontFamily: fontAwesome.name
                    primary: true
                    onClicked: {
                        gitManager.forcePush()
                        largeFilesDialog.close()
                    }
                }
            }
        }
    }

    // Gitignore manager dialog
    Dialog {
        id: gitignoreDialog
        title: ""
        anchors.centerIn: parent
        width: 450
        height: 400
        modal: true
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "管理 .gitignore"
            onCloseClicked: gitignoreDialog.close()
        }

        property var rules: []

        onOpened: {
            rules = gitManager.getGitignoreRules()
        }

        contentItem: ColumnLayout {
            spacing: 12

            // Info message
            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 8
                color: "#eff6ff"
                border.color: "#3b82f6"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: "\uf05a"
                        font.family: fontAwesome.name
                        font.pixelSize: 14
                        color: "#3b82f6"
                    }

                    Text {
                        text: "点击规则可以将其从 .gitignore 中移除"
                        font.pixelSize: 11
                        color: "#1e40af"
                        Layout.fillWidth: true
                    }
                }
            }

            // Rules list
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: "#ffffff"
                clip: true

                ListView {
                    id: gitignoreList
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 4
                    model: gitignoreDialog.rules

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        width: ListView.view.width - 8
                        height: 40
                        radius: 6
                        color: ruleHover.hovered ? "#fef2f2" : "#f9fafb"
                        border.color: ruleHover.hovered ? "#fecaca" : "transparent"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            Text {
                                text: "\uf070"
                                font.family: fontAwesome.name
                                font.pixelSize: 12
                                color: "#9ca3af"
                            }

                            Text {
                                text: modelData
                                font.pixelSize: 13
                                font.family: "Consolas, Monaco, monospace"
                                color: "#374151"
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }

                            Text {
                                visible: ruleHover.hovered
                                text: "\uf1f8"
                                font.family: fontAwesome.name
                                font.pixelSize: 12
                                color: "#ef4444"
                            }
                        }

                        HoverHandler {
                            id: ruleHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: {
                                gitManager.removeFromGitignore(modelData)
                                gitignoreDialog.rules = gitManager.getGitignoreRules()
                            }
                        }
                    }

                    // Empty state
                    Text {
                        anchors.centerIn: parent
                        visible: gitignoreList.count === 0
                        text: ".gitignore 为空"
                        font.pixelSize: 14
                        color: "#9ca3af"
                    }
                }
            }

            // Close button
            RowLayout {
                Layout.fillWidth: true

                Item { Layout.fillWidth: true }

                Text {
                    text: "关闭"
                    font.pixelSize: 13
                    color: closeGitignoreArea.containsMouse ? "#3b82f6" : "#6b7280"
                    
                    MouseArea {
                        id: closeGitignoreArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: gitignoreDialog.close()
                    }
                }
            }
        }
    }

    // Diff dialog
    property string diffDialogPath: ""
    property bool diffDialogStaged: false
    property var diffDialogData: []
    
    Dialog {
        id: diffDialog
        title: ""
        anchors.centerIn: parent
        width: Math.min(800, window.width - 80)
        height: Math.min(600, window.height - 100)
        modal: true
        standardButtons: Dialog.NoButton
        padding: 0
        topPadding: 0

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "文件差异 - " + diffDialogPath
            onCloseClicked: diffDialog.close()
        }

        contentItem: Rectangle {
            color: "transparent"
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                
                // Legend
                Row {
                    spacing: 20
                    Layout.fillWidth: true
                    
                    Row {
                        spacing: 6
                        Rectangle {
                            width: 12
                            height: 12
                            radius: 2
                            color: "#dcfce7"
                            border.color: "#22c55e"
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "新增"
                            font.pixelSize: 12
                            color: "#166534"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    
                    Row {
                        spacing: 6
                        Rectangle {
                            width: 12
                            height: 12
                            radius: 2
                            color: "#fee2e2"
                            border.color: "#ef4444"
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "删除"
                            font.pixelSize: 12
                            color: "#991b1b"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    
                    Row {
                        spacing: 6
                        Rectangle {
                            width: 12
                            height: 12
                            radius: 2
                            color: "#f3f4f6"
                            border.color: "#9ca3af"
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "未更改"
                            font.pixelSize: 12
                            color: "#6b7280"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Text {
                        text: diffDialogStaged ? "已暂存" : "未暂存"
                        font.pixelSize: 11
                        color: "#6b7280"
                    }
                }
                
                // Diff content
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: "#ffffff"
                    border.color: "#e5e7eb"
                    border.width: 1
                    clip: true
                    
                    ListView {
                        id: diffListView
                        anchors.fill: parent
                        anchors.margins: 1
                        model: diffDialogData
                        clip: true
                        
                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }
                        
                        delegate: Rectangle {
                            width: diffListView.width
                            height: diffLineText.implicitHeight + 8
                            color: {
                                if (modelData.type === "add") return "#dcfce7"
                                if (modelData.type === "delete") return "#fee2e2"
                                if (modelData.type === "header") return "#dbeafe"
                                return "transparent"
                            }
                            
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                anchors.topMargin: 4
                                anchors.bottomMargin: 4
                                spacing: 12
                                
                                // Line number
                                Text {
                                    width: 40
                                    text: modelData.lineNum > 0 ? modelData.lineNum : ""
                                    font.family: "Consolas, Monaco, monospace"
                                    font.pixelSize: 12
                                    color: "#9ca3af"
                                    horizontalAlignment: Text.AlignRight
                                }
                                
                                // +/- indicator
                                Text {
                                    width: 16
                                    text: {
                                        if (modelData.type === "add") return "+"
                                        if (modelData.type === "delete") return "-"
                                        return " "
                                    }
                                    font.family: "Consolas, Monaco, monospace"
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: {
                                        if (modelData.type === "add") return "#22c55e"
                                        if (modelData.type === "delete") return "#ef4444"
                                        return "#9ca3af"
                                    }
                                }
                                
                                // Content
                                Text {
                                    id: diffLineText
                                    width: parent.width - 76
                                    text: modelData.content || ""
                                    font.family: "Consolas, Monaco, monospace"
                                    font.pixelSize: 12
                                    color: {
                                        if (modelData.type === "add") return "#166534"
                                        if (modelData.type === "delete") return "#991b1b"
                                        if (modelData.type === "header") return "#1d4ed8"
                                        return "#374151"
                                    }
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                        }
                        
                        // Empty state
                        Text {
                            anchors.centerIn: parent
                            visible: diffDialogData.length === 0
                            text: "没有差异内容"
                            font.pixelSize: 14
                            color: "#9ca3af"
                        }
                    }
                }
                
                // Close button
                Row {
                    Layout.alignment: Qt.AlignRight
                    spacing: 12
                    
                    Text {
                        text: "关闭"
                        font.pixelSize: 13
                        color: closeDiffArea.containsMouse ? "#3b82f6" : "#6b7280"
                        
                        MouseArea {
                            id: closeDiffArea
                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: diffDialog.close()
                        }
                    }
                }
            }
        }
    }

    // Branch merge confirm dialog
    property string mergeBranchName: ""
    Dialog {
        id: mergeConfirmDialog
        title: ""
        anchors.centerIn: parent
        width: 450
        modal: true
        standardButtons: Dialog.NoButton
        padding: 20
        topPadding: 0
        bottomPadding: 40

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "确认合并"
            onCloseClicked: mergeConfirmDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 12

            Text {
                text: "确定要执行分支合并吗？"
                font.pixelSize: 14
                color: "#1a1a1a"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                height: 60
                radius: 6
                color: "#f0fdf4"

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: "将「" + mergeBranchName + "」分支"
                        font.pixelSize: 13
                        color: "#166534"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: "合并到「" + gitManager.currentBranch + "」"
                        font.pixelSize: 13
                        color: "#166534"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            Text {
                text: "💡 合并会将目标分支的更改整合到当前分支"
                font.pixelSize: 11
                color: "#6b7280"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: cancelMergeArea.containsMouse ? "#3b82f6" : "#6b7280"
                    
                    MouseArea {
                        id: cancelMergeArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mergeConfirmDialog.close()
                    }
                }

                ActionButton {
                    text: "确认合并"
                    icon: "\uf126"
                    fontFamily: fontAwesome.name
                    primary: true
                    onClicked: {
                        mergeConfirmDialog.close()
                        gitManager.mergeBranch(mergeBranchName)
                    }
                }
            }
        }
    }

    // Branch reset confirm dialog
    property string resetBranchName: ""
    property string deleteBranchName: ""
    Dialog {
        id: resetConfirmDialog
        title: ""
        anchors.centerIn: parent
        width: 450
        modal: true
        standardButtons: Dialog.NoButton
        padding: 20
        topPadding: 0
        bottomPadding: 40

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "确认替换"
            onCloseClicked: resetConfirmDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 12

            Text {
                text: "确定要执行分支替换吗？"
                font.pixelSize: 14
                color: "#1a1a1a"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                height: 60
                radius: 6
                color: "#fef2f2"

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: "将「" + resetBranchName + "」分支"
                        font.pixelSize: 13
                        color: "#991b1b"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: "替换到「" + gitManager.currentBranch + "」"
                        font.pixelSize: 13
                        color: "#991b1b"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            Text {
                text: "⚠️ 此操作会强制覆盖当前分支，未提交的更改将丢失"
                font.pixelSize: 11
                color: "#f59e0b"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: cancelResetArea.containsMouse ? "#3b82f6" : "#6b7280"
                    
                    MouseArea {
                        id: cancelResetArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: resetConfirmDialog.close()
                    }
                }

                ActionButton {
                    text: "确认替换"
                    icon: "\uf021"
                    fontFamily: fontAwesome.name
                    primary: true
                    onClicked: {
                        resetConfirmDialog.close()
                        gitManager.resetToBranch(resetBranchName)
                    }
                }
            }
        }
    }

    // Delete new file confirm dialog
    property string deleteNewFilePath: ""
    Dialog {
        id: deleteNewFileConfirmDialog
        title: ""
        anchors.centerIn: parent
        width: 450
        modal: true
        standardButtons: Dialog.NoButton
        padding: 20
        topPadding: 0
        bottomPadding: 40

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "确认删除"
            onCloseClicked: deleteNewFileConfirmDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 12

            Text {
                text: "确定要删除此新增文件吗？"
                font.pixelSize: 14
                color: "#1a1a1a"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 6
                color: "#fef2f2"

                Text {
                    anchors.centerIn: parent
                    text: deleteNewFilePath
                    font.pixelSize: 12
                    color: "#991b1b"
                    elide: Text.ElideMiddle
                    width: parent.width - 20
                }
            }

            Text {
                text: "⚠️ 此操作不可撤销，文件将被永久删除"
                font.pixelSize: 11
                color: "#f59e0b"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: cancelDeleteNewFileArea.containsMouse ? "#3b82f6" : "#6b7280"
                    
                    MouseArea {
                        id: cancelDeleteNewFileArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: deleteNewFileConfirmDialog.close()
                    }
                }

                ActionButton {
                    text: "确认删除"
                    icon: "\uf1f8"
                    fontFamily: fontAwesome.name
                    primary: true
                    onClicked: {
                        deleteNewFileConfirmDialog.close()
                        gitManager.deleteNewFile(deleteNewFilePath)
                    }
                }
            }
        }
    }

    // Discard all changes confirm dialog
    Dialog {
        id: discardAllConfirmDialog
        title: ""
        anchors.centerIn: parent
        width: 450
        modal: true
        standardButtons: Dialog.NoButton
        padding: 20
        topPadding: 0
        bottomPadding: 40

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "确认撤销"
            onCloseClicked: discardAllConfirmDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 12

            Text {
                text: "确定要撤销所有更改吗？"
                font.pixelSize: 14
                color: "#1a1a1a"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 6
                color: "#fef2f2"

                Text {
                    anchors.centerIn: parent
                    text: gitManager.changedFiles.length + " 个文件将被撤销"
                    font.pixelSize: 13
                    color: "#991b1b"
                }
            }

            Text {
                text: "⚠️ 此操作不可撤销，所有未暂存的更改将丢失"
                font.pixelSize: 11
                color: "#f59e0b"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: cancelDiscardAllArea.containsMouse ? "#3b82f6" : "#6b7280"
                    
                    MouseArea {
                        id: cancelDiscardAllArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: discardAllConfirmDialog.close()
                    }
                }

                ActionButton {
                    text: "确认撤销"
                    icon: "\uf2ea"
                    fontFamily: fontAwesome.name
                    primary: true
                    onClicked: {
                        discardAllConfirmDialog.close()
                        gitManager.setBulkOperationMode(true)
                        gitManager.discardAllChanges()
                    }
                }
            }
        }
    }

    // Branch delete confirm dialog
    Dialog {
        id: deleteBranchConfirmDialog
        title: ""
        anchors.centerIn: parent
        width: 450
        modal: true
        standardButtons: Dialog.NoButton
        padding: 20
        topPadding: 0
        bottomPadding: 40

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "确认删除"
            onCloseClicked: deleteBranchConfirmDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 12

            Text {
                text: "确定要删除此分支吗？"
                font.pixelSize: 14
                color: "#1a1a1a"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 6
                color: "#fef2f2"

                Text {
                    anchors.centerIn: parent
                    text: "「" + deleteBranchName + "」"
                    font.pixelSize: 13
                    color: "#991b1b"
                }
            }

            Text {
                text: "⚠️ 删除后分支将无法恢复"
                font.pixelSize: 11
                color: "#f59e0b"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: cancelDeleteBranchArea.containsMouse ? "#3b82f6" : "#6b7280"
                    
                    MouseArea {
                        id: cancelDeleteBranchArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: deleteBranchConfirmDialog.close()
                    }
                }

                ActionButton {
                    text: "确认删除"
                    icon: "\uf1f8"
                    fontFamily: fontAwesome.name
                    primary: true
                    onClicked: {
                        deleteBranchConfirmDialog.close()
                        gitManager.deleteBranch(deleteBranchName)
                    }
                }
            }
        }
    }

    // Clean confirm dialog
    property string cleanConfirmPath: ""
    Dialog {
        id: cleanConfirmDialog
        title: ""
        anchors.centerIn: parent
        width: 450
        modal: true
        standardButtons: Dialog.NoButton
        padding: 20
        topPadding: 0
        bottomPadding: 40

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "确认清理"
            onCloseClicked: cleanConfirmDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 12

            Text {
                text: "确定要从 Git 历史中删除此文件吗？"
                font.pixelSize: 14
                color: "#1a1a1a"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 6
                color: "#fef2f2"

                Text {
                    anchors.centerIn: parent
                    text: cleanConfirmPath
                    font.pixelSize: 12
                    color: "#991b1b"
                    elide: Text.ElideMiddle
                    width: parent.width - 20
                }
            }

            Text {
                text: "⚠️ 此操作不可撤销，清理后需要强制推送"
                font.pixelSize: 11
                color: "#f59e0b"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: cancelCleanArea.containsMouse ? "#3b82f6" : "#6b7280"
                    
                    MouseArea {
                        id: cancelCleanArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: cleanConfirmDialog.close()
                    }
                }

                ActionButton {
                    text: "确认清理"
                    icon: "\uf1f8"
                    fontFamily: fontAwesome.name
                    primary: true
                    onClicked: {
                        cleanConfirmDialog.close()
                        largeFilesDialog.close()
                        gitManager.removeLargeFileFromHistory(cleanConfirmPath)
                    }
                }
            }
        }
    }

    // Store last repo path for "return to repo" feature
    property string lastRepoPath: ""

    ColumnLayout {
        parent: contentArea
        anchors.fill: parent
        anchors.margins: 16
        anchors.topMargin: 8
        anchors.rightMargin: 32
        spacing: 16

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Logo/Title with User Info - wrapped in Column for back button
            ColumnLayout {
                spacing: 4

                // Back buttons (above avatar)
                Item {
                    visible: gitManager.isValidRepo || lastRepoPath !== ""
                    Layout.preferredWidth: backBtnRow.width
                    Layout.preferredHeight: 28

                    Row {
                        id: backBtnRow
                        spacing: 8

                        // Back to home button (visible when repo is open)
                        Rectangle {
                            visible: gitManager.isValidRepo
                            width: 80
                            height: 28
                            radius: 14
                            color: "#ffffff"
                            border.color: "#e5e7eb"
                            border.width: 1
                            clip: true

                            // Text (behind the sliding background)
                            Text {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: 8
                                text: "主页"
                                font.pixelSize: 11
                                font.bold: true
                                color: "#1a1a1a"
                                z: 1
                            }

                            // Sliding green background (on top)
                            Rectangle {
                                width: backHomeHover.hovered ? parent.width - 6 : 24
                                height: 22
                                radius: 11
                                color: "#4ade80"
                                anchors.left: parent.left
                                anchors.leftMargin: 3
                                anchors.verticalCenter: parent.verticalCenter
                                z: 2

                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                                // Arrow and text inside sliding background
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    
                                    Text {
                                        text: "\uf060"
                                        font.family: fontAwesome.name
                                        font.pixelSize: 11
                                        color: "#000000"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    
                                    Text {
                                        visible: backHomeHover.hovered
                                        text: "主页"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: "#000000"
                                        anchors.verticalCenter: parent.verticalCenter
                                        opacity: backHomeHover.hovered ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                    }
                                }
                            }

                            HoverHandler {
                                id: backHomeHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: {
                                    lastRepoPath = gitManager.repoPath
                                    gitManager.repoPath = ""
                                }
                            }
                        }

                        // Close repo button (visible when repo is open)
                        Rectangle {
                            visible: gitManager.isValidRepo
                            width: 100
                            height: 28
                            radius: 14
                            color: "#ffffff"
                            border.color: "#e5e7eb"
                            border.width: 1
                            clip: true

                            // Text (behind the sliding background)
                            Text {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: 8
                                text: "关闭仓库"
                                font.pixelSize: 11
                                font.bold: true
                                color: "#1a1a1a"
                                z: 1
                            }

                            // Sliding red background (on top)
                            Rectangle {
                                width: closeRepoHover.hovered ? parent.width - 6 : 24
                                height: 22
                                radius: 11
                                color: "#f87171"
                                anchors.left: parent.left
                                anchors.leftMargin: 3
                                anchors.verticalCenter: parent.verticalCenter
                                z: 2

                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                                // Icon and text inside sliding background
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    
                                    Text {
                                        text: "\uf00d"
                                        font.family: fontAwesome.name
                                        font.pixelSize: 11
                                        color: "#ffffff"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    
                                    Text {
                                        visible: closeRepoHover.hovered
                                        text: "关闭仓库"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: "#ffffff"
                                        anchors.verticalCenter: parent.verticalCenter
                                        opacity: closeRepoHover.hovered ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                    }
                                }
                            }

                            HoverHandler {
                                id: closeRepoHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: {
                                    lastRepoPath = ""  // Don't save, can't return
                                    gitManager.repoPath = ""
                                }
                            }
                        }

                        // Return to repo button (visible on home when last repo exists)
                        Rectangle {
                            visible: !gitManager.isValidRepo && lastRepoPath !== ""
                            width: 90
                            height: 28
                            radius: 14
                            color: "#ffffff"
                            border.color: "#e5e7eb"
                            border.width: 1
                            clip: true

                            // Text (behind the sliding background)
                            Text {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: -8
                                text: "返回仓库"
                                font.pixelSize: 11
                                font.bold: true
                                color: "#1a1a1a"
                                z: 1
                            }

                            // Sliding blue background (on top)
                            Rectangle {
                                width: backRepoHover.hovered ? parent.width - 6 : 24
                                height: 22
                                radius: 11
                                color: "#60a5fa"
                                anchors.right: parent.right
                                anchors.rightMargin: 3
                                anchors.verticalCenter: parent.verticalCenter
                                z: 2

                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                                // Arrow and text inside sliding background
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    layoutDirection: Qt.RightToLeft
                                    
                                    Text {
                                        text: "\uf061"
                                        font.family: fontAwesome.name
                                        font.pixelSize: 11
                                        color: "#ffffff"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    
                                    Text {
                                        visible: backRepoHover.hovered
                                        text: "返回仓库"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: "#ffffff"
                                        anchors.verticalCenter: parent.verticalCenter
                                        opacity: backRepoHover.hovered ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                    }
                                }
                            }

                            HoverHandler {
                                id: backRepoHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: {
                                    gitManager.repoPath = lastRepoPath
                                }
                            }
                        }
                    }
                }

                // User info row
                RowLayout {
                    spacing: 10

                    // User Avatar with hover animation
                    Item {
                        width: 48
                        height: 48

                        Rectangle {
                            id: avatarBg
                            anchors.centerIn: parent
                            width: avatarHover.hovered ? 46 : 42
                            height: avatarHover.hovered ? 46 : 42
                            radius: width / 2
                        color: {
                            var name = gitManager.userName || "U"
                            var hash = 0
                            for (var i = 0; i < name.length; i++) {
                                hash = name.charCodeAt(i) + ((hash << 5) - hash)
                            }
                            var colors = ["#4a90d9", "#52c41a", "#faad14", "#ff4d4f", "#7c5cbf", "#13c2c2", "#eb2f96"]
                            return colors[Math.abs(hash) % colors.length]
                        }

                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                        // Glow effect on hover
                        layer.enabled: avatarHover.hovered
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: avatarBg.color
                            shadowHorizontalOffset: 0
                            shadowVerticalOffset: 0
                            shadowBlur: 0.8
                        }

                        Text {
                            anchors.centerIn: parent
                            text: gitManager.userName ? gitManager.userName.charAt(0).toUpperCase() : "?"
                            font.pixelSize: avatarHover.hovered ? 20 : 18
                            font.bold: true
                            color: "#ffffff"

                            Behavior on font.pixelSize { NumberAnimation { duration: 200 } }
                        }

                        // Status indicator
                        Rectangle {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            width: 12
                            height: 12
                            radius: 6
                            color: gitManager.userName ? "#52c41a" : "#faad14"
                            border.color: "#ffffff"
                            border.width: 2
                        }
                    }

                    HoverHandler {
                        id: avatarHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: userConfigDialog.open()
                    }
                }

                // User Info
                ColumnLayout {
                    spacing: 1

                    // Label
                    Text {
                        text: "当前用户"
                        font.pixelSize: 10
                        color: theme.textDim
                    }

                    // Username with settings
                    RowLayout {
                        spacing: 4

                        Text {
                            text: gitManager.userName || "未配置"
                            font.pixelSize: 14
                            font.bold: true
                            color: gitManager.userName ? theme.text : theme.warning
                        }

                        Text {
                            text: "\uf013"
                            font.family: fontAwesome.name
                            font.pixelSize: 10
                            color: theme.textDim
                            opacity: settingsHover.hovered ? 1 : 0.6

                            HoverHandler { id: settingsHover }
                            
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: userConfigDialog.open()
                            }
                        }
                    }

                    // Email
                    Text {
                        text: gitManager.userEmail || "点击配置"
                        font.pixelSize: 11
                        color: theme.textDim
                        
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: gitManager.userEmail ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: if (!gitManager.userEmail) userConfigDialog.open()
                        }
                    }
                }
                }  // End of user info RowLayout
            }  // End of ColumnLayout wrapper

            Item { Layout.fillWidth: true }

            // Branch label + selector group
            Row {
                visible: gitManager.isValidRepo
                spacing: 8
                Layout.alignment: Qt.AlignVCenter
                
                // Branch label
                Text {
                    text: "当前分支"
                    font.pixelSize: 12
                    color: theme.textDim
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Branch selector - fancy glow style
                Item {
                    width: 140
                    height: 42
                    
                    // Main button container
                    Rectangle {
                        id: branchBtn
                        anchors.fill: parent
                        radius: 10
                        color: "#262626"
                        border.color: branchBtnArea.hovered ? "#fda4af" : "#404040"
                        border.width: 1
                        clip: true

                        Behavior on border.color { ColorAnimation { duration: 300 } }

                        // Violet glow circle (top right)
                        Rectangle {
                            id: violetGlow
                            width: 24
                            height: 24
                            radius: 12
                            color: "#8b5cf6"
                            x: parent.width - 30
                            y: 4
                            opacity: 0.8
                            
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blur: 1.0
                                blurMax: 32
                            }

                            // Hover animation
                            Behavior on x { NumberAnimation { duration: 500 } }
                            Behavior on y { NumberAnimation { duration: 500 } }
                        }

                        // Rose glow circle
                        Rectangle {
                            id: roseGlow
                            width: 36
                            height: 36
                            radius: 18
                            color: "#fda4af"
                            x: parent.width - 50
                            y: 8
                            opacity: 0.6
                            
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blur: 1.0
                                blurMax: 32
                            }

                            // Hover animation
                            Behavior on x { NumberAnimation { duration: 500 } }
                            Behavior on y { NumberAnimation { duration: 500 } }
                        }

                        // Content
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            z: 10
                            
                            Text {
                                text: "\uf126"
                                font.family: fontAwesome.name
                                font.pixelSize: 12
                                color: branchBtnArea.hovered ? "#fda4af" : "#f5f5f5"
                                anchors.verticalCenter: parent.verticalCenter
                                
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                            
                            Text {
                                text: gitManager.currentBranch || "main"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: branchBtnArea.hovered ? "#fda4af" : "#f5f5f5"
                                elide: Text.ElideRight
                                width: 80
                                anchors.verticalCenter: parent.verticalCenter
                                
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                        }

                        // Hover handler
                        HoverHandler {
                            id: branchBtnArea
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: branchMenu.open()
                        }

                        // Hover state changes
                        states: State {
                            name: "hovered"
                            when: branchBtnArea.hovered
                            PropertyChanges { target: violetGlow; x: branchBtn.width - 20; y: branchBtn.height - 16 }
                            PropertyChanges { target: roseGlow; x: branchBtn.width - 70; y: -8 }
                        }
                    }

                    Menu {
                        id: branchMenu
                        y: branchBtn.height + 4

                        Repeater {
                            model: gitManager.branches
                            MenuItem {
                                text: modelData
                                onTriggered: gitManager.switchBranch(modelData)
                            }
                        }
                    }
                    
                    ToolTip.visible: branchBtnArea.hovered
                    ToolTip.text: gitManager.currentBranch
                    ToolTip.delay: 500
                }
            }

            // Neumorphism button group container
            Rectangle {
                id: buttonGroup
                Layout.preferredWidth: buttonRow.width + 20
                Layout.preferredHeight: 54
                radius: 16
                
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#e6e6e6" }
                    GradientStop { position: 1.0; color: "#ffffff" }
                }

                // Neumorphism shadows
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#00000026"
                    shadowHorizontalOffset: 5
                    shadowVerticalOffset: 5
                    shadowBlur: 0.4
                }

                Row {
                    id: buttonRow
                    anchors.centerIn: parent
                    spacing: 8

                    // Refresh button
                    IconButton {
                        icon: "\uf2f1"
                        fontFamily: fontAwesome.name
                        tooltip: "刷新状态"
                        onClicked: gitManager.refresh()
                        rotating: gitManager.isLoading
                    }

                    // Abort merge button
                    IconButton {
                        visible: gitManager.isValidRepo
                        icon: "\uf00d"
                        fontFamily: fontAwesome.name
                        tooltip: "取消合并"
                        onClicked: gitManager.abortMerge()
                    }

                    // Clone button
                    IconButton {
                        icon: "\uf019"
                        fontFamily: fontAwesome.name
                        tooltip: "克隆仓库"
                        onClicked: cloneDialog.open()
                    }

                    // Branch management button
                    IconButton {
                        visible: gitManager.isValidRepo
                        icon: "\uf126"
                        fontFamily: fontAwesome.name
                        tooltip: "分支管理"
                        onClicked: branchDialog.open()
                    }

                    // File browser button - 远程文件浏览
                    IconButton {
                        visible: gitManager.isValidRepo
                        icon: "\uf0c2"
                        fontFamily: fontAwesome.name
                        tooltip: "远程文件"
                        onClicked: {
                            gitManager.loadRemoteFiles("")
                            remoteFileBrowserDrawer.open()
                        }
                    }

                    // Commit history button
                    IconButton {
                        visible: gitManager.isValidRepo
                        icon: "\uf1da"
                        fontFamily: fontAwesome.name
                        tooltip: "提交历史"
                        onClicked: {
                            gitManager.loadCommitHistory()
                            commitHistoryDrawer.open()
                        }
                    }

                    // Clean large files button
                    IconButton {
                        visible: gitManager.isValidRepo
                        icon: "\uf1f8"
                        fontFamily: fontAwesome.name
                        tooltip: "清理大文件"
                        onClicked: {
                            largeFilesDialog.open()
                            gitManager.findLargeFiles(50)
                        }
                    }
                }
            }
        }

        // Repository selector with gradient border and hover animation
        Item {
            Layout.fillWidth: true
            height: 60

            // Hover scale effect
            scale: repoHover.hovered ? 1.02 : 1.0
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

            // Static gradient border
            Rectangle {
                id: repoBorder
                anchors.fill: parent
                radius: 30
                
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#ff9a9e" }
                    GradientStop { position: 0.25; color: "#a8edea" }
                    GradientStop { position: 0.5; color: "#ffecd2" }
                    GradientStop { position: 0.75; color: "#fcb69f" }
                    GradientStop { position: 1.0; color: "#ff9a9e" }
                }

                // Glow effect on hover
                layer.enabled: repoHover.hovered
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#fcb69f"
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 4
                    shadowBlur: 0.6
                }
            }

            // Inner white card
            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: 27
                color: repoHover.hovered ? "#fffbf7" : "#ffffff"

                Behavior on color { ColorAnimation { duration: 200 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    // Folder icon with gradient background
                    Rectangle {
                        id: folderIcon
                        width: repoHover.hovered ? 40 : 36
                        height: repoHover.hovered ? 40 : 36
                        radius: 10
                        
                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#ffecd2" }
                            GradientStop { position: 1.0; color: "#fcb69f" }
                        }
                        
                        Text {
                            anchors.centerIn: parent
                            text: "\uf07b"
                            font.family: fontAwesome.name
                            font.pixelSize: repoHover.hovered ? 18 : 16
                            color: "#ffffff"

                            Behavior on font.pixelSize { NumberAnimation { duration: 200 } }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        
                        Text {
                            text: gitManager.repoPath || "选择一个仓库..."
                            font.pixelSize: 13
                            font.bold: gitManager.repoPath ? true : false
                            color: gitManager.repoPath ? "#1a1a1a" : "#9ca3af"
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                        
                        RowLayout {
                            visible: gitManager.isValidRepo
                            spacing: 12

                            Text {
                                text: gitManager.stagedFiles.length + " 已暂存, " + gitManager.changedFiles.length + " 已更改  (点击刷新按钮更新)"
                                font.pixelSize: 11
                                color: "#6b7280"
                            }

                            Text {
                                visible: gitManager.lastCommitTime !== ""
                                text: "最后提交: " + gitManager.lastCommitTime
                                font.pixelSize: 10
                                color: "#9ca3af"
                            }
                        }
                    }

                    // Action buttons row
                    Row {
                        spacing: 8

                        // Open folder button (only when repo is valid)
                        Rectangle {
                            visible: gitManager.isValidRepo
                            width: 32
                            height: 28
                            radius: 14
                            color: openFolderHover.hovered ? "#f59e0b" : "#fef3c7"

                            Behavior on color { ColorAnimation { duration: 200 } }

                            Text {
                                anchors.centerIn: parent
                                text: "\uf07c"
                                font.family: fontAwesome.name
                                font.pixelSize: 12
                                color: openFolderHover.hovered ? "#ffffff" : "#f59e0b"

                                Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            HoverHandler {
                                id: openFolderHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: Qt.openUrlExternally("file:///" + gitManager.repoPath)
                            }

                            ToolTip.visible: openFolderHover.hovered
                            ToolTip.text: "打开仓库文件夹"
                            ToolTip.delay: 500
                        }

                        // Browse button with hover effect
                        Rectangle {
                            width: browseLabel.width + 16
                            height: 28
                            radius: 14
                            color: browseBtnHover.hovered ? "#3b82f6" : "transparent"

                            Behavior on color { ColorAnimation { duration: 200 } }

                            Text {
                                id: browseLabel
                                anchors.centerIn: parent
                                text: "浏览"
                                font.pixelSize: 13
                                font.bold: true
                                color: browseBtnHover.hovered ? "#ffffff" : "#3b82f6"

                                Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            HoverHandler {
                                id: browseBtnHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: folderDialog.open()
                            }
                        }
                    }
                }

                HoverHandler {
                    id: repoHover
                }
            }
        }

        // Main content area with keyboard focus
        FocusScope {
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: true
            visible: gitManager.isValidRepo

            Keys.onPressed: (event) => {
                // Ctrl+A - Select all files in current panel
                if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_A) {
                    if (changedFilesPanel.visible) {
                        changedFilesPanel.selectAll()
                    } else if (stagedFilesPanel.visible) {
                        stagedFilesPanel.selectAll()
                    }
                    event.accepted = true
                }
                // Space - Stage/unstage selected files
                else if (event.key === Qt.Key_Space) {
                    if (changedFilesPanel.hasSelection) {
                        changedFilesPanel.stageSelected()
                    } else if (stagedFilesPanel.hasSelection) {
                        stagedFilesPanel.unstageSelected()
                    }
                    event.accepted = true
                }
                // Ctrl+Enter - Quick commit
                else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_Return) {
                    if (gitManager.stagedFiles.length > 0) {
                        commitDialog.open()
                    }
                    event.accepted = true
                }
                // F5 - Refresh
                else if (event.key === Qt.Key_F5) {
                    gitManager.refresh()
                    event.accepted = true
                }
                // Escape - Clear selection
                else if (event.key === Qt.Key_Escape) {
                    changedFilesPanel.clearSelection()
                    stagedFilesPanel.clearSelection()
                    event.accepted = true
                }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 16

            // Changed files panel
            FilePanel {
                id: changedFilesPanel
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "已更改文件"
                subtitle: gitManager.changedFiles.length + " 个文件"
                files: gitManager.changedFiles
                emptyText: "没有检测到更改"
                actionText: "暂存"
                actionAllText: "全部暂存"
                discardAllText: "全部撤销"
                fontAwesomeName: fontAwesome.name
                onFileAction: (path) => gitManager.stageFile(path)
                onBatchAction: (paths) => gitManager.stageFiles(paths)
                onAllAction: {
                    gitManager.setBulkOperationMode(true)
                    gitManager.stageAll()
                }
                onDiscardAllAction: discardAllConfirmDialog.open()
                showDiscard: true
                onDiscardFile: (path) => gitManager.discardChanges(path)
                onDeleteNewFile: (path) => {
                    deleteNewFilePath = path
                    deleteNewFileConfirmDialog.open()
                }
                onFileClicked: (path, staged) => {
                    diffDialogPath = path
                    diffDialogStaged = staged
                    diffDialogData = gitManager.getFileDiff(path, staged)
                    diffDialog.open()
                }
                onOpenFileLocation: (path) => gitManager.openFileLocation(path)
                onAddToGitignore: (pattern) => gitManager.addToGitignore(pattern)
                onOpenGitignoreManager: gitignoreDialog.open()
            }

            // Staged files panel
            FilePanel {
                id: stagedFilesPanel
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "已暂存文件"
                subtitle: gitManager.stagedFiles.length + " 个文件"
                files: gitManager.stagedFiles
                emptyText: "没有已暂存的文件"
                actionText: "取消暂存"
                actionAllText: "全部取消"
                isStaged: true
                fontAwesomeName: fontAwesome.name
                onFileAction: (path) => gitManager.unstageFile(path)
                onBatchAction: (paths) => gitManager.unstageFiles(paths)
                onAllAction: {
                    gitManager.setBulkOperationMode(true)
                    gitManager.unstageAll()
                }
                onFileClicked: (path, staged) => {
                    diffDialogPath = path
                    diffDialogStaged = staged
                    diffDialogData = gitManager.getFileDiff(path, staged)
                    diffDialog.open()
                }
                onOpenFileLocation: (path) => gitManager.openFileLocation(path)
                onOpenGitignoreManager: gitignoreDialog.open()
            }
        }
        }

        // Empty state
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !gitManager.isValidRepo && gitManager.repoPath !== ""
            color: "transparent"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 16

                Text {
                    text: "\uf071"
                    font.family: fontAwesome.name
                    font.pixelSize: 48
                    color: theme.warning
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "不是 Git 仓库"
                    font.pixelSize: 18
                    font.bold: true
                    color: theme.text
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "请选择一个包含 Git 仓库的文件夹"
                    font.pixelSize: 13
                    color: theme.textDim
                    Layout.alignment: Qt.AlignHCenter
                }

                // Return to home button
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                    width: backHomeRow.width + 24
                    height: 36
                    radius: 18
                    color: backHomeBtnHover.hovered ? "#4ade80" : "#f0fdf4"
                    border.color: "#4ade80"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Row {
                        id: backHomeRow
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "\uf060"
                            font.family: fontAwesome.name
                            font.pixelSize: 12
                            color: backHomeBtnHover.hovered ? "#ffffff" : "#16a34a"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "返回主页"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: backHomeBtnHover.hovered ? "#ffffff" : "#16a34a"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    HoverHandler {
                        id: backHomeBtnHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: gitManager.repoPath = ""
                    }
                }
            }
        }

        // Welcome state
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: gitManager.repoPath === ""
            color: "transparent"

            // Welcome content - fixed upper center
            ColumnLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 40
                spacing: 16

                Text {
                    text: "\uf09b"
                    font.family: fontAwesome.name
                    font.pixelSize: 48
                    color: theme.primary
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "欢迎使用 Git 推送工具"
                    font.pixelSize: 18
                    font.bold: true
                    color: theme.text
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "选择一个仓库开始使用，支持拖拽文件夹"
                    font.pixelSize: 13
                    color: theme.textDim
                    Layout.alignment: Qt.AlignHCenter
                }

                // Buttons in a row
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                    spacing: 16

                    ActionButton {
                        text: "打开仓库"
                        icon: "\uf07b"
                        fontFamily: fontAwesome.name
                        primary: true
                        onClicked: folderDialog.open()
                    }

                    ActionButton {
                        text: "克隆仓库"
                        icon: "\uf019"
                        fontFamily: fontAwesome.name
                        onClicked: cloneDialog.open()
                    }
                }
            }

            // Recent repos section - fixed at bottom
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 30
                width: 320
                height: 160
                visible: gitManager.recentReposList.length > 0

                Column {
                    id: recentReposContainer
                    anchors.fill: parent
                    spacing: 8

                    // Header
                    Row {
                        id: recentReposHeader
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "\uf1da"
                            font.family: fontAwesome.name
                            font.pixelSize: 12
                            color: theme.textDim
                        }
                        Text {
                            text: "最近打开"
                            font.pixelSize: 12
                            font.bold: true
                            color: theme.textDim
                        }
                        Item { width: 1; Layout.fillWidth: true }
                        Text {
                            text: "清空"
                            font.pixelSize: 11
                            color: clearHover.hovered ? theme.error : theme.textDim
                            
                            MouseArea {
                                id: clearHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: gitManager.clearRecentRepos()
                            }
                        }
                    }

                    // Recent repos list with scroll - fixed height
                    ListView {
                        id: recentReposList
                        width: parent.width
                        height: parent.height - recentReposHeader.height - 8
                        model: gitManager.recentReposList
                        spacing: 4
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            policy: recentReposList.contentHeight > recentReposList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                            width: 6
                        }

                        delegate: Rectangle {
                            width: recentReposList.width - 10
                            height: 40
                            radius: 8
                            color: recentItemHover.hovered ? (isDarkMode ? "#3a3a3a" : "#f0f0f0") : (isDarkMode ? "#2a2a2a" : "#ffffff")
                            border.color: recentItemHover.hovered ? theme.primary : theme.border
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                Text {
                                    text: "\uf07b"
                                    font.family: fontAwesome.name
                                    font.pixelSize: 14
                                    color: theme.primary
                                }

                                Text {
                                    text: modelData.split('/').pop() || modelData.split('\\').pop()
                                    font.pixelSize: 13
                                    color: theme.text
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }

                                // Remove button
                                Rectangle {
                                    width: 20
                                    height: 20
                                    radius: 4
                                    color: removeHover.hovered ? "#fee2e2" : "transparent"
                                    visible: recentItemHover.hovered

                                    Text {
                                        anchors.centerIn: parent
                                        text: "\uf00d"
                                        font.family: fontAwesome.name
                                        font.pixelSize: 10
                                        color: "#ef4444"
                                    }

                                    HoverHandler { id: removeHover }
                                    TapHandler {
                                        onTapped: gitManager.removeRecentRepo(modelData)
                                    }
                                }
                            }

                            HoverHandler { id: recentItemHover }
                            TapHandler {
                                onTapped: gitManager.repoPath = modelData
                            }

                            ToolTip.visible: recentItemHover.hovered
                            ToolTip.delay: 500
                            ToolTip.text: modelData
                        }
                    }
                }
            }

            // Install Git button - bottom left corner
            Item {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 20
                width: gitInstallCol.width
                height: gitInstallCol.height

                Column {
                    id: gitInstallCol
                    spacing: 8

                    // Git logo with hover animation
                    Item {
                        width: 64
                        height: 64
                        anchors.horizontalCenter: parent.horizontalCenter

                        Image {
                            id: gitLogo
                            anchors.centerIn: parent
                            source: "images/git.png"
                            width: gitLogoHover.hovered ? 58 : 50
                            height: gitLogoHover.hovered ? 58 : 50
                            fillMode: Image.PreserveAspectFit
                            
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        }

                        // Glow effect on hover
                        Rectangle {
                            anchors.centerIn: parent
                            width: gitLogoHover.hovered ? 70 : 0
                            height: gitLogoHover.hovered ? 70 : 0
                            radius: width / 2
                            color: "transparent"
                            border.color: "#f05033"
                            border.width: 2
                            opacity: gitLogoHover.hovered ? 0.6 : 0
                            z: -1
                            
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }

                        HoverHandler {
                            id: gitLogoHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: gitManager.runGitInstaller()
                        }

                        ToolTip.visible: gitLogoHover.hovered
                        ToolTip.delay: 300
                        ToolTip.text: "点击安装 Git"
                    }

                    // Hint text
                    Text {
                        text: "没有安装 Git？"
                        font.pixelSize: 11
                        color: "#666666"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: "点击上方图标安装"
                        font.pixelSize: 10
                        color: "#999999"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            // Social links - bottom right corner
            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 20
                spacing: 10

                // GitHub button
                Rectangle {
                    id: homeGithubBtn
                    width: 42
                    height: 42
                    radius: 10
                    color: homeGithubHover.hovered ? "#24292e" : "#f6f8fa"
                    border.color: homeGithubHover.hovered ? "#6e40c9" : "#d0d7de"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    // GitHub icon
                    Image {
                        anchors.centerIn: parent
                        source: "images/github.com-favicon.ico"
                        width: 22
                        height: 22
                        fillMode: Image.PreserveAspectFit
                        visible: !homeGithubHover.hovered
                    }
                    
                    // White text on hover
                    Text {
                        anchors.centerIn: parent
                        text: "GitHub"
                        font.pixelSize: 10
                        font.bold: true
                        color: "#ffffff"
                        visible: homeGithubHover.hovered
                    }

                    layer.enabled: homeGithubHover.hovered
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#6e40c9"
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0
                        shadowBlur: 0.6
                    }

                    HoverHandler {
                        id: homeGithubHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: Qt.openUrlExternally("https://github.com/likeLBY")
                    }

                    ToolTip.visible: homeGithubHover.hovered
                    ToolTip.delay: 300
                    ToolTip.text: "GitHub"
                }

                // Gitee button
                Rectangle {
                    id: homeGiteeBtn
                    width: 42
                    height: 42
                    radius: 10
                    color: homeGiteeHover.hovered ? "#c71d23" : "#f6f8fa"
                    border.color: homeGiteeHover.hovered ? "#c71d23" : "#d0d7de"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    // Gitee icon
                    Image {
                        anchors.centerIn: parent
                        source: "images/gitee.com-favicon.ico"
                        width: 22
                        height: 22
                        fillMode: Image.PreserveAspectFit
                        visible: !homeGiteeHover.hovered
                    }
                    
                    // White text on hover
                    Text {
                        anchors.centerIn: parent
                        text: "Gitee"
                        font.pixelSize: 10
                        font.bold: true
                        color: "#ffffff"
                        visible: homeGiteeHover.hovered
                    }

                    layer.enabled: homeGiteeHover.hovered
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#c71d23"
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0
                        shadowBlur: 0.6
                    }

                    HoverHandler {
                        id: homeGiteeHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: Qt.openUrlExternally("https://gitee.com/likeLBY")
                    }

                    ToolTip.visible: homeGiteeHover.hovered
                    ToolTip.delay: 300
                    ToolTip.text: "Gitee"
                }
            }
        }

        // Commit section
        Rectangle {
            Layout.fillWidth: true
            height: commitLayout.height + 24
            radius: 12
            color: theme.surface
            visible: gitManager.isValidRepo

            ColumnLayout {
                id: commitLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 12

                // Simple gradient border input
                Rectangle {
                    id: inputWrapper
                    Layout.fillWidth: true
                    height: 56
                    radius: 28
                    
                    // Gradient background (border effect)
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "#e3d5ff" }  // 紫色
                        GradientStop { position: 1.0; color: "#ffe7e7" }  // 粉色
                    }
                    
                    // Soft shadow
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#00000013"
                        shadowHorizontalOffset: 2
                        shadowVerticalOffset: 2
                        shadowBlur: 0.3
                    }
                    
                    // Inner white input area
                    Rectangle {
                        id: inputInner
                        anchors.centerIn: parent
                        width: parent.width - 6
                        height: parent.height - 6
                        radius: 25
                        color: "#ffffff"
                        
                        TextArea {
                            id: commitInput
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            anchors.topMargin: 8
                            anchors.bottomMargin: 8
                            placeholderText: "输入提交描述..."
                            placeholderTextColor: "#aaaaaa"
                            color: "#131313"
                            font.pixelSize: 13
                            font.letterSpacing: 0.8
                            wrapMode: TextArea.Wrap
                            background: null
                            
                            // Orange caret
                            cursorDelegate: Rectangle {
                                width: 2
                                color: "#ff5100"
                            }
                        }
                    }
                }

                // Action buttons
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // Social links - GitHub & Gitee (moved to left)
                    Row {
                        spacing: 10

                        // GitHub button
                        Rectangle {
                            id: githubBtn
                            width: 42
                            height: 42
                            radius: 10
                            color: githubHover.hovered ? "#24292e" : "#f6f8fa"
                            border.color: githubHover.hovered ? "#6e40c9" : "#d0d7de"
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            // GitHub icon
                            Image {
                                anchors.centerIn: parent
                                source: "images/github.com-favicon.ico"
                                width: 22
                                height: 22
                                fillMode: Image.PreserveAspectFit
                                visible: !githubHover.hovered
                            }
                            
                            // White text on hover
                            Text {
                                anchors.centerIn: parent
                                text: "GitHub"
                                font.pixelSize: 10
                                font.bold: true
                                color: "#ffffff"
                                visible: githubHover.hovered
                            }

                            // Glow effect on hover
                            layer.enabled: githubHover.hovered
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: "#6e40c9"
                                shadowHorizontalOffset: 0
                                shadowVerticalOffset: 0
                                shadowBlur: 0.6
                            }

                            HoverHandler {
                                id: githubHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: Qt.openUrlExternally("https://github.com/likeLBY")
                            }

                            ToolTip.visible: githubHover.hovered
                            ToolTip.delay: 300
                            ToolTip.text: "GitHub"
                        }

                        // Gitee button
                        Rectangle {
                            id: giteeBtn
                            width: 42
                            height: 42
                            radius: 10
                            color: giteeHover.hovered ? "#c71d23" : "#f6f8fa"
                            border.color: giteeHover.hovered ? "#c71d23" : "#d0d7de"
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            // Gitee icon
                            Image {
                                anchors.centerIn: parent
                                source: "images/gitee.com-favicon.ico"
                                width: 22
                                height: 22
                                fillMode: Image.PreserveAspectFit
                                visible: !giteeHover.hovered
                            }
                            
                            // White icon on hover (use text as fallback)
                            Text {
                                anchors.centerIn: parent
                                text: "Gitee"
                                font.pixelSize: 10
                                font.bold: true
                                color: "#ffffff"
                                visible: giteeHover.hovered
                            }

                            // Glow effect on hover
                            layer.enabled: giteeHover.hovered
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: "#c71d23"
                                shadowHorizontalOffset: 0
                                shadowVerticalOffset: 0
                                shadowBlur: 0.6
                            }

                            HoverHandler {
                                id: giteeHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: Qt.openUrlExternally("https://gitee.com/likeLBY")
                            }

                            ToolTip.visible: giteeHover.hovered
                            ToolTip.delay: 300
                            ToolTip.text: "Gitee"
                        }
                    }

                    Item { Layout.fillWidth: true }

                    ActionButton {
                        text: "拉取"
                        icon: "\uf019"
                        fontFamily: fontAwesome.name
                        onClicked: gitManager.pull()
                        
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: "从远程仓库获取最新代码到本地"
                    }

                    ActionButton {
                        text: "一键提交推送"
                        icon: "\uf021"
                        fontFamily: fontAwesome.name
                        primary: true
                        enabled: commitInput.text.trim() !== "" && (gitManager.changedFiles.length > 0 || gitManager.stagedFiles.length > 0)
                        onClicked: {
                            gitManager.quickSync(commitInput.text)
                            commitInput.text = trayManager.commitTemplate || ""
                        }
                        
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: "暂存所有更改 + 提交 + 推送到远程，一步到位"
                    }

                    ActionButton {
                        text: "提交"
                        icon: "\uf00c"
                        fontFamily: fontAwesome.name
                        enabled: gitManager.stagedFiles.length > 0 && commitInput.text.trim() !== ""
                        onClicked: {
                            gitManager.commit(commitInput.text)
                            commitInput.text = trayManager.commitTemplate || ""
                        }
                        
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: "只提交已暂存的文件到本地仓库"
                    }

                    ActionButton {
                        text: "推送"
                        icon: "\uf093"
                        fontFamily: fontAwesome.name
                        onClicked: gitManager.push()
                        
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: "将本地提交推送到远程仓库"
                    }
                }
            }
        }
    }

    // Toast notification
    Toast {
        id: toast
        fontAwesomeName: fontAwesome.name
        z: 9999
    }

    // Loading overlay
    Rectangle {
        id: loadingOverlay
        anchors.fill: parent
        color: isDarkMode ? "#80000000" : "#80ffffff"
        visible: gitManager.isLoading
        z: 1000

        // Block all mouse events
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }

        // Loading spinner container
        Rectangle {
            anchors.centerIn: parent
            width: 120
            height: 120
            radius: 16
            color: isDarkMode ? "#2a2a2a" : "#ffffff"
            border.color: isDarkMode ? "#444444" : "#e0e0e0"
            border.width: 1

            // Shadow effect
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#40000000"
                shadowBlur: 0.5
                shadowVerticalOffset: 4
            }

            Column {
                anchors.centerIn: parent
                spacing: 16

                // Spinning icon
                Item {
                    width: 48
                    height: 48
                    anchors.horizontalCenter: parent.horizontalCenter

                    Text {
                        id: spinnerIcon
                        anchors.centerIn: parent
                        text: "\uf110"
                        font.family: fontAwesome.name
                        font.pixelSize: 36
                        color: theme.primary

                        RotationAnimator {
                            target: spinnerIcon
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                            running: loadingOverlay.visible
                        }
                    }
                }

                Text {
                    text: "处理中..."
                    font.pixelSize: 14
                    color: theme.text
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // Fade animation
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // Commit History Drawer
    Drawer {
        id: commitHistoryDrawer
        width: 450
        height: parent.height
        edge: Qt.RightEdge

        property string historySearchFilter: ""
        property var filteredHistory: {
            if (!historySearchFilter || historySearchFilter.trim() === "") {
                return gitManager.commitHistory
            }
            var keyword = historySearchFilter.toLowerCase()
            return gitManager.commitHistory.filter(function(commit) {
                return commit.message.toLowerCase().indexOf(keyword) >= 0 ||
                       commit.author.toLowerCase().indexOf(keyword) >= 0 ||
                       commit.shortHash.toLowerCase().indexOf(keyword) >= 0
            })
        }

        background: Rectangle {
            color: "#F8FBFE"
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // macOS style header
            MacTitleBar {
                Layout.fillWidth: true
                title: "提交历史"
                onCloseClicked: commitHistoryDrawer.close()
            }

            // Search bar
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 8
                height: 36
                radius: 8
                color: "#f9fafb"
                border.color: historySearchField.activeFocus ? "#3b82f6" : "#e5e7eb"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: "\uf002"
                        font.family: fontAwesome.name
                        font.pixelSize: 12
                        color: "#9ca3af"
                    }

                    TextInput {
                        id: historySearchField
                        Layout.fillWidth: true
                        font.pixelSize: 13
                        color: "#1f2937"
                        clip: true
                        selectByMouse: true
                        onTextChanged: commitHistoryDrawer.historySearchFilter = text

                        Text {
                            anchors.fill: parent
                            text: "搜索提交信息、作者..."
                            font.pixelSize: 13
                            color: "#9ca3af"
                            visible: !historySearchField.text && !historySearchField.activeFocus
                        }
                    }

                    Text {
                        text: "\uf00d"
                        font.family: fontAwesome.name
                        font.pixelSize: 11
                        color: clearHistorySearchArea.containsMouse ? "#ef4444" : "#9ca3af"
                        visible: historySearchField.text !== ""

                        MouseArea {
                            id: clearHistorySearchArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                historySearchField.text = ""
                                commitHistoryDrawer.historySearchFilter = ""
                            }
                        }
                    }
                }
            }

            // Sub header info
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                height: 36
                color: "transparent"
                
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: gitManager.currentBranch + " · " + commitHistoryDrawer.filteredHistory.length + " 条记录"
                    font.pixelSize: 12
                    color: "#6b7280"
                }
                
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    
                    Text {
                        text: "\uf2f1"
                        font.family: fontAwesome.name
                        font.pixelSize: 14
                        color: refreshHistoryArea.containsMouse ? "#3b82f6" : "#6b7280"
                        
                        MouseArea {
                            id: refreshHistoryArea
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: gitManager.loadCommitHistory()
                        }
                    }
                }
            }

            // Commit list
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 16
                Layout.topMargin: 0
                radius: 8
                color: "#ffffff"
                clip: true

                ListView {
                    id: commitListView
                    anchors.fill: parent
                    anchors.margins: 4
                    model: commitHistoryDrawer.filteredHistory
                    spacing: 6

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AlwaysOff
                    }

                    delegate: Rectangle {
                        id: commitDelegate
                        width: commitListView.width
                        height: commitContent.height + 20
                        radius: 8
                        color: commitHover.hovered ? theme.surface : theme.surfaceLight

                        property bool isFirst: index === 0
                        property bool isExpanded: false

                        HoverHandler {
                            id: commitHover
                        }

                        ColumnLayout {
                            id: commitContent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 8

                            // Header row - hash, branch, time, actions
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Commit hash
                                Rectangle {
                                    width: hashText.width + 12
                                    height: 22
                                    radius: 4
                                    color: Qt.rgba(74, 144, 217, 0.15)

                                    Text {
                                        id: hashText
                                        anchors.centerIn: parent
                                        text: modelData.shortHash
                                        font.pixelSize: 11
                                        font.family: "Consolas"
                                        font.bold: true
                                        color: theme.primary
                                    }
                                }

                                // Branch tag - limited width
                                Rectangle {
                                    width: Math.min(branchTag.implicitWidth + 12, 80)
                                    height: 22
                                    radius: 4
                                    color: Qt.rgba(124, 92, 191, 0.15)
                                    clip: true

                                    Text {
                                        id: branchTag
                                        anchors.centerIn: parent
                                        width: parent.width - 8
                                        text: gitManager.currentBranch
                                        font.pixelSize: 10
                                        color: theme.secondary
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    
                                    ToolTip.visible: branchTagHover.hovered && gitManager.currentBranch.length > 8
                                    ToolTip.text: gitManager.currentBranch
                                    ToolTip.delay: 300
                                    
                                    HoverHandler {
                                        id: branchTagHover
                                    }
                                }

                                // Full date and time
                                Text {
                                    text: modelData.fullDate || modelData.relativeDate
                                    font.pixelSize: 11
                                    color: theme.textDim
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                // Relative time
                                Text {
                                    text: "(" + modelData.relativeDate + ")"
                                    font.pixelSize: 10
                                    color: theme.textDim
                                    opacity: 0.7
                                    visible: modelData.fullDate !== undefined
                                }

                                // Fixed action buttons on the right
                                Row {
                                    spacing: 4
                                    z: 100  // Ensure buttons are on top
                                    
                                    // Edit button (only for first commit)
                                    Rectangle {
                                        visible: commitDelegate.isFirst && commitHover.hovered
                                        width: 28
                                        height: 28
                                        radius: 6
                                        color: editCommitHover.hovered ? theme.surfaceLight : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "\uf044"
                                            font.family: fontAwesome.name
                                            font.pixelSize: 12
                                            color: theme.primary
                                        }

                                        HoverHandler {
                                            id: editCommitHover
                                            cursorShape: Qt.PointingHandCursor
                                        }

                                        TapHandler {
                                            onTapped: {
                                                editCommitMessage = modelData.message
                                                editCommitDialog.open()
                                            }
                                        }

                                        // Block mouse events from propagating
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                editCommitMessage = modelData.message
                                                editCommitDialog.open()
                                            }
                                            cursorShape: Qt.PointingHandCursor
                                        }

                                        ToolTip.visible: editCommitHover.hovered
                                        ToolTip.text: "修改提交信息"
                                        ToolTip.delay: 500
                                    }

                                    // Revert button
                                    Rectangle {
                                        visible: commitHover.hovered
                                        width: 28
                                        height: 28
                                        radius: 6
                                        color: revertCommitHover.hovered ? "#3f1a1a" : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "\uf0e2"
                                            font.family: fontAwesome.name
                                            font.pixelSize: 12
                                            color: theme.error
                                        }

                                        HoverHandler {
                                            id: revertCommitHover
                                            cursorShape: Qt.PointingHandCursor
                                        }

                                        // Block mouse events from propagating
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                revertCommitHash = modelData.hash
                                                revertCommitMsg = modelData.message
                                                revertCommitDialog.open()
                                            }
                                        }

                                        ToolTip.visible: revertCommitHover.hovered
                                        ToolTip.text: "撤销此提交"
                                        ToolTip.delay: 500
                                    }
                                }
                            }

                            // Commit message (备注)
                            Rectangle {
                                Layout.fillWidth: true
                                height: msgText.height + 12
                                radius: 6
                                color: Qt.rgba(74, 144, 217, 0.1)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 8

                                    Text {
                                        text: "\uf075"
                                        font.family: fontAwesome.name
                                        font.pixelSize: 12
                                        color: theme.primary
                                    }

                                    Text {
                                        id: msgText
                                        text: modelData.message
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: theme.text
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }

                            // Author info
                            RowLayout {
                                spacing: 8

                                Text {
                                    text: "\uf007"
                                    font.family: fontAwesome.name
                                    font.pixelSize: 10
                                    color: theme.secondary
                                }
                                Text {
                                    text: modelData.author
                                    font.pixelSize: 11
                                    color: theme.secondary
                                }
                            }

                            // Files changed section - or message only indicator
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: !modelData.isMessageOnly

                                // Files header - clickable to expand
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 28
                                    radius: 4
                                    color: filesHeaderHover.hovered ? theme.surfaceLight : "transparent"

                                    HoverHandler {
                                        id: filesHeaderHover
                                        cursorShape: Qt.PointingHandCursor
                                    }

                                    TapHandler {
                                        onTapped: commitDelegate.isExpanded = !commitDelegate.isExpanded
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 4
                                        spacing: 6

                                        Text {
                                            text: commitDelegate.isExpanded ? "\uf078" : "\uf054"
                                            font.family: fontAwesome.name
                                            font.pixelSize: 10
                                            color: theme.textDim
                                        }

                                        Text {
                                            text: "\uf15b"
                                            font.family: fontAwesome.name
                                            font.pixelSize: 11
                                            color: theme.warning
                                        }

                                        Text {
                                            text: modelData.fileCount + " 个文件变更"
                                            font.pixelSize: 11
                                            color: theme.text
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: "点击展开"
                                            font.pixelSize: 10
                                            color: theme.textDim
                                            visible: !commitDelegate.isExpanded
                                        }
                                    }
                                }

                                // File list (expandable)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 16
                                    spacing: 2
                                    visible: commitDelegate.isExpanded

                                    Repeater {
                                        model: modelData.files

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 24
                                            radius: 4
                                            color: "transparent"

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: 8

                                                // Status icon
                                                Rectangle {
                                                    width: 18
                                                    height: 18
                                                    radius: 3
                                                    color: modelData.status === "A" ? Qt.rgba(158, 206, 106, 0.2) :
                                                           modelData.status === "D" ? Qt.rgba(247, 118, 142, 0.2) :
                                                           modelData.status === "M" ? Qt.rgba(224, 175, 104, 0.2) :
                                                           Qt.rgba(122, 162, 247, 0.2)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData.status === "A" ? "\uf067" :
                                                              modelData.status === "D" ? "\uf068" :
                                                              modelData.status === "M" ? "\uf044" :
                                                              "\uf074"
                                                        font.family: fontAwesome.name
                                                        font.pixelSize: 9
                                                        color: modelData.status === "A" ? theme.success :
                                                               modelData.status === "D" ? theme.error :
                                                               modelData.status === "M" ? theme.warning :
                                                               theme.primary
                                                    }
                                                }

                                                // Status text
                                                Text {
                                                    text: modelData.statusText || modelData.status
                                                    font.pixelSize: 10
                                                    color: modelData.status === "A" ? theme.success :
                                                           modelData.status === "D" ? theme.error :
                                                           modelData.status === "M" ? theme.warning :
                                                           theme.primary
                                                    Layout.preferredWidth: 30
                                                }

                                                // File name
                                                Text {
                                                    text: modelData.name
                                                    font.pixelSize: 11
                                                    color: theme.text
                                                    elide: Text.ElideMiddle
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Message only indicator (for amend commits without file changes)
                            Rectangle {
                                Layout.fillWidth: true
                                height: 28
                                radius: 4
                                color: Qt.rgba(59, 130, 246, 0.1)
                                visible: modelData.isMessageOnly

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    Text {
                                        text: "\uf075"
                                        font.family: fontAwesome.name
                                        font.pixelSize: 11
                                        color: theme.primary
                                    }

                                    Text {
                                        text: "仅修改提交信息"
                                        font.pixelSize: 11
                                        color: theme.primary
                                    }
                                }
                            }
                        }
                    }

                    // Empty state
                    Rectangle {
                        anchors.centerIn: parent
                        visible: gitManager.commitHistory.length === 0 && !gitManager.isLoading
                        color: "transparent"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: "\uf1da"
                                font.family: fontAwesome.name
                                font.pixelSize: 32
                                color: theme.textDim
                                Layout.alignment: Qt.AlignHCenter
                                opacity: 0.5
                            }
                            Text {
                                text: "暂无提交记录"
                                font.pixelSize: 12
                                color: theme.textDim
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
    }

    // Edit Commit Message Dialog
    property string editCommitMessage: ""

    Dialog {
        id: editCommitDialog
        title: ""
        anchors.centerIn: parent
        width: 420
        modal: true
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "修改提交信息"
            onCloseClicked: editCommitDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 16

            Text {
                text: "修改最近一次提交的描述信息"
                font.pixelSize: 14
                color: "#1a1a1a"
            }

            Rectangle {
                Layout.fillWidth: true
                height: 80
                radius: 8
                color: "#ffffff"
                border.color: editMsgInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                border.width: 1

                TextArea {
                    id: editMsgInput
                    anchors.fill: parent
                    anchors.margins: 8
                    text: editCommitMessage
                    color: "#1a1a1a"
                    font.pixelSize: 13
                    wrapMode: TextArea.Wrap
                    background: null
                }
            }

            Text {
                text: "⚠️ 这将强制推送到远程，请确保没有其他人在使用此分支"
                font.pixelSize: 11
                color: "#f59e0b"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 30
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: cancelEditArea.containsMouse ? "#3b82f6" : "#6b7280"
                    Behavior on color { ColorAnimation { duration: 150 } }
                    MouseArea {
                        id: cancelEditArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: editCommitDialog.close()
                    }
                }

                ActionButton {
                    text: "保存"
                    icon: "\uf0c7"
                    fontFamily: fontAwesome.name
                    primary: true
                    enabled: editMsgInput.text.trim() !== ""
                    onClicked: {
                        gitManager.amendCommitMessage(editMsgInput.text)
                        editCommitDialog.close()
                    }
                }
            }
        }
    }

    // Revert Commit Dialog
    property string revertCommitHash: ""
    property string revertCommitMsg: ""

    Dialog {
        id: revertCommitDialog
        title: ""
        anchors.centerIn: parent
        width: 420
        modal: true
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "撤销提交"
            onCloseClicked: revertCommitDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 16

            Text {
                text: "将创建一个新的提交来撤销此更改"
                font.pixelSize: 14
                color: "#1a1a1a"
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 8
                color: "#ffffff"
                border.color: revertMsgInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                border.width: 1

                TextInput {
                    id: revertMsgInput
                    anchors.fill: parent
                    anchors.margins: 10
                    color: "#1a1a1a"
                    font.pixelSize: 13
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    selectByMouse: true

                    Text {
                        anchors.fill: parent
                        text: "Revert: " + revertCommitMsg
                        color: "#9ca3af"
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        visible: !revertMsgInput.text && !revertMsgInput.activeFocus
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 30
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: cancelRevertArea.containsMouse ? "#3b82f6" : "#6b7280"
                    Behavior on color { ColorAnimation { duration: 150 } }
                    MouseArea {
                        id: cancelRevertArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            revertCommitDialog.close()
                            revertMsgInput.text = ""
                        }
                    }
                }

                ActionButton {
                    text: "撤销"
                    icon: "\uf0e2"
                    fontFamily: fontAwesome.name
                    primary: true
                    onClicked: {
                        gitManager.revertCommit(revertCommitHash, revertMsgInput.text)
                        revertCommitDialog.close()
                        revertMsgInput.text = ""
                    }
                }
            }
        }
    }

    // Remote File Browser Drawer
    Drawer {
        id: remoteFileBrowserDrawer
        width: 420
        height: parent.height
        edge: Qt.RightEdge

        property string remoteSearchFilter: ""
        property var filteredRemoteFiles: {
            if (!remoteSearchFilter || remoteSearchFilter.trim() === "") {
                return gitManager.remoteFiles
            }
            var keyword = remoteSearchFilter.toLowerCase()
            return gitManager.remoteFiles.filter(function(file) {
                return file.name.toLowerCase().indexOf(keyword) >= 0
            })
        }

        background: Rectangle {
            color: "#F8FBFE"
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // macOS style header
            MacTitleBar {
                Layout.fillWidth: true
                title: "远程文件"
                onCloseClicked: remoteFileBrowserDrawer.close()
            }

            // Search bar
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 8
                height: 36
                radius: 8
                color: "#f9fafb"
                border.color: remoteSearchField.activeFocus ? "#3b82f6" : "#e5e7eb"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: "\uf002"
                        font.family: fontAwesome.name
                        font.pixelSize: 12
                        color: "#9ca3af"
                    }

                    TextInput {
                        id: remoteSearchField
                        Layout.fillWidth: true
                        font.pixelSize: 13
                        color: "#1f2937"
                        clip: true
                        selectByMouse: true
                        onTextChanged: remoteFileBrowserDrawer.remoteSearchFilter = text

                        Text {
                            anchors.fill: parent
                            text: "搜索文件..."
                            font.pixelSize: 13
                            color: "#9ca3af"
                            visible: !remoteSearchField.text && !remoteSearchField.activeFocus
                        }
                    }

                    Text {
                        text: "\uf00d"
                        font.family: fontAwesome.name
                        font.pixelSize: 11
                        color: clearRemoteSearchArea.containsMouse ? "#ef4444" : "#9ca3af"
                        visible: remoteSearchField.text !== ""

                        MouseArea {
                            id: clearRemoteSearchArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                remoteSearchField.text = ""
                                remoteFileBrowserDrawer.remoteSearchFilter = ""
                            }
                        }
                    }
                }
            }

            // Path and actions bar
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                height: 40
                color: "transparent"
                
                RowLayout {
                    anchors.fill: parent
                    spacing: 8
                    
                    // Back button
                    Text {
                        text: "\uf060"
                        font.family: fontAwesome.name
                        font.pixelSize: 14
                        color: backArea.containsMouse ? "#3b82f6" : "#6b7280"
                        visible: gitManager.remoteCurrentPath !== ""
                        
                        MouseArea {
                            id: backArea
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: gitManager.goBackRemote()
                        }
                    }
                    
                    Text {
                        text: "/" + (gitManager.remoteCurrentPath || "")
                        font.pixelSize: 12
                        color: "#6b7280"
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                    
                    Text {
                        text: "\uf2f1"
                        font.family: fontAwesome.name
                        font.pixelSize: 14
                        color: refreshRemoteArea.containsMouse ? "#3b82f6" : "#6b7280"
                        
                        MouseArea {
                            id: refreshRemoteArea
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: gitManager.loadRemoteFiles(gitManager.remoteCurrentPath)
                        }
                    }
                }
            }

            // Branch info
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                height: 36
                radius: 6
                color: "#f0f4f8"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: "\uf126"
                        font.family: fontAwesome.name
                        font.pixelSize: 12
                        color: "#6b7280"
                    }
                    Text {
                        text: gitManager.currentBranch
                        font.pixelSize: 12
                        color: "#1a1a1a"
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: remoteFileBrowserDrawer.filteredRemoteFiles.length + " 项"
                        font.pixelSize: 11
                        color: theme.textDim
                    }
                }
            }

            // File list
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: theme.surfaceLight
                clip: true

                ListView {
                    id: remoteFileListView
                    anchors.fill: parent
                    anchors.margins: 4
                    model: remoteFileBrowserDrawer.filteredRemoteFiles
                    spacing: 2

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AlwaysOff
                    }

                    delegate: Rectangle {
                        id: remoteFileDelegate
                        width: remoteFileListView.width
                        height: 64
                        radius: 6
                        color: remoteFileHover.hovered ? theme.surface : "transparent"

                        property bool isDir: modelData.isDir
                        property bool isImage: {
                            var ext = modelData.name.toLowerCase().split('.').pop()
                            return ["png", "jpg", "jpeg", "gif", "bmp", "webp", "ico"].indexOf(ext) >= 0
                        }
                        
                        // Get file icon based on extension
                        function getFileIcon(fileName) {
                            if (isDir) return "\uf07b"
                            var ext = fileName.split('.').pop().toLowerCase()
                            
                            if (["js", "jsx", "ts", "tsx"].includes(ext)) return "\uf3b8"
                            if (["py", "pyw"].includes(ext)) return "\uf3e2"
                            if (["java", "jar"].includes(ext)) return "\uf4e4"
                            if (["c", "cpp", "cc", "h", "hpp"].includes(ext)) return "\ue61d"
                            if (["html", "htm"].includes(ext)) return "\uf13b"
                            if (["css", "scss", "sass", "less"].includes(ext)) return "\uf13c"
                            if (["vue"].includes(ext)) return "\uf41f"
                            if (["json"].includes(ext)) return "\uf1c9"
                            if (["md", "markdown"].includes(ext)) return "\uf48a"
                            if (["txt", "text"].includes(ext)) return "\uf15c"
                            if (["pdf"].includes(ext)) return "\uf1c1"
                            if (["doc", "docx"].includes(ext)) return "\uf1c2"
                            if (["xls", "xlsx"].includes(ext)) return "\uf1c3"
                            if (["ppt", "pptx"].includes(ext)) return "\uf1c4"
                            if (["png", "jpg", "jpeg", "gif", "bmp", "svg", "webp", "ico"].includes(ext)) return "\uf1c5"
                            if (["mp3", "wav", "flac", "aac", "ogg"].includes(ext)) return "\uf1c7"
                            if (["mp4", "avi", "mov", "mkv", "webm"].includes(ext)) return "\uf1c8"
                            if (["zip", "rar", "7z", "tar", "gz"].includes(ext)) return "\uf1c6"
                            if (["sh", "bash", "bat", "cmd", "ps1"].includes(ext)) return "\uf120"
                            if (["exe", "msi", "dmg", "app"].includes(ext)) return "\uf085"
                            return "\uf15b"
                        }
                        
                        function getFileIconColor(fileName) {
                            if (isDir) return "#f59e0b"
                            var ext = fileName.split('.').pop().toLowerCase()
                            
                            if (["js", "jsx"].includes(ext)) return "#f7df1e"
                            if (["ts", "tsx"].includes(ext)) return "#3178c6"
                            if (["py", "pyw"].includes(ext)) return "#3776ab"
                            if (["java", "jar"].includes(ext)) return "#ed8b00"
                            if (["html", "htm"].includes(ext)) return "#e34f26"
                            if (["css", "scss", "sass", "less"].includes(ext)) return "#1572b6"
                            if (["vue"].includes(ext)) return "#42b883"
                            if (["json"].includes(ext)) return "#cbcb41"
                            if (["md", "markdown"].includes(ext)) return "#083fa1"
                            if (["pdf"].includes(ext)) return "#ff0000"
                            if (["doc", "docx"].includes(ext)) return "#2b579a"
                            if (["xls", "xlsx"].includes(ext)) return "#217346"
                            if (["ppt", "pptx"].includes(ext)) return "#d24726"
                            if (["png", "jpg", "jpeg", "gif", "svg"].includes(ext)) return "#a074c4"
                            if (["mp3", "wav", "flac"].includes(ext)) return "#1db954"
                            if (["mp4", "avi", "mov", "mkv"].includes(ext)) return "#e50914"
                            if (["zip", "rar", "7z"].includes(ext)) return "#f9a825"
                            if (["sh", "bash", "bat"].includes(ext)) return "#4eaa25"
                            if (["exe", "msi"].includes(ext)) return "#00a4ef"
                            return "#6b7280"
                        }

                        HoverHandler {
                            id: remoteFileHover
                        }

                        TapHandler {
                            onTapped: {
                                if (remoteFileDelegate.isDir) {
                                    gitManager.loadRemoteFiles(modelData.path)
                                } else if (remoteFileDelegate.isImage) {
                                    // Open image preview
                                    openImagePreview(modelData.path, modelData.name)
                                } else {
                                    // Open file editor
                                    remoteEditFilePath = modelData.path
                                    gitManager.openFile(modelData.path)
                                    remoteFileEditorDialog.open()
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            // Icon
                            Text {
                                text: remoteFileDelegate.getFileIcon(modelData.name)
                                font.family: fontAwesome.name
                                font.pixelSize: 18
                                color: remoteFileDelegate.getFileIconColor(modelData.name)
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 12
                            }

                            // File info
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: modelData.name
                                    font.pixelSize: 13
                                    color: theme.text
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                
                                // Commit message
                                Text {
                                    visible: modelData.commitMsg && modelData.commitMsg !== ""
                                    text: modelData.commitMsg || ""
                                    font.pixelSize: 11
                                    color: theme.textDim
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                
                                // Size and time row
                                RowLayout {
                                    spacing: 8
                                    Text {
                                        visible: !remoteFileDelegate.isDir && modelData.size > 0
                                        text: formatFileSize(modelData.size)
                                        font.pixelSize: 10
                                        color: theme.textDim

                                        function formatFileSize(bytes) {
                                            if (!bytes || bytes === 0) return ""
                                            if (bytes < 1024) return bytes + " B"
                                            if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
                                            return (bytes / 1024 / 1024).toFixed(1) + " MB"
                                        }
                                    }
                                    // Full date time
                                    Text {
                                        visible: modelData.commitTimeFull && modelData.commitTimeFull !== ""
                                        text: modelData.commitTimeFull || ""
                                        font.pixelSize: 10
                                        color: theme.textDim
                                    }
                                    // Relative time in parentheses
                                    Text {
                                        visible: modelData.commitTimeRelative && modelData.commitTimeRelative !== ""
                                        text: "(" + (modelData.commitTimeRelative || "") + ")"
                                        font.pixelSize: 10
                                        color: theme.secondary
                                    }
                                }
                            }

                            // Edit button (for files only)
                            Rectangle {
                                id: editBtn
                                visible: !remoteFileDelegate.isDir && remoteFileHover.hovered
                                width: 28
                                height: 28
                                radius: 6
                                color: editBtnArea.containsMouse ? theme.surfaceLight : "transparent"
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf044"
                                    font.family: fontAwesome.name
                                    font.pixelSize: 12
                                    color: theme.primary
                                }

                                MouseArea {
                                    id: editBtnArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        mouse.accepted = true
                                        remoteEditFilePath = modelData.path
                                        gitManager.openFile(modelData.path)
                                        remoteFileEditorDialog.open()
                                    }
                                }

                                ToolTip.visible: editBtnArea.containsMouse
                                ToolTip.text: "编辑文件"
                                ToolTip.delay: 500
                            }

                            // Rename button
                            Rectangle {
                                id: renameBtn
                                width: 28
                                height: 28
                                radius: 6
                                color: renameBtnArea.containsMouse ? "#fef3c7" : "transparent"
                                opacity: remoteFileHover.hovered ? 1 : 0
                                visible: opacity > 0
                                Layout.alignment: Qt.AlignVCenter

                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf246"
                                    font.family: fontAwesome.name
                                    font.pixelSize: 12
                                    color: theme.warning
                                }

                                MouseArea {
                                    id: renameBtnArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        mouse.accepted = true
                                        renameOldPath = modelData.path
                                        renameOldName = modelData.name
                                        renameNewNameInput.text = modelData.name
                                        renameFileDialog.open()
                                    }
                                }

                                ToolTip.visible: renameBtnArea.containsMouse
                                ToolTip.text: "重命名"
                                ToolTip.delay: 500
                            }

                            // Delete button
                            Rectangle {
                                id: deleteBtn
                                width: 28
                                height: 28
                                radius: 6
                                color: deleteBtnArea.containsMouse ? "#3f1a1a" : "transparent"
                                opacity: remoteFileHover.hovered ? 1 : 0
                                visible: opacity > 0
                                Layout.alignment: Qt.AlignVCenter

                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf1f8"
                                    font.family: fontAwesome.name
                                    font.pixelSize: 12
                                    color: theme.error
                                }

                                MouseArea {
                                    id: deleteBtnArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        mouse.accepted = true
                                        remoteDeleteFilePath = modelData.path
                                        remoteDeleteFileDialog.open()
                                    }
                                }

                                ToolTip.visible: deleteBtnArea.containsMouse
                                ToolTip.text: "删除文件"
                                ToolTip.delay: 500
                            }
                        }
                    }

                    // Empty state
                    Rectangle {
                        anchors.centerIn: parent
                        visible: gitManager.remoteFiles.length === 0 && !gitManager.isLoading
                        color: "transparent"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: "\uf0c2"
                                font.family: fontAwesome.name
                                font.pixelSize: 32
                                color: theme.textDim
                                Layout.alignment: Qt.AlignHCenter
                                opacity: 0.5
                            }
                            Text {
                                text: "暂无文件"
                                font.pixelSize: 12
                                color: theme.textDim
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
    }

    // Remote File Editor Dialog
    property string remoteEditFilePath: ""
    property string remoteEditOriginalContent: ""  // 存储原始内容用于比较

    Dialog {
        id: remoteFileEditorDialog
        title: ""
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 650)
        height: Math.min(parent.height - 60, 500)
        modal: true
        standardButtons: Dialog.NoButton

        onOpened: {
            // 对话框打开时保存原始内容
            // 使用延迟确保fileContent已加载
            Qt.callLater(function() {
                remoteEditOriginalContent = gitManager.fileContent
                console.log("Original content saved, length:", remoteEditOriginalContent.length)
            })
        }

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "编辑文件"
            onCloseClicked: remoteFileEditorDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 12

            // File path
            RowLayout {
                spacing: 8
                Text {
                    text: "\uf15b"
                    font.family: fontAwesome.name
                    font.pixelSize: 12
                    color: "#6b7280"
                }
                Text {
                    text: remoteEditFilePath
                    font.pixelSize: 12
                    color: "#6b7280"
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
            }

            // Editor
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: "#ffffff"
                border.color: "#e5e7eb"
                border.width: 1

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 8

                    TextArea {
                        id: remoteFileEditor
                        text: gitManager.fileContent
                        color: "#1a1a1a"
                        font.family: "Consolas, Monaco, monospace"
                        font.pixelSize: 13
                        wrapMode: TextArea.NoWrap
                        selectByMouse: true
                        background: null
                    }
                }
            }

            // Commit message input
            Rectangle {
                Layout.fillWidth: true
                height: 44
                radius: 8
                color: "#ffffff"
                border.color: remoteEditorCommitMsgInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: "\uf075"
                        font.family: fontAwesome.name
                        font.pixelSize: 12
                        color: "#9ca3af"
                    }

                    TextInput {
                        id: remoteEditorCommitMsgInput
                        Layout.fillWidth: true
                        color: "#1a1a1a"
                        font.pixelSize: 13
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true

                        Text {
                            anchors.fill: parent
                            text: "提交信息 (可选，留空则使用默认)"
                            color: "#9ca3af"
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                            visible: !remoteEditorCommitMsgInput.text && !remoteEditorCommitMsgInput.activeFocus
                        }
                    }
                }
            }

            // Buttons
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 30
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: cancelEditorArea.containsMouse ? "#3b82f6" : "#6b7280"
                    Behavior on color { ColorAnimation { duration: 150 } }
                    MouseArea {
                        id: cancelEditorArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            remoteFileEditorDialog.close()
                            remoteEditorCommitMsgInput.text = ""
                        }
                    }
                }

                ActionButton {
                    text: "保存并推送"
                    icon: "\uf093"
                    fontFamily: fontAwesome.name
                    primary: true
                    onClicked: {
                        var currentContent = remoteFileEditor.text
                        var originalContent = remoteEditOriginalContent
                        var contentChanged = (currentContent !== originalContent)
                        var rawMsg = remoteEditorCommitMsgInput.text
                        var commitMsg = rawMsg ? rawMsg.trim() : ""
                        
                        console.log("=== Save button clicked ===")
                        console.log("currentContent length:", currentContent.length)
                        console.log("originalContent length:", originalContent.length)
                        console.log("contentChanged:", contentChanged)
                        console.log("rawMsg:", rawMsg)
                        console.log("commitMsg:", commitMsg)
                        
                        if (contentChanged) {
                            // 文件内容有变化，正常保存并推送
                            console.log("Calling saveAndPushFile with message:", commitMsg)
                            gitManager.saveAndPushFile(remoteEditFilePath, currentContent, commitMsg)
                            toast.show("已保存，请点击刷新按钮查看更新", "success")
                        } else if (commitMsg !== "") {
                            // 文件内容没变，但有提交信息，使用amend修改上次提交信息
                            console.log("Calling amendCommitMessage with message:", commitMsg)
                            gitManager.amendCommitMessage(commitMsg)
                            toast.show("已修改提交信息，请点击刷新按钮查看更新", "success")
                        } else {
                            // 什么都没改
                            toast.show("没有任何更改", "info")
                        }
                        remoteFileEditorDialog.close()
                        remoteEditorCommitMsgInput.text = ""
                    }
                }
            }
        }
    }

    // Remote Delete File Dialog
    property string remoteDeleteFilePath: ""

    Dialog {
        id: remoteDeleteFileDialog
        title: ""
        anchors.centerIn: parent
        width: 400
        modal: true
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "删除文件"
            onCloseClicked: remoteDeleteFileDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 16

            Text {
                text: "确定要从远程仓库删除此文件吗？"
                font.pixelSize: 14
                color: "#1a1a1a"
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 8
                color: "#fef2f2"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: "\uf1f8"
                        font.family: fontAwesome.name
                        font.pixelSize: 12
                        color: "#ef4444"
                    }
                    Text {
                        text: remoteDeleteFilePath
                        font.pixelSize: 13
                        color: "#ef4444"
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }
            }

            Text {
                text: "提交信息（可选）"
                font.pixelSize: 12
                color: "#6b7280"
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 8
                color: "#ffffff"
                border.color: remoteDeleteMsgInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                border.width: 1

                TextInput {
                    id: remoteDeleteMsgInput
                    anchors.fill: parent
                    anchors.margins: 10
                    color: "#1a1a1a"
                    font.pixelSize: 13
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    selectByMouse: true

                    Text {
                        anchors.fill: parent
                        text: "Delete " + remoteDeleteFilePath
                        color: "#9ca3af"
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        visible: !remoteDeleteMsgInput.text && !remoteDeleteMsgInput.activeFocus
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 30
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: cancelDeleteArea.containsMouse ? "#3b82f6" : "#6b7280"
                    Behavior on color { ColorAnimation { duration: 150 } }
                    MouseArea {
                        id: cancelDeleteArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            remoteDeleteFileDialog.close()
                            remoteDeleteMsgInput.text = ""
                        }
                    }
                }

                ActionButton {
                    text: "删除"
                    icon: "\uf1f8"
                    fontFamily: fontAwesome.name
                    primary: true
                    onClicked: {
                        var msg = remoteDeleteMsgInput.text || ("Delete " + remoteDeleteFilePath)
                        gitManager.deleteRemoteFile(remoteDeleteFilePath, msg)
                        remoteDeleteFileDialog.close()
                        remoteDeleteMsgInput.text = ""
                    }
                }
            }
        }
    }

    // Rename File Dialog
    property string renameOldPath: ""
    property string renameOldName: ""

    Dialog {
        id: renameFileDialog
        title: ""
        anchors.centerIn: parent
        width: 420
        modal: true
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "重命名文件"
            onCloseClicked: renameFileDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 16

            Text {
                text: "输入新的文件名"
                font.pixelSize: 14
                color: "#1a1a1a"
            }

            // Current name
            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 8
                color: "#f3f4f6"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: "\uf15b"
                        font.family: fontAwesome.name
                        font.pixelSize: 12
                        color: "#6b7280"
                    }
                    Text {
                        text: renameOldName
                        font.pixelSize: 13
                        color: "#6b7280"
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }
            }

            // New name input
            Text {
                text: "新文件名"
                font.pixelSize: 12
                color: "#1a1a1a"
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 8
                color: "#ffffff"
                border.color: renameNewNameInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                border.width: 1

                TextInput {
                    id: renameNewNameInput
                    anchors.fill: parent
                    anchors.margins: 10
                    color: "#1a1a1a"
                    font.pixelSize: 13
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    selectByMouse: true

                    Text {
                        anchors.fill: parent
                        text: "输入新文件名..."
                        color: "#9ca3af"
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        visible: !renameNewNameInput.text && !renameNewNameInput.activeFocus
                    }
                }
            }

            // Commit message
            Text {
                text: "提交信息（可选）"
                font.pixelSize: 12
                color: "#6b7280"
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 8
                color: "#ffffff"
                border.color: renameMsgInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                border.width: 1

                TextInput {
                    id: renameMsgInput
                    anchors.fill: parent
                    anchors.margins: 10
                    color: "#1a1a1a"
                    font.pixelSize: 13
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    selectByMouse: true

                    Text {
                        anchors.fill: parent
                        text: "Rename " + renameOldName
                        color: "#9ca3af"
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        visible: !renameMsgInput.text && !renameMsgInput.activeFocus
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 30
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: cancelRenameArea.containsMouse ? "#3b82f6" : "#6b7280"
                    Behavior on color { ColorAnimation { duration: 150 } }
                    MouseArea {
                        id: cancelRenameArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            renameFileDialog.close()
                            renameMsgInput.text = ""
                        }
                    }
                }

                ActionButton {
                    text: "重命名"
                    icon: "\uf246"
                    fontFamily: fontAwesome.name
                    primary: true
                    enabled: renameNewNameInput.text.trim() !== "" && renameNewNameInput.text.trim() !== renameOldName
                    onClicked: {
                        // Calculate new path
                        var pathParts = renameOldPath.split("/")
                        pathParts.pop()
                        var newPath = pathParts.length > 0 ? pathParts.join("/") + "/" + renameNewNameInput.text.trim() : renameNewNameInput.text.trim()
                        
                        var msg = renameMsgInput.text || ""
                        gitManager.renameRemoteFile(renameOldPath, newPath, msg)
                        renameFileDialog.close()
                        renameMsgInput.text = ""
                    }
                }
            }
        }
    }

    // Image Preview Dialog
    property string imagePreviewPath: ""
    property string imagePreviewName: ""
    property var imageList: []
    property int currentImageIndex: 0

    function openImagePreview(path, name) {
        // Build image list from current remote files
        imageList = []
        for (var i = 0; i < gitManager.remoteFiles.length; i++) {
            var file = gitManager.remoteFiles[i]
            if (!file.isDir) {
                var ext = file.name.toLowerCase().split('.').pop()
                if (["png", "jpg", "jpeg", "gif", "bmp", "webp", "ico"].indexOf(ext) >= 0) {
                    imageList.push({path: file.path, name: file.name})
                }
            }
        }
        // Find current index
        for (var j = 0; j < imageList.length; j++) {
            if (imageList[j].path === path) {
                currentImageIndex = j
                break
            }
        }
        imagePreviewPath = path
        imagePreviewName = name
        imagePreviewDialog.open()
    }

    function showPrevImage() {
        if (imageList.length > 1 && currentImageIndex > 0) {
            currentImageIndex--
            imagePreviewPath = imageList[currentImageIndex].path
            imagePreviewName = imageList[currentImageIndex].name
        }
    }

    function showNextImage() {
        if (imageList.length > 1 && currentImageIndex < imageList.length - 1) {
            currentImageIndex++
            imagePreviewPath = imageList[currentImageIndex].path
            imagePreviewName = imageList[currentImageIndex].name
        }
    }

    Dialog {
        id: imagePreviewDialog
        title: ""
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 800)
        height: Math.min(parent.height - 40, 600)
        modal: true
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: imagePreviewName
            onCloseClicked: imagePreviewDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 12

            // Image count indicator
            Text {
                visible: imageList.length > 1
                text: (currentImageIndex + 1) + " / " + imageList.length
                font.pixelSize: 12
                color: "#6b7280"
                Layout.alignment: Qt.AlignHCenter
            }

            // Image container with navigation
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Previous button
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    radius: 20
                    color: prevHover.hovered ? "#e5e7eb" : "#f3f4f6"
                    visible: imageList.length > 1 && currentImageIndex > 0
                    z: 10
                    
                    Text {
                        anchors.centerIn: parent
                        text: "\uf053"
                        font.family: fontAwesome.name
                        font.pixelSize: 16
                        color: "#1a1a1a"
                    }

                    HoverHandler { id: prevHover }
                    TapHandler { onTapped: showPrevImage() }
                }

                // Next button
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    radius: 20
                    color: nextHover.hovered ? "#e5e7eb" : "#f3f4f6"
                    visible: imageList.length > 1 && currentImageIndex < imageList.length - 1
                    z: 10

                    Text {
                        anchors.centerIn: parent
                        text: "\uf054"
                        font.family: fontAwesome.name
                        font.pixelSize: 16
                        color: "#1a1a1a"
                    }

                    HoverHandler { id: nextHover }
                    TapHandler { onTapped: showNextImage() }
                }

                // Image
                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 50
                    anchors.rightMargin: 50
                    radius: 8
                    color: theme.surfaceLight
                    clip: true

                    Image {
                        id: previewImage
                        anchors.fill: parent
                        anchors.margins: 8
                        source: "file:///" + gitManager.repoPath + "/" + imagePreviewPath
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true

                        BusyIndicator {
                            anchors.centerIn: parent
                            running: previewImage.status === Image.Loading
                            visible: running
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "无法加载图片"
                            font.pixelSize: 14
                            color: theme.error
                            visible: previewImage.status === Image.Error
                        }
                    }
                }
            }

            // Image info
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 30
                spacing: 16

                Text {
                    text: "尺寸: " + previewImage.sourceSize.width + " × " + previewImage.sourceSize.height
                    font.pixelSize: 11
                    color: theme.textDim
                    visible: previewImage.status === Image.Ready
                }

                Item { Layout.fillWidth: true }

                ActionButton {
                    text: "上一张"
                    icon: "\uf053"
                    fontFamily: fontAwesome.name
                    enabled: currentImageIndex > 0
                    visible: imageList.length > 1
                    onClicked: showPrevImage()
                }

                ActionButton {
                    text: "下一张"
                    icon: "\uf054"
                    fontFamily: fontAwesome.name
                    enabled: currentImageIndex < imageList.length - 1
                    visible: imageList.length > 1
                    onClicked: showNextImage()
                }

                ActionButton {
                    text: "关闭"
                    onClicked: imagePreviewDialog.close()
                }
            }
        }
    }

    // User Config Dialog
    Dialog {
        id: userConfigDialog
        title: ""
        anchors.centerIn: parent
        width: 420
        modal: true
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "用户配置"
            onCloseClicked: userConfigDialog.close()
        }

        contentItem: ColumnLayout {
            spacing: 16

            Text {
                text: "用户名和邮箱将用于提交记录"
                font.pixelSize: 12
                color: "#6b7280"
            }

            // Username
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "用户名"
                    font.pixelSize: 12
                    color: "#1a1a1a"
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    radius: 8
                    color: "#ffffff"
                    border.color: configNameInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                    border.width: 1

                    TextInput {
                        id: configNameInput
                        anchors.fill: parent
                        anchors.margins: 10
                        color: "#1a1a1a"
                        font.pixelSize: 13
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        text: gitManager.userName || ""

                        Text {
                            anchors.fill: parent
                            text: "输入用户名..."
                            color: "#9ca3af"
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                            visible: !configNameInput.text && !configNameInput.activeFocus
                        }
                    }
                }
            }

            // Email
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "邮箱"
                    font.pixelSize: 12
                    color: "#1a1a1a"
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    radius: 8
                    color: "#ffffff"
                    border.color: configEmailInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                    border.width: 1

                    TextInput {
                        id: configEmailInput
                        anchors.fill: parent
                        anchors.margins: 10
                        color: "#1a1a1a"
                        font.pixelSize: 13
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        text: gitManager.userEmail || ""

                        Text {
                            anchors.fill: parent
                            text: "输入邮箱..."
                            color: "#9ca3af"
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                            visible: !configEmailInput.text && !configEmailInput.activeFocus
                        }
                    }
                }
            }            // Scope selection
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "配置范围"
                    font.pixelSize: 12
                    color: theme.text
                }

                RowLayout {
                    spacing: 16

                    Rectangle {
                        width: globalRadio.width + 30
                        height: 36
                        radius: 8
                        color: configScopeGlobal ? Qt.rgba(74, 144, 217, 0.15) : theme.surfaceLight
                        border.color: configScopeGlobal ? theme.primary : theme.border
                        border.width: 1

                        RowLayout {
                            id: globalRadio
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                width: 16
                                height: 16
                                radius: 8
                                color: "transparent"
                                border.color: configScopeGlobal ? theme.primary : theme.textDim
                                border.width: 2

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: theme.primary
                                    visible: configScopeGlobal
                                }
                            }

                            Text {
                                text: "全局配置"
                                font.pixelSize: 12
                                color: theme.text
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: configScopeGlobal = true
                        }
                    }

                    Rectangle {
                        width: localRadio.width + 30
                        height: 36
                        radius: 8
                        color: !configScopeGlobal ? Qt.rgba(74, 144, 217, 0.15) : theme.surfaceLight
                        border.color: !configScopeGlobal ? theme.primary : theme.border
                        border.width: 1

                        RowLayout {
                            id: localRadio
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                width: 16
                                height: 16
                                radius: 8
                                color: "transparent"
                                border.color: !configScopeGlobal ? theme.primary : theme.textDim
                                border.width: 2

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: theme.primary
                                    visible: !configScopeGlobal
                                }
                            }

                            Text {
                                text: "仅当前仓库"
                                font.pixelSize: 12
                                color: theme.text
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: configScopeGlobal = false
                        }
                    }
                }

                Text {
                    text: configScopeGlobal ? "全局配置将应用于所有仓库" : "仅对当前仓库生效"
                    font.pixelSize: 10
                    color: theme.textDim
                    Layout.topMargin: 4
                }
            }

            // Buttons
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 30
                spacing: 12

                Item { Layout.fillWidth: true }

                ActionButton {
                    text: "取消"
                    onClicked: userConfigDialog.close()
                }

                ActionButton {
                    text: "保存配置"
                    icon: "\uf0c7"
                    fontFamily: fontAwesome.name
                    primary: true
                    enabled: configNameInput.text.trim() !== "" && configEmailInput.text.trim() !== ""
                    onClicked: {
                        gitManager.configureUser(configNameInput.text.trim(), configEmailInput.text.trim(), configScopeGlobal)
                        userConfigDialog.close()
                    }
                }
            }
        }
    }

    property bool configScopeGlobal: true

    // Loading overlay
    Rectangle {
        anchors.fill: parent
        color: "#80000000"
        visible: gitManager.isLoading
        opacity: gitManager.isLoading ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 200 } }

        BusyIndicator {
            anchors.centerIn: parent
            running: gitManager.isLoading
            palette.dark: theme.primary
        }

        MouseArea {
            anchors.fill: parent
            // Block clicks while loading
        }
    }

    // Settings Dialog
    Dialog {
        id: settingsDialog
        title: ""
        anchors.centerIn: parent
        width: 520
        height: 580
        modal: true
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "设置"
            onCloseClicked: settingsDialog.close()
        }

        contentItem: Flickable {
            contentHeight: settingsContent.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: settingsContent
                width: parent.width
                spacing: 20

                // Commit Template Section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "默认提交信息模板"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#1a1a1a"
                    }

                    Text {
                        text: "设置后，提交输入框会自动填充此模板"
                        font.pixelSize: 11
                        color: "#6b7280"
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 80
                    radius: 8
                    color: "#ffffff"
                    border.color: commitTemplateInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                    border.width: 1

                    TextArea {
                        id: commitTemplateInput
                        anchors.fill: parent
                        anchors.margins: 10
                        color: "#1a1a1a"
                        font.pixelSize: 13
                        wrapMode: TextArea.Wrap
                        placeholderText: "例如: [功能] "
                        placeholderTextColor: "#9ca3af"
                        background: null
                        text: trayManager.commitTemplate
                    }
                }
            }

            // Auto Push Toggle
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "自动推送"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#1a1a1a"
                    }

                    Text {
                        text: "提交后自动推送到远程仓库"
                        font.pixelSize: 11
                        color: "#6b7280"
                    }
                }

                // Toggle Switch
                Rectangle {
                    id: autoPushToggle
                    width: 50
                    height: 28
                    radius: 14
                    color: trayManager.autoPush ? "#10b981" : "#d1d5db"

                    Behavior on color { ColorAnimation { duration: 200 } }

                    Rectangle {
                        width: 22
                        height: 22
                        radius: 11
                        color: "#ffffff"
                        x: trayManager.autoPush ? parent.width - width - 3 : 3
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: trayManager.autoPush = !trayManager.autoPush
                    }
                }
            }

            // Dark Mode Toggle
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "深色模式"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#1a1a1a"
                    }

                    Text {
                        text: "切换界面主题，下次启动时保持"
                        font.pixelSize: 11
                        color: "#6b7280"
                    }
                }

                // Toggle Switch
                Rectangle {
                    width: 50
                    height: 28
                    radius: 14
                    color: trayManager.isDarkMode ? "#8b5cf6" : "#d1d5db"

                    Behavior on color { ColorAnimation { duration: 200 } }

                    Rectangle {
                        width: 22
                        height: 22
                        radius: 11
                        color: "#ffffff"
                        x: trayManager.isDarkMode ? parent.width - width - 3 : 3
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: trayManager.isDarkMode = !trayManager.isDarkMode
                    }
                }
            }

            // Auto Start Toggle
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "开机自启动"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#1a1a1a"
                    }

                    Text {
                        text: "系统启动时自动运行程序"
                        font.pixelSize: 11
                        color: "#6b7280"
                    }
                }

                // Toggle Switch
                Rectangle {
                    width: 50
                    height: 28
                    radius: 14
                    color: trayManager.autoStart ? "#3b82f6" : "#d1d5db"

                    Behavior on color { ColorAnimation { duration: 200 } }

                    Rectangle {
                        width: 22
                        height: 22
                        radius: 11
                        color: "#ffffff"
                        x: trayManager.autoStart ? parent.width - width - 3 : 3
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: trayManager.autoStart = !trayManager.autoStart
                    }
                }
            }

            // Shortcuts Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "快捷键设置"
                    font.pixelSize: 14
                    font.bold: true
                    color: "#1a1a1a"
                }

                Text {
                    text: "点击输入框后按下新的快捷键组合"
                    font.pixelSize: 11
                    color: "#6b7280"
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 8

                    // Commit shortcut
                    Text {
                        text: "一键提交推送"
                        font.pixelSize: 12
                        color: "#374151"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: 6
                        color: shortcutCommitInput.activeFocus ? "#eff6ff" : "#f9fafb"
                        border.color: shortcutCommitInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                        border.width: 1

                        TextInput {
                            id: shortcutCommitInput
                            anchors.fill: parent
                            anchors.margins: 10
                            text: trayManager.shortcutCommit
                            font.pixelSize: 12
                            color: "#1f2937"
                            readOnly: true
                            verticalAlignment: TextInput.AlignVCenter

                            Keys.onPressed: function(event) {
                                var keys = []
                                if (event.modifiers & Qt.ControlModifier) keys.push("Ctrl")
                                if (event.modifiers & Qt.ShiftModifier) keys.push("Shift")
                                if (event.modifiers & Qt.AltModifier) keys.push("Alt")
                                
                                var keyName = ""
                                if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
                                    keyName = String.fromCharCode(event.key)
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    keyName = "Return"
                                } else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) {
                                    keyName = "F" + (event.key - Qt.Key_F1 + 1)
                                }
                                
                                if (keys.length > 0 && keyName) {
                                    keys.push(keyName)
                                    trayManager.shortcutCommit = keys.join("+")
                                }
                                event.accepted = true
                            }
                        }
                    }

                    // Commit only shortcut
                    Text {
                        text: "提交"
                        font.pixelSize: 12
                        color: "#374151"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: 6
                        color: shortcutCommitOnlyInput.activeFocus ? "#eff6ff" : "#f9fafb"
                        border.color: shortcutCommitOnlyInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                        border.width: 1

                        TextInput {
                            id: shortcutCommitOnlyInput
                            anchors.fill: parent
                            anchors.margins: 10
                            text: trayManager.shortcutCommitOnly
                            font.pixelSize: 12
                            color: "#1f2937"
                            readOnly: true
                            verticalAlignment: TextInput.AlignVCenter

                            Keys.onPressed: function(event) {
                                var keys = []
                                if (event.modifiers & Qt.ControlModifier) keys.push("Ctrl")
                                if (event.modifiers & Qt.ShiftModifier) keys.push("Shift")
                                if (event.modifiers & Qt.AltModifier) keys.push("Alt")
                                
                                var keyName = ""
                                if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
                                    keyName = String.fromCharCode(event.key)
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    keyName = "Return"
                                } else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) {
                                    keyName = "F" + (event.key - Qt.Key_F1 + 1)
                                }
                                
                                if (keys.length > 0 && keyName) {
                                    keys.push(keyName)
                                    trayManager.shortcutCommitOnly = keys.join("+")
                                }
                                event.accepted = true
                            }
                        }
                    }

                    // Refresh shortcut
                    Text {
                        text: "刷新"
                        font.pixelSize: 12
                        color: "#374151"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: 6
                        color: shortcutRefreshInput.activeFocus ? "#eff6ff" : "#f9fafb"
                        border.color: shortcutRefreshInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                        border.width: 1

                        TextInput {
                            id: shortcutRefreshInput
                            anchors.fill: parent
                            anchors.margins: 10
                            text: trayManager.shortcutRefresh
                            font.pixelSize: 12
                            color: "#1f2937"
                            readOnly: true
                            verticalAlignment: TextInput.AlignVCenter

                            Keys.onPressed: function(event) {
                                var keys = []
                                if (event.modifiers & Qt.ControlModifier) keys.push("Ctrl")
                                if (event.modifiers & Qt.ShiftModifier) keys.push("Shift")
                                if (event.modifiers & Qt.AltModifier) keys.push("Alt")
                                
                                var keyName = ""
                                if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
                                    keyName = String.fromCharCode(event.key)
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    keyName = "Return"
                                } else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) {
                                    keyName = "F" + (event.key - Qt.Key_F1 + 1)
                                }
                                
                                if (keys.length > 0 && keyName) {
                                    keys.push(keyName)
                                    trayManager.shortcutRefresh = keys.join("+")
                                }
                                event.accepted = true
                            }
                        }
                    }

                    // Push shortcut
                    Text {
                        text: "推送"
                        font.pixelSize: 12
                        color: "#374151"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: 6
                        color: shortcutPushInput.activeFocus ? "#eff6ff" : "#f9fafb"
                        border.color: shortcutPushInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                        border.width: 1

                        TextInput {
                            id: shortcutPushInput
                            anchors.fill: parent
                            anchors.margins: 10
                            text: trayManager.shortcutPush
                            font.pixelSize: 12
                            color: "#1f2937"
                            readOnly: true
                            verticalAlignment: TextInput.AlignVCenter

                            Keys.onPressed: function(event) {
                                var keys = []
                                if (event.modifiers & Qt.ControlModifier) keys.push("Ctrl")
                                if (event.modifiers & Qt.ShiftModifier) keys.push("Shift")
                                if (event.modifiers & Qt.AltModifier) keys.push("Alt")
                                
                                var keyName = ""
                                if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
                                    keyName = String.fromCharCode(event.key)
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    keyName = "Return"
                                } else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) {
                                    keyName = "F" + (event.key - Qt.Key_F1 + 1)
                                }
                                
                                if (keys.length > 0 && keyName) {
                                    keys.push(keyName)
                                    trayManager.shortcutPush = keys.join("+")
                                }
                                event.accepted = true
                            }
                        }
                    }

                    // Pull shortcut
                    Text {
                        text: "拉取"
                        font.pixelSize: 12
                        color: "#374151"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: 6
                        color: shortcutPullInput.activeFocus ? "#eff6ff" : "#f9fafb"
                        border.color: shortcutPullInput.activeFocus ? "#3b82f6" : "#e5e7eb"
                        border.width: 1

                        TextInput {
                            id: shortcutPullInput
                            anchors.fill: parent
                            anchors.margins: 10
                            text: trayManager.shortcutPull
                            font.pixelSize: 12
                            color: "#1f2937"
                            readOnly: true
                            verticalAlignment: TextInput.AlignVCenter

                            Keys.onPressed: function(event) {
                                var keys = []
                                if (event.modifiers & Qt.ControlModifier) keys.push("Ctrl")
                                if (event.modifiers & Qt.ShiftModifier) keys.push("Shift")
                                if (event.modifiers & Qt.AltModifier) keys.push("Alt")
                                
                                var keyName = ""
                                if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
                                    keyName = String.fromCharCode(event.key)
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    keyName = "Return"
                                } else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) {
                                    keyName = "F" + (event.key - Qt.Key_F1 + 1)
                                }
                                
                                if (keys.length > 0 && keyName) {
                                    keys.push(keyName)
                                    trayManager.shortcutPull = keys.join("+")
                                }
                                event.accepted = true
                            }
                        }
                    }
                }
            }

            // Buttons
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 30
                spacing: 12

                Item { Layout.fillWidth: true }

                Text {
                    text: "取消"
                    font.pixelSize: 13
                    color: settingsCancelArea.containsMouse ? "#3b82f6" : "#6b7280"
                    Behavior on color { ColorAnimation { duration: 150 } }
                    MouseArea {
                        id: settingsCancelArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: settingsDialog.close()
                    }
                }

                ActionButton {
                    text: "保存"
                    icon: "\uf0c7"
                    fontFamily: fontAwesome.name
                    primary: true
                    onClicked: {
                        trayManager.commitTemplate = commitTemplateInput.text
                        settingsDialog.close()
                        toast.show("设置已保存", "success")
                    }
                }
            }
            }  // End ColumnLayout settingsContent
        }  // End Flickable

        onOpened: {
            commitTemplateInput.text = trayManager.commitTemplate
        }
    }

    // Close confirmation dialog
    Dialog {
        id: closeDialog
        title: ""
        anchors.centerIn: parent
        width: 400
        modal: true
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: "#F8FBFE"
            radius: 12
        }

        header: MacTitleBar {
            title: "关闭程序"
            onCloseClicked: closeDialog.close()
        }

        property bool rememberChoice: false

        contentItem: ColumnLayout {
            spacing: 20

            // Question icon and text
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

                Rectangle {
                    width: 48
                    height: 48
                    radius: 24
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#4158D0" }
                        GradientStop { position: 0.5; color: "#C850C0" }
                        GradientStop { position: 1.0; color: "#FFCC70" }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "\uf059"
                        font.family: fontAwesome.name
                        font.pixelSize: 24
                        color: "#ffffff"
                    }
                }

                Text {
                    text: "您想要退出程序还是最小化到托盘？"
                    font.pixelSize: 14
                    color: "#1a1a1a"
                }
            }

            // Remember choice checkbox - centered
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

                // Fancy checkbox
                Item {
                    width: 36
                    height: 36

                    Rectangle {
                        id: checkboxBg
                        anchors.fill: parent
                        radius: 18
                        
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: "#4158D0" }
                            GradientStop { position: 0.46; color: "#C850C0" }
                            GradientStop { position: 1.0; color: "#FFCC70" }
                        }

                        // Inner white circle (unchecked state)
                        Rectangle {
                            anchors.centerIn: parent
                            width: closeDialog.rememberChoice ? 0 : 26
                            height: closeDialog.rememberChoice ? 0 : 26
                            radius: width / 2
                            color: "#ffffff"

                            Behavior on width { NumberAnimation { duration: 200 } }
                            Behavior on height { NumberAnimation { duration: 200 } }
                        }

                        // Checkmark
                        Item {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: -2
                            anchors.verticalCenterOffset: -2
                            width: 20
                            height: 20
                            rotation: -40
                            opacity: closeDialog.rememberChoice ? 1 : 0

                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            Rectangle {
                                x: 0
                                y: 6
                                width: 4
                                height: closeDialog.rememberChoice ? 10 : 0
                                radius: 2
                                color: "#ffffff"

                                Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            }

                            Rectangle {
                                x: 0
                                y: 12
                                width: closeDialog.rememberChoice ? 18 : 0
                                height: 4
                                radius: 2
                                color: "#ffffff"

                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            }
                        }

                        // Scale animation on press
                        scale: checkboxArea.pressed ? 0.9 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        MouseArea {
                            id: checkboxArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: closeDialog.rememberChoice = !closeDialog.rememberChoice
                        }
                    }
                }

                Text {
                    text: "记住我的选择"
                    font.pixelSize: 13
                    color: "#1a1a1a"

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: closeDialog.rememberChoice = !closeDialog.rememberChoice
                    }
                }
            }

            // Buttons - centered
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                Layout.bottomMargin: 40
                spacing: 16

                Item { Layout.fillWidth: true }

                ActionButton {
                    text: "退出程序"
                    icon: "\uf011"
                    fontFamily: fontAwesome.name
                    onClicked: {
                        if (closeDialog.rememberChoice) {
                            trayManager.rememberChoice = true
                            trayManager.minimizeToTray = false
                        }
                        closeDialog.close()
                        trayManager.quitApp()
                    }
                }

                ActionButton {
                    text: "最小化到托盘"
                    icon: "\uf2d1"
                    fontFamily: fontAwesome.name
                    primary: true
                    onClicked: {
                        if (closeDialog.rememberChoice) {
                            trayManager.rememberChoice = true
                            trayManager.minimizeToTray = true
                        }
                        closeDialog.close()
                        window.hide()
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
