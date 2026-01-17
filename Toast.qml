import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: root
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: 50
    width: toastContent.width
    height: toastContent.height
    opacity: 0
    visible: opacity > 0

    property string message: ""
    property string type: "success"
    property string fontAwesomeName: ""

    function show(msg, msgType) {
        message = msg
        type = msgType || "info"
        showAnim.start()
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: hideAnim.start()
    }

    NumberAnimation {
        id: showAnim
        target: root
        property: "opacity"
        to: 1
        duration: 150
    }

    NumberAnimation {
        id: hideAnim
        target: root
        property: "opacity"
        to: 0
        duration: 150
    }

    Rectangle {
        id: toastContent
        width: toastLayout.width + 40
        height: 48
        radius: 24
        color: {
            switch(root.type) {
                case "success": return "#10b981"
                case "error": return "#ef4444"
                default: return "#3b82f6"
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#00000040"
            shadowVerticalOffset: 4
            shadowBlur: 0.3
        }

        RowLayout {
            id: toastLayout
            anchors.centerIn: parent
            spacing: 10

            Text {
                text: {
                    switch(root.type) {
                        case "success": return "\uf00c"
                        case "error": return "\uf00d"
                        default: return "\uf05a"
                    }
                }
                font.family: root.fontAwesomeName
                font.pixelSize: 16
                color: "#ffffff"
            }

            Text {
                text: root.message
                font.pixelSize: 14
                font.weight: Font.Medium
                color: "#ffffff"
            }
        }
    }
}
