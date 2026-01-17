import QtQuick
import QtQuick.Controls
import QtQuick.Effects

Rectangle {
    id: root
    width: 70
    height: 50
    radius: 12
    
    property string icon: ""
    property string fontFamily: ""
    property string tooltip: ""
    property bool rotating: false
    property bool checked: false

    // Split tooltip into two lines (2 chars each)
    property string line1: tooltip.length > 2 ? tooltip.substring(0, 2) : tooltip
    property string line2: tooltip.length > 2 ? tooltip.substring(2) : ""

    signal clicked()

    // Neumorphism gradient background
    gradient: Gradient {
        GradientStop { position: 0.0; color: btnArea.containsMouse ? "#f0f0f0" : (root.checked ? "#3b82f6" : "#ffffff") }
        GradientStop { position: 1.0; color: btnArea.containsMouse ? "#ffffff" : (root.checked ? "#2563eb" : "#e6e6e6") }
    }

    // Neumorphism shadow effect
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: root.checked ? "#3b82f680" : "#00000026"
        shadowHorizontalOffset: root.checked ? 0 : 3
        shadowVerticalOffset: root.checked ? 0 : 3
        shadowBlur: root.checked ? 0.3 : 0.2
    }

    // Press animation
    transform: Translate {
        y: btnArea.pressed ? 2 : (btnArea.containsMouse && !root.checked ? -1 : (root.checked ? 2 : 0))
        Behavior on y { NumberAnimation { duration: 100 } }
    }

    // Icon (shown when not hovered)
    Text {
        id: iconText
        anchors.centerIn: parent
        text: root.icon
        font.family: root.fontFamily
        font.pixelSize: 18
        color: root.checked ? "white" : "#2d3748"
        opacity: btnArea.containsMouse && root.tooltip !== "" ? 0 : 1
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 150 } }

        RotationAnimation on rotation {
            running: root.rotating
            from: 0
            to: 360
            duration: 1000
            loops: Animation.Infinite
        }
    }

    // Label text (shown when hovered) - two lines
    Column {
        anchors.centerIn: parent
        spacing: 0
        opacity: btnArea.containsMouse && root.tooltip !== "" ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 150 } }

        Text {
            text: root.line1
            font.pixelSize: 12
            font.weight: root.checked ? Font.DemiBold : Font.Medium
            color: root.checked ? "white" : "#2d3748"
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: root.line2
            font.pixelSize: 12
            font.weight: root.checked ? Font.DemiBold : Font.Medium
            color: root.checked ? "white" : "#2d3748"
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.line2 !== ""
        }
    }

    // Ripple effect on click
    Rectangle {
        id: ripple
        anchors.centerIn: parent
        width: 0
        height: width
        radius: width / 2
        color: root.checked ? Qt.rgba(255, 255, 255, 0.3) : Qt.rgba(59, 130, 246, 0.2)
        opacity: 0

        ParallelAnimation {
            id: rippleAnim
            NumberAnimation { target: ripple; property: "width"; from: 0; to: root.width * 2; duration: 400; easing.type: Easing.OutQuad }
            NumberAnimation { target: ripple; property: "opacity"; from: 0.6; to: 0; duration: 400; easing.type: Easing.OutQuad }
        }
    }

    MouseArea {
        id: btnArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            rippleAnim.start()
            root.clicked()
        }
    }
}
