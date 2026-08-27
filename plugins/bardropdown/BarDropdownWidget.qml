pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

// One bar button that drops a panel of real bar widgets *below* the bar.
//
// ── Why this exists ──────────────────────────────────────────────────────────
// The obvious way to collapse a cluster of bar widgets is to hide them in place
// and reveal them again inline — that is what hthienloc/dms-hidden-bar and
// rdannenbring/widget-group both do. On a bar whose sections are laid out
// independently that reveal has nowhere to go.
//
// DankBarContent.qml anchors the three sections separately: left to
// `parent.left`, right to `parent.right`, centre to `parent.horizontalCenter`.
// They do not share a layout, so a right-section widget that grows wider only
// pushes its own section's left edge further left, into the empty middle of the
// bar. The centre widgets stay pinned to the screen centre and never move, and
// because the centre section paints after the right one, an expansion wide
// enough to reach them ends up *underneath* the clock rather than displacing
// it. No plugin setting can change that; it is a property of the bar.
//
// So this plugin does not expand along the bar at all. The members go in a
// popout, which DMS anchors under the trigger and paints above the windows
// below — nothing on the bar moves, and nothing overlaps. PluginComponent
// renders `popoutContent` in a DankPopout and wires the pill's click to
// `pluginPopout.toggle()` (see PluginComponent.qml), so the drop-down needs no
// window management of its own.
PluginComponent {
    id: root

    // PluginComponent does not declare this; WidgetHost.qml assigns PopoutService
    // to any widget that has the property (WidgetHost.qml:212). Members need it
    // to open the popouts DMS owns centrally — the tray menu, the control
    // centre, the process list — so it has to be declared here to be filled in.
    property var popoutService: null

    // Bar-widget ids to place in the panel, in order. Plain ids like
    // "systemTray" or "ambientSound"; a plugin variant is "<pluginId>:<variantId>".
    //
    // Two shapes are accepted because two things write this list. The settings
    // UI uses DMS's ListSettingWithInput, which can only store records, so it
    // produces [{ id: "systemTray" }, …]; a config file writing the setting
    // directly is far more naturally a plain ["systemTray", …]. Normalising
    // here means neither writer has to know about the other.
    readonly property var targets: {
        const raw = pluginData?.targets
        if (!raw || raw.length === undefined)
            return []
        const out = []
        for (let i = 0; i < raw.length; i++) {
            const entry = raw[i]
            const id = (typeof entry === "string") ? entry : (entry?.id ?? "")
            if (id !== "")
                out.push(id)
        }
        return out
    }

    readonly property string buttonIcon: pluginData?.icon || "widgets"
    // "icon" | "both" — whether the pill carries a text label next to the icon.
    readonly property string display: pluginData?.display || "icon"
    readonly property string buttonLabel: pluginData?.label || ""
    // Chevron next to the icon, marking the button as something that opens.
    readonly property bool showChevron: pluginData?.showChevron !== false

    // Panel geometry. The width has to be known before the popout's content
    // exists, so it starts as an estimate and is corrected to the real measured
    // row width the first time the panel lays out (see _measuredWidth below).
    // DankPopout re-reads popupWidth reactively, so the correction is a resize
    // rather than a reopen.
    property real _measuredWidth: 0
    readonly property real _panelPadding: Theme.spacingM * 2
    popoutWidth: Math.max(120, (_measuredWidth > 0 ? _measuredWidth : targets.length * (widgetThickness + Theme.spacingL)) + _panelPadding)
    popoutHeight: widgetThickness + _panelPadding

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            anchors.verticalCenter: parent?.verticalCenter ?? undefined

            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.buttonIcon
                size: root.iconSize
                color: Theme.surfaceText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.display === "both" && root.buttonLabel !== ""
                text: root.buttonLabel
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }

            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.showChevron
                // The panel always drops downward from a top bar, so the
                // chevron points the way it opens rather than tracking state.
                name: (root.axis?.edge || "top") === "bottom" ? "expand_less" : "expand_more"
                size: Math.round(root.iconSize * 0.8)
                color: Theme.surfaceVariantText
            }
        }
    }

    popoutContent: Component {
        Item {
            id: panel

            implicitWidth: memberRow.implicitWidth + root._panelPadding
            implicitHeight: memberRow.implicitHeight + root._panelPadding

            // Hand the measured width back so popoutWidth stops being a guess.
            // Qt.callLater keeps this off the first binding pass, where the
            // Row's children have not been sized yet and implicitWidth is 0.
            onImplicitWidthChanged: Qt.callLater(() => {
                if (memberRow.implicitWidth > 0)
                    root._measuredWidth = memberRow.implicitWidth
            })

            Row {
                id: memberRow
                anchors.centerIn: parent
                spacing: Theme.spacingS

                Repeater {
                    model: root.targets

                    DropdownMember {
                        required property var modelData

                        targetId: modelData
                        pluginService: root.pluginService
                        popoutService: root.popoutService

                        // Bar context. `section` is deliberately the trigger's
                        // own section: a member that opens its own popout asks
                        // DMS to place it the way that section's widgets are
                        // placed, which is what keeps a tray menu opening on
                        // the correct side of the screen.
                        //
                        // widget-group's author warns that members in a popout
                        // cannot position their own popouts — that is true for
                        // a *vertical* bar, where getPopupTriggerPosition
                        // (SettingsData.qml:2216-2227) passes the anchor's y
                        // straight through, and our anchor sits one bar-height
                        // off. On a top or bottom bar the same function derives
                        // y from barThickness alone and takes only x from the
                        // anchor, so a member's popout still lands under the
                        // bar, horizontally aligned with the member icon the
                        // user clicked. This bar is horizontal.
                        axis: root.axis
                        section: root.section
                        parentScreen: root.parentScreen
                        widgetThickness: root.widgetThickness
                        barThickness: root.barThickness
                        barSpacing: root.barSpacing
                        barConfig: root.barConfig
                        blurBarWindow: root.blurBarWindow
                    }
                }
            }

            // An empty panel is a configuration mistake, not a state worth
            // rendering as a blank rectangle the user cannot interpret.
            StyledText {
                anchors.centerIn: parent
                visible: root.targets.length === 0
                text: I18n.tr("No widgets configured")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }
}
