import QtQuick
import QtQuick.Controls as QQC
import "Controls.js" as Controls

Item {
    id: button

    property string label: ""
    property string help: ""
    property string targetAddress: ""
    property string targetIdentity: ""
    property bool destructive: false
    property string pressedAddress: ""
    property string pressedIdentity: ""
    readonly property bool hovered: area.containsMouse
    signal activated(string address, string identity)

    Accessible.role: Accessible.Button
    Accessible.name: help || label
    Accessible.onPressAction: activated(targetAddress, targetIdentity)
    QQC.ToolTip.visible: hovered && help !== ""
    QQC.ToolTip.text: Controls.tooltipText(help)
    QQC.ToolTip.delay: 600
    QQC.ToolTip.timeout: 8000

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 4
        color: area.pressed ? (button.destructive ? "#a81420" : "#596371")
            : button.hovered ? (button.destructive ? "#d62032" : "#3f4855") : "transparent"
    }

    Text {
        anchors.centerIn: parent
        text: button.label
        textFormat: Text.PlainText
        color: "#ffffff"
        font.pixelSize: Math.min(14, Math.max(10, button.width - 4))
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: {
            button.pressedAddress = button.targetAddress;
            button.pressedIdentity = button.targetIdentity;
        }
        onReleased: function(mouse) {
            var address = button.pressedAddress;
            var identity = button.pressedIdentity;
            button.pressedAddress = "";
            button.pressedIdentity = "";
            if (containsMouse && mouse.button === Qt.LeftButton)
                button.activated(address, identity);
        }
        onCanceled: {
            button.pressedAddress = "";
            button.pressedIdentity = "";
        }
    }
}
