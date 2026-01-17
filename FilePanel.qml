import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: root
    
    property string title: "Files"
    property string subtitle: ""
    property var files: []
    property string emptyText: "No files"
    property string actionText: "Action"
    property string actionAllText: "Action All"
    property string discardAllText: ""
    property bool isStaged: false
    property bool showDiscard: false
    property string fontAwesomeName: ""
    property string searchFilter: ""
    property color accentColor: isStaged ? "#10b981" : "#3b82f6"
    property color accentColorLight: isStaged ? "#d1fae5" : "#dbeafe"
    property color cardBgColor: isStaged ? "#f0fdf4" : "#eff6ff"

    // Selection management
    property var selectedPaths: []
    property bool hasSelection: selectedPaths.length > 0
    property bool allSelected: files.length > 0 && selectedPaths.length === files.length
    property var lastFilePaths: []

    function toggleSelection(path) {
        var newSelection = selectedPaths.slice()
        var idx = newSelection.indexOf(path)
        if (idx >= 0) {
            newSelection.splice(idx, 1)
        } else {
            newSelection.push(path)
        }
        selectedPaths = newSelection
    }

    function selectAll() {
        selectedPaths = files.map(f => f.path)
    }

    function clearSelection() {
        selectedPaths = []
    }

    function stageSelected() {
        if (hasSelection && !isStaged) {
            batchAction(selectedPaths.slice())
            clearSelection()
        }
    }

    function unstageSelected() {
        if (hasSelection && isStaged) {
            batchAction(selectedPaths.slice())
            clearSelection()
        }
    }

    function isSelected(path) {
        return selectedPaths.indexOf(path) >= 0
    }

    // Clear selection only when files actually change (not just re-render)
    onFilesChanged: {
        var currentPaths = files.map(f => f.path).sort().join(",")
        var lastPaths = lastFilePaths.sort().join(",")
        if (currentPaths !== lastPaths) {
            selectedPaths = []
            lastFilePaths = files.map(f => f.path)
        }
    }

    // Filtered files based on search
    property var filteredFiles: {
        if (!searchFilter || searchFilter.trim() === "") {
            return files
        }
        var keyword = searchFilter.toLowerCase()
        return files.filter(function(file) {
            return file.name.toLowerCase().indexOf(keyword) >= 0 || 
                   file.path.toLowerCase().indexOf(keyword) >= 0
        })
    }

    signal fileAction(string path)
    signal batchAction(var paths)
    signal allAction()
    signal discardAllAction()
    signal discardFile(string path)
    signal fileClicked(string path, bool staged)
    signal openFileLocation(string path)
    signal deleteNewFile(string path)
    signal addToGitignore(string pattern)
    signal openGitignoreManager()

    property bool acceptDrop: false

    // Main card
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: root.cardBgColor
        
        // Subtle shadow
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#20000000"
            shadowBlur: 0.8
            shadowVerticalOffset: 2
            shadowHorizontalOffset: 0
        }

        // Left accent bar
        Rectangle {
            width: 4
            height: parent.height - 32
            anchors.left: parent.left
            anchors.leftMargin: 0
            anchors.verticalCenter: parent.verticalCenter
            radius: 2
            color: root.accentColor
            opacity: root.files.length > 0 ? 1 : 0.3
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 12

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Icon badge / Select all checkbox
                Rectangle {
                    width: 36
                    height: 36
                    radius: 10
                    color: root.hasSelection ? root.accentColor : root.accentColorLight
                    
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: root.hasSelection ? (root.allSelected ? "\uf14a" : "\uf146") : (root.isStaged ? "\uf00c" : "\uf15c")
                        font.family: root.fontAwesomeName
                        font.pixelSize: 14
                        color: root.hasSelection ? "#ffffff" : root.accentColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: root.files.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (root.files.length > 0) {
                                if (root.allSelected) {
                                    root.clearSelection()
                                } else {
                                    root.selectAll()
                                }
                            }
                        }
                    }

                    ToolTip.visible: root.files.length > 0 && selectAllHover.hovered
                    ToolTip.text: root.allSelected ? "取消全选" : "全选"
                    ToolTip.delay: 500

                    HoverHandler {
                        id: selectAllHover
                    }
                }

                // Title and count
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.title
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: "#1f2937"
                    }

                    RowLayout {
                        spacing: 6

                        Rectangle {
                            width: countText.width + 12
                            height: 18
                            radius: 9
                            color: root.files.length > 0 ? root.accentColorLight : "#f3f4f6"

                            Text {
                                id: countText
                                anchors.centerIn: parent
                                text: root.hasSelection ? root.selectedPaths.length + "/" + root.files.length : root.files.length
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: root.files.length > 0 ? root.accentColor : "#9ca3af"
                            }
                        }

                        Text {
                            text: root.hasSelection ? "已选中" : "个文件"
                            font.pixelSize: 11
                            color: "#9ca3af"
                        }
                    }
                }

                // Action buttons
                RowLayout {
                    spacing: 8

                    // Search button
                    Rectangle {
                        visible: root.files.length > 3
                        width: 32
                        height: 32
                        radius: 8
                        color: searchBtnArea.containsMouse ? "#f3f4f6" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "\uf002"
                            font.family: root.fontAwesomeName
                            font.pixelSize: 12
                            color: searchInput.visible ? root.accentColor : "#6b7280"
                        }

                        MouseArea {
                            id: searchBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchInput.visible = !searchInput.visible
                                if (searchInput.visible) {
                                    searchField.forceActiveFocus()
                                } else {
                                    root.searchFilter = ""
                                    searchField.text = ""
                                }
                            }
                        }

                        ToolTip.visible: searchBtnArea.containsMouse
                        ToolTip.text: "搜索文件"
                        ToolTip.delay: 500
                    }

                    // Gitignore manager button
                    Rectangle {
                        width: gitignoreBtnText.width + 16
                        height: 32
                        radius: 8
                        color: gitignoreBtnArea.containsMouse ? "#f3f4f6" : "transparent"

                        Text {
                            id: gitignoreBtnText
                            anchors.centerIn: parent
                            text: ".gitignore"
                            font.pixelSize: 11
                            color: gitignoreBtnArea.containsMouse ? root.accentColor : "#6b7280"
                        }

                        MouseArea {
                            id: gitignoreBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openGitignoreManager()
                        }

                        ToolTip.visible: gitignoreBtnArea.containsMouse
                        ToolTip.text: "管理 .gitignore"
                        ToolTip.delay: 500
                    }

                    // Action all / batch button
                    Rectangle {
                        visible: root.files.length > 0
                        width: Math.max(allBtnRow.width + 24, 90)
                        height: 32
                        radius: 8
                        color: allBtnArea.containsMouse ? root.accentColorLight : "#f9fafb"
                        border.color: allBtnArea.containsMouse ? root.accentColor : "#e5e7eb"
                        border.width: 1

                        RowLayout {
                            id: allBtnRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "\uf004"
                                font.family: root.fontAwesomeName
                                font.pixelSize: 10
                                color: root.accentColor
                            }

                            Text {
                                text: root.hasSelection ? (root.isStaged ? "取消" : "暂存") + " (" + root.selectedPaths.length + ")" : root.actionAllText
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: allBtnArea.containsMouse ? root.accentColor : "#4b5563"
                            }
                        }

                        MouseArea {
                            id: allBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.hasSelection) {
                                    root.batchAction(root.selectedPaths.slice())
                                    root.clearSelection()
                                } else {
                                    root.allAction()
                                }
                            }
                        }
                    }

                    // Clear selection button
                    Rectangle {
                        visible: root.hasSelection
                        width: 32
                        height: 32
                        radius: 8
                        color: clearSelBtnArea.containsMouse ? "#fef2f2" : "#f9fafb"
                        border.color: clearSelBtnArea.containsMouse ? "#ef4444" : "#e5e7eb"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00d"
                            font.family: root.fontAwesomeName
                            font.pixelSize: 10
                            color: clearSelBtnArea.containsMouse ? "#ef4444" : "#6b7280"
                        }

                        MouseArea {
                            id: clearSelBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.clearSelection()
                        }

                        ToolTip.visible: clearSelBtnArea.containsMouse
                        ToolTip.text: "取消选择"
                        ToolTip.delay: 500
                    }

                    // Discard all button
                    Rectangle {
                        visible: root.files.length > 0 && root.discardAllText !== "" && !root.hasSelection
                        width: discardBtnRow.width + 16
                        height: 32
                        radius: 8
                        color: discardAllBtnArea.containsMouse ? "#fef2f2" : "#f9fafb"
                        border.color: discardAllBtnArea.containsMouse ? "#ef4444" : "#e5e7eb"
                        border.width: 1

                        RowLayout {
                            id: discardBtnRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "\uf2ea"
                                font.family: root.fontAwesomeName
                                font.pixelSize: 9
                                color: "#ef4444"
                            }

                            Text {
                                text: root.discardAllText
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: discardAllBtnArea.containsMouse ? "#ef4444" : "#4b5563"
                            }
                        }

                        MouseArea {
                            id: discardAllBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.discardAllAction()
                        }
                    }
                }
            }

            // Search input
            Rectangle {
                id: searchInput
                Layout.fillWidth: true
                height: 36
                radius: 8
                color: "#f9fafb"
                border.color: searchField.activeFocus ? root.accentColor : "#e5e7eb"
                border.width: 1
                visible: false

                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Text {
                        text: "\uf002"
                        font.family: root.fontAwesomeName
                        font.pixelSize: 12
                        color: "#9ca3af"
                    }

                    TextInput {
                        id: searchField
                        Layout.fillWidth: true
                        font.pixelSize: 13
                        color: "#1f2937"
                        clip: true
                        selectByMouse: true
                        onTextChanged: root.searchFilter = text

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 0
                            verticalAlignment: Text.AlignVCenter
                            text: "输入文件名搜索..."
                            font.pixelSize: 13
                            color: "#9ca3af"
                            visible: !searchField.text && !searchField.activeFocus
                        }
                    }

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        color: clearSearchArea.containsMouse ? "#fee2e2" : "transparent"
                        visible: searchField.text !== ""

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00d"
                            font.family: root.fontAwesomeName
                            font.pixelSize: 9
                            color: clearSearchArea.containsMouse ? "#ef4444" : "#9ca3af"
                        }

                        MouseArea {
                            id: clearSearchArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchField.text = ""
                                root.searchFilter = ""
                            }
                        }
                    }
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#f3f4f6"
            }

            // File list
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: root.filteredFiles

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 6
                    
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: "#d1d5db"
                        opacity: parent.active ? 1 : 0
                        
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                    
                    background: Rectangle {
                        color: "transparent"
                    }
                }

                delegate: FileItem {
                    width: ListView.view.width - 6
                    fileName: modelData.name
                    filePath: modelData.path
                    status: modelData.status
                    actionText: root.actionText
                    showDiscard: root.showDiscard && !root.isStaged
                    fontAwesomeName: root.fontAwesomeName
                    enableDrag: false
                    isStaged: root.isStaged
                    selected: root.isSelected(modelData.path)
                    showCheckbox: true
                    fileSize: modelData.sizeStr || "0 B"
                    onCheckboxClicked: root.toggleSelection(modelData.path)
                    onActionClicked: root.fileAction(modelData.path)
                    onDiscardClicked: root.discardFile(modelData.path)
                    onDeleteFileClicked: root.deleteNewFile(modelData.path)
                    onFileClicked: root.fileClicked(modelData.path, root.isStaged)
                    onOpenLocationClicked: root.openFileLocation(modelData.path)
                    onAddToGitignore: (pattern) => root.addToGitignore(pattern)
                }

                // Empty state
                Item {
                    anchors.fill: parent
                    visible: root.filteredFiles.length === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 12

                        Rectangle {
                            width: 64
                            height: 64
                            radius: 32
                            color: "#f9fafb"
                            Layout.alignment: Qt.AlignHCenter

                            Text {
                                anchors.centerIn: parent
                                text: root.searchFilter ? "\uf002" : (root.isStaged ? "\uf466" : "\uf15c")
                                font.family: root.fontAwesomeName
                                font.pixelSize: 24
                                color: "#d1d5db"
                            }
                        }

                        Text {
                            text: root.searchFilter ? "没有匹配的文件" : root.emptyText
                            font.pixelSize: 13
                            color: "#9ca3af"
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            visible: !root.searchFilter && !root.isStaged
                            text: "修改文件后会显示在这里"
                            font.pixelSize: 11
                            color: "#d1d5db"
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            visible: !root.searchFilter && root.isStaged
                            text: "暂存文件后会显示在这里"
                            font.pixelSize: 11
                            color: "#d1d5db"
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }
        }
    }
}
