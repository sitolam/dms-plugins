import QtQuick
import QtQuick.Layouts
import "layout-us.js" as LayoutUs

ColumnLayout {
    id: root

    required property var ydotool

    spacing: 6

    Repeater {
        model: LayoutUs.rows

        delegate: RowLayout {
            id: keyRow
            required property var modelData
            spacing: 6

            Repeater {
                model: keyRow.modelData

                delegate: Key {
                    id: keyDelegate
                    required property var modelData
                    keyData: modelData
                    ydotool: root.ydotool
                    Layout.fillWidth: modelData.shape === "space" || modelData.shape === "expand"
                }
            }
        }
    }
}
