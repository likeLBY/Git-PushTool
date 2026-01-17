import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    width: buttonContent.width + arrowCircle.width + 50
    height: 44
    radius: 12
    color: enabled ? (primary ? "#FFD700" : "#FFEB3B") : "#8B8B7A"
    border.color: "#1a1a1a"
    border.width: 2
    clip: true

    property string text: "Button"
    property string icon: ""
    property string fontFamily: ""
    property bool primary: false
    property alias hovered: btnArea.containsMouse

    signal clicked()

    // Box shadow effect via transform - only when enabled
    transform: Translate {
        x: enabled ? (btnArea.pressed ? 1 : (btnArea.containsMouse ? 1 : 0)) : 0
        y: enabled ? (btnArea.pressed ? 2 : (btnArea.containsMouse ? 1 : 0)) : 0
        Behavior on x { NumberAnimation { duration: 150 } }
        Behavior on y { NumberAnimation { duration: 150 } }
    }

    // Shadow rectangle behind - smaller shadow
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: enabled ? (btnArea.containsMouse ? 1 : 2) : 1
        anchors.topMargin: enabled ? (btnArea.containsMouse ? 2 : 3) : 2
        radius: parent.radius
        color: "#1a1a1a"
        z: -1
    }

    // Pink slide-in background - only when enabled
    Rectangle {
        id: pinkBg
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: (enabled && btnArea.containsMouse) ? parent.width : 0
        radius: parent.radius
        color: primary ? "#FF69B4" : "#FFB6C1"
        z: 0

        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }
    }

    // Content
    RowLayout {
        id: buttonContent
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        z: 1

        Text {
            text: root.text
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: enabled ? "#1a1a1a" : "#4a4a4a"
        }
    }

    // Arrow circle on the right
    Rectangle {
        id: arrowCircle
        width: 32
        height: 32
        radius: 16
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        color: enabled ? (primary ? "#FF69B4" : "#FFB6C1") : "#6B6B5F"
        border.color: "#1a1a1a"
        border.width: 2
        z: 1
        clip: true

        transform: Translate {
            x: (enabled && btnArea.containsMouse) ? 3 : 0
            Behavior on x { NumberAnimation { duration: 250 } }
        }

        // Yellow slide-in for arrow circle
        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: (enabled && btnArea.containsMouse) ? parent.width : 0
            radius: parent.radius
            color: primary ? "#FFD700" : "#FFEB3B"

            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
        }

        // Icon - use arrow symbol if no fontFamily
        Text {
            anchors.centerIn: parent
            text: root.fontFamily !== "" ? (root.icon !== "" ? root.icon : "\uf061") : "→"
            font.family: root.fontFamily !== "" ? root.fontFamily : undefined
            font.pixelSize: root.fontFamily !== "" ? 12 : 16
            font.bold: root.fontFamily === ""
            color: enabled ? "#1a1a1a" : "#4a4a4a"
            z: 1
        }
    }

    MouseArea {
        id: btnArea
        anchors.fill: parent
        hoverEnabled: enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.enabled) root.clicked()
    }
}
