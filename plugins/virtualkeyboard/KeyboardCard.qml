import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

StyledRect {
    id: root

    required property var ydotool
    property bool pinned: false
    // Set only by the floating window -- lets the drag handle below call
    // startSystemMove() on it. Left null when docked, where there's nothing
    // to drag (the panel is anchored to the screen edge).
    property var targetWindow: null

    signal pinClicked
    signal hideClicked

    radius: Theme.cornerRadius
    color: Theme.readableSurface
    border.width: 1
    border.color: Theme.outlineVariant
    width: content.implicitWidth + Theme.spacingL * 2
    height: content.implicitHeight + Theme.spacingL * 2

    // Drag handle: clicking empty card padding (anywhere the RowLayout below
    // doesn't cover) starts a compositor-native window move. Declared before
    // `content` so buttons and keys, painted on top, still get their own
    // clicks -- this only catches clicks that land on the gaps around them.
    MouseArea {
        anchors.fill: parent
        enabled: root.pinned && !!root.targetWindow
        cursorShape: enabled ? Qt.SizeAllCursor : Qt.ArrowCursor
        onPressed: root.targetWindow.startSystemMove()
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: Theme.spacingM

        ColumnLayout {
            spacing: Theme.spacingXS

            DankActionButton {
                iconName: "keep"
                iconColor: root.pinned ? Theme.primary : Theme.surfaceText
                tooltipText: root.pinned ? "Dock to bottom" : "Float"
                onClicked: root.pinClicked()
            }

            DankActionButton {
                iconName: "keyboard_hide"
                tooltipText: "Hide"
                onClicked: root.hideClicked()
            }
        }

        Rectangle {
            Layout.fillHeight: true
            Layout.topMargin: Theme.spacingM
            Layout.bottomMargin: Theme.spacingM
            implicitWidth: 1
            color: Theme.outlineVariant
        }

        KeyboardLayout {
            ydotool: root.ydotool
        }
    }
}
