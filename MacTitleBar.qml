import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    width: parent.width
    height: 40
    color: "transparent"
    
    property string title: ""
    signal closeClicked()
    
    // macOS style traffic lights
    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        
        Rectangle {
            width: 12
            height: 12
            radius: 6
            color: closeHover.containsMouse ? "#ff3b30" : "#ff605c"
            
            Text {
                anchors.centerIn: parent
                text: "×"
                font.pixelSize: 10
                font.bold: true
                color: "#4a0000"
                opacity: closeHover.containsMouse ? 1 : 0
            }
            
            HoverHandler {
                id: closeHover
            }
            
            TapHandler {
                onTapped: root.closeClicked()
            }
        }
        Rectangle {
            width: 12
            height: 12
            radius: 6
            color: "#ffbd44"
        }
        Rectangle {
            width: 12
            height: 12
            radius: 6
            color: "#00ca4e"
        }
    }
    
    Text {
        anchors.centerIn: parent
        text: root.title
        font.pixelSize: 14
        font.weight: Font.Medium
        color: "#1a1a1a"
    }
}
