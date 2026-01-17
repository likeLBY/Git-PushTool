import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    height: 48
    radius: 10
    color: root.selected ? (root.accentColor + "15") : (hoverHandler.hovered ? "#f8fafc" : "transparent")
    border.color: root.selected ? root.accentColor : (hoverHandler.hovered ? "#e2e8f0" : "transparent")
    border.width: 1

    property string fileName: ""
    property string filePath: ""
    property string status: "modified"
    property string actionText: "Stage"
    property bool showDiscard: false
    property string fontAwesomeName: ""
    property bool enableDrag: false
    property bool isStaged: false
    property bool selected: false
    property bool showCheckbox: false
    property string fileSize: "0 B"

    signal actionClicked()
    signal discardClicked()
    signal deleteFileClicked()
    signal fileClicked()
    signal openLocationClicked()
    signal checkboxClicked()
    signal addToGitignore(string pattern)

    property color accentColor: isStaged ? "#10b981" : "#3b82f6"
    property bool isNewFile: status === "added"

    Behavior on color { ColorAnimation { duration: 100 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    HoverHandler {
        id: hoverHandler
    }
    
    MouseArea {
        id: fileMouseArea
        anchors.left: parent.left
        anchors.right: actionArea.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.rightMargin: 8
        anchors.leftMargin: 36
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                contextMenu.popup()
            } else {
                root.fileClicked()
            }
        }
    }

    Menu {
        id: contextMenu
        
        MenuItem {
            text: "打开文件所在目录"
            onTriggered: root.openLocationClicked()
        }
        
        MenuItem {
            text: "查看差异"
            onTriggered: root.fileClicked()
        }
        
        MenuSeparator {}
        
        MenuItem {
            text: root.actionText
            onTriggered: root.actionClicked()
        }
        
        MenuItem {
            text: root.isNewFile ? "删除文件" : "撤销更改"
            visible: root.showDiscard
            onTriggered: {
                if (root.isNewFile) {
                    root.deleteFileClicked()
                } else {
                    root.discardClicked()
                }
            }
        }

        MenuSeparator {}

        Menu {
            title: "添加到 .gitignore"

            MenuItem {
                text: "忽略此文件"
                onTriggered: root.addToGitignore(root.filePath)
            }

            MenuItem {
                text: "忽略同类型文件 (*." + root.fileName.split('.').pop() + ")"
                visible: root.fileName.indexOf('.') > 0
                onTriggered: root.addToGitignore("*." + root.fileName.split('.').pop())
            }

            MenuItem {
                property string folderPath: root.filePath.indexOf('/') > 0 ? root.filePath.substring(0, root.filePath.lastIndexOf('/')) + "/" : ""
                text: "忽略所在文件夹 (" + (folderPath || "根目录") + ")"
                visible: folderPath !== ""
                onTriggered: root.addToGitignore(folderPath)
            }
        }
    }
    
    Item {
        id: actionArea
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 100
    }
    
    function getFileIcon(fileName) {
        var ext = fileName.split('.').pop().toLowerCase()
        if (["js", "jsx", "ts", "tsx"].includes(ext)) return "\uf3b8"
        if (["py", "pyw"].includes(ext)) return "\uf3e2"
        if (["java", "jar"].includes(ext)) return "\uf4e4"
        if (["c", "cpp", "cc", "cxx", "h", "hpp"].includes(ext)) return "\ue61d"
        if (["html", "htm"].includes(ext)) return "\uf13b"
        if (["css", "scss", "sass", "less"].includes(ext)) return "\uf13c"
        if (["vue"].includes(ext)) return "\uf41f"
        if (["json"].includes(ext)) return "\uf1c9"
        if (["md", "markdown"].includes(ext)) return "\uf48a"
        if (["txt", "text"].includes(ext)) return "\uf15c"
        if (["pdf"].includes(ext)) return "\uf1c1"
        if (["doc", "docx"].includes(ext)) return "\uf1c2"
        if (["xls", "xlsx"].includes(ext)) return "\uf1c3"
        if (["png", "jpg", "jpeg", "gif", "bmp", "svg", "webp", "ico"].includes(ext)) return "\uf1c5"
        if (["mp3", "wav", "flac", "aac", "ogg"].includes(ext)) return "\uf1c7"
        if (["mp4", "avi", "mov", "mkv", "webm"].includes(ext)) return "\uf1c8"
        if (["zip", "rar", "7z", "tar", "gz", "bz2"].includes(ext)) return "\uf1c6"
        if (["sh", "bash", "zsh", "bat", "cmd", "ps1"].includes(ext)) return "\uf120"
        if (["qml"].includes(ext)) return "\uf1c9"
        return "\uf15b"
    }
    
    function getFileIconColor(fileName) {
        var ext = fileName.split('.').pop().toLowerCase()
        if (["js", "jsx"].includes(ext)) return "#f7df1e"
        if (["ts", "tsx"].includes(ext)) return "#3178c6"
        if (["py", "pyw"].includes(ext)) return "#3776ab"
        if (["java", "jar"].includes(ext)) return "#ed8b00"
        if (["c", "cpp", "cc", "cxx", "h", "hpp"].includes(ext)) return "#00599c"
        if (["html", "htm"].includes(ext)) return "#e34f26"
        if (["css", "scss", "sass", "less"].includes(ext)) return "#1572b6"
        if (["vue"].includes(ext)) return "#42b883"
        if (["json"].includes(ext)) return "#cbcb41"
        if (["md", "markdown"].includes(ext)) return "#083fa1"
        if (["png", "jpg", "jpeg", "gif", "svg"].includes(ext)) return "#a074c4"
        if (["zip", "rar", "7z"].includes(ext)) return "#f9a825"
        if (["sh", "bash", "bat"].includes(ext)) return "#4eaa25"
        if (["qml"].includes(ext)) return "#41cd52"
        return "#6b7280"
    }

    function getStatusInfo(status) {
        switch(status) {
            case "added": return { icon: "\uf067", color: "#10b981", bg: "#d1fae5", text: "新增" }
            case "deleted": return { icon: "\uf068", color: "#ef4444", bg: "#fee2e2", text: "删除" }
            case "renamed": return { icon: "\uf074", color: "#f59e0b", bg: "#fef3c7", text: "重命名" }
            default: return { icon: "\uf040", color: "#3b82f6", bg: "#dbeafe", text: "修改" }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 12
        spacing: 8

        // Heart checkbox
        Item {
            visible: root.showCheckbox
            width: 24
            height: 24

            // Outline heart (always visible when not selected)
            Text {
                id: heartOutline
                anchors.centerIn: parent
                text: "\uf004"
                font.family: root.fontAwesomeName
                font.pixelSize: 16
                color: heartArea.containsMouse ? root.accentColor : "#d1d5db"
                opacity: root.selected ? 0 : 1
                
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            // Filled heart (visible when selected)
            Text {
                id: heartFilled
                anchors.centerIn: parent
                text: "\uf004"
                font.family: root.fontAwesomeName
                font.pixelSize: 16
                color: root.accentColor
                opacity: root.selected ? 1 : 0
                scale: root.selected ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 200 } }
                Behavior on scale { 
                    NumberAnimation { 
                        duration: 300
                        easing.type: Easing.OutBack
                        easing.overshoot: 2
                    } 
                }
            }

            // Celebrate particles
            Repeater {
                model: 6
                
                Rectangle {
                    id: particle
                    width: 4
                    height: 4
                    radius: 2
                    color: root.accentColor
                    x: parent.width / 2 - 2
                    y: parent.height / 2 - 2
                    opacity: 0
                    
                    property real angle: index * 60
                    property bool animating: false

                    states: State {
                        name: "explode"
                        when: particle.animating
                        PropertyChanges {
                            target: particle
                            x: parent.width / 2 - 2 + Math.cos(particle.angle * Math.PI / 180) * 16
                            y: parent.height / 2 - 2 + Math.sin(particle.angle * Math.PI / 180) * 16
                            opacity: 0
                            scale: 0.5
                        }
                    }

                    transitions: Transition {
                        to: "explode"
                        SequentialAnimation {
                            PropertyAction { property: "opacity"; value: 1 }
                            ParallelAnimation {
                                NumberAnimation { property: "x"; duration: 400; easing.type: Easing.OutQuad }
                                NumberAnimation { property: "y"; duration: 400; easing.type: Easing.OutQuad }
                                NumberAnimation { property: "opacity"; duration: 400 }
                                NumberAnimation { property: "scale"; duration: 400 }
                            }
                            PropertyAction { property: "animating"; value: false }
                        }
                    }

                    Connections {
                        target: root
                        function onSelectedChanged() {
                            if (root.selected) {
                                particle.animating = true
                            }
                        }
                    }
                }
            }

            MouseArea {
                id: heartArea
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.checkboxClicked()
            }
        }

        // File icon
        Rectangle {
            width: 32
            height: 32
            radius: 8
            color: "#f8fafc"

            Text {
                anchors.centerIn: parent
                text: getFileIcon(root.fileName)
                font.family: root.fontAwesomeName
                font.pixelSize: 14
                color: getFileIconColor(root.fileName)
            }
        }

        // File info
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                spacing: 6

                Text {
                    text: root.fileName
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: "#1f2937"
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }

                Rectangle {
                    width: statusRow.width + 8
                    height: 18
                    radius: 4
                    color: getStatusInfo(root.status).bg

                    RowLayout {
                        id: statusRow
                        anchors.centerIn: parent
                        spacing: 3

                        Text {
                            text: getStatusInfo(root.status).icon
                            font.family: root.fontAwesomeName
                            font.pixelSize: 8
                            color: getStatusInfo(root.status).color
                        }

                        Text {
                            text: getStatusInfo(root.status).text
                            font.pixelSize: 9
                            font.weight: Font.Medium
                            color: getStatusInfo(root.status).color
                        }
                    }
                }
            }

            RowLayout {
                spacing: 8
                visible: root.filePath !== root.fileName || root.fileSize !== "0 B"

                Text {
                    text: root.filePath
                    font.pixelSize: 11
                    color: "#9ca3af"
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                    visible: root.filePath !== root.fileName
                }

                Text {
                    text: root.fileSize
                    font.pixelSize: 11
                    color: "#6b7280"
                    visible: root.fileSize !== "0 B"
                }
            }
        }

        // Action buttons
        RowLayout {
            spacing: 6
            opacity: hoverHandler.hovered ? 1 : 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: 150 } }

            Rectangle {
                visible: root.showDiscard
                width: 28
                height: 28
                radius: 6
                color: discardHover.hovered ? "#fee2e2" : "#f1f5f9"

                Text {
                    anchors.centerIn: parent
                    text: root.isNewFile ? "\uf1f8" : "\uf2ea"
                    font.family: root.fontAwesomeName
                    font.pixelSize: 11
                    color: discardHover.hovered ? "#ef4444" : "#64748b"
                }

                HoverHandler { id: discardHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: root.isNewFile ? root.deleteFileClicked() : root.discardClicked()
                }

                ToolTip.visible: discardHover.hovered
                ToolTip.text: root.isNewFile ? "删除文件" : "撤销更改"
                ToolTip.delay: 500
            }

            Rectangle {
                width: 28
                height: 28
                radius: 6
                color: actionHover.hovered ? root.accentColor : "#f1f5f9"

                Text {
                    anchors.centerIn: parent
                    text: root.isStaged ? "\uf068" : "\uf067"
                    font.family: root.fontAwesomeName
                    font.pixelSize: 11
                    color: actionHover.hovered ? "#ffffff" : "#64748b"
                }

                HoverHandler { id: actionHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.actionClicked() }

                ToolTip.visible: actionHover.hovered
                ToolTip.text: root.actionText
                ToolTip.delay: 500
            }
        }
    }
}
