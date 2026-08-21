import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common

PanelWindow {
    id: root

    property var tree: ({
            nodes: {},
            roots: [],
            aliases: {},
            orphans: []
        })
    property bool menuVisible: false
    property string pendingRoute: "root"

    signal closed

    function openAt(route) {
        pendingRoute = route || "root";
        menuVisible = true;
    }

    function closeMenu() {
        menuVisible = false;
        closed();
    }

    visible: menuVisible
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.namespace: "dms:plugins:dankMenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: menuVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Dimmed backdrop; clicking it closes, as omarchy's menu does.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeMenu()
        }
    }

    FocusScope {
        anchors.fill: parent
        focus: root.menuVisible

        Keys.onEscapePressed: root.closeMenu()

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(720, parent.width - Theme.spacingXL * 2)
            height: Math.min(520, parent.height - Theme.spacingXL * 2)
            radius: Theme.cornerRadius
            color: Theme.surfaceContainer
            border.width: 1
            border.color: Theme.outline

            // Swallow clicks so they don't reach the backdrop.
            MouseArea {
                anchors.fill: parent
            }
        }
    }
}
