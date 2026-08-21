import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null
    readonly property var daemon: pluginService
        ? pluginService.pluginInstances[pluginId] : null
    readonly property string mouthState: daemon ? daemon.mouthState : "inactive"

    readonly property var iconFor: ({
        "inactive": "videocam_off",
        "closed": "sentiment_satisfied",
        "open": "warning",
        "noface": "face_retouching_off",
        "paused": "pause_circle"
    })

    readonly property color stateColor: mouthState === "open"
        ? Theme.error
        : (mouthState === "closed" ? Theme.surfaceText : Theme.surfaceVariantText)

    // Task 13 declared this setting; nothing read it until now. A live gap
    // number is only useful once tracking has actually started, and only on
    // the horizontal pill -- the vertical (side-mounted) pill is too narrow
    // for an icon plus a number.
    readonly property bool showGap: (pluginData?.showGapInPill ?? false)
        && root.mouthState !== "inactive"

    popoutWidth: 420
    popoutHeight: 380

    function _fmt(ms) {
        if (!ms) return "—"
        const s = Math.floor(ms / 1000)
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    popoutContent: Component {
        PopoutComponent {
            headerText: "MouthGuard"
            detailsText: root.mouthState === "inactive"
                ? "Not tracking"
                : "Tracking — " + root.mouthState
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                GapChart {
                    width: parent.width
                    height: 120
                    points: root.daemon?.gapHistory ?? []
                    threshold: root.daemon?.threshold ?? 0
                }

                Row {
                    spacing: Theme.spacingL
                    visible: root.daemon?.distComp ?? false

                    StyledText {
                        text: "Face " + Math.round(root.daemon?.lastFace ?? 0) + "px"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    StyledText {
                        text: "Adj. gap " + (root.daemon?.lastAdjGap ?? 0).toFixed(1) + "px"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                Row {
                    spacing: Theme.spacingL

                    StyledText {
                        text: "Open " + root._fmt(root.daemon?.sessionStats.openMs)
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    StyledText {
                        text: "Closed " + root._fmt(root.daemon?.sessionStats.closedMs)
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    StyledText {
                        // "Away" = time with no face visible, plus any
                        // auto-pause gap (lock/idle/sleep) -- see the
                        // daemon's sessionStats.unmeasuredMs. Shown
                        // alongside Open/Closed so the three visibly add up
                        // to the session length instead of quietly falling
                        // short of it whenever the screen was locked.
                        text: "Away " + root._fmt(root.daemon?.sessionStats.unmeasuredMs)
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    StyledText {
                        text: "Events " + (root.daemon?.sessionStats.events ?? 0)
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "History — % is share of MEASURED time (open ÷ open+closed) the mouth was open; time away isn't counted"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                StyledText {
                    visible: (root.daemon?.history ?? []).length === 0
                    text: "No sessions yet"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                Repeater {
                    model: (root.daemon?.history ?? []).slice(0, 5)

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        StyledText {
                            text: new Date(modelData.start).toLocaleTimeString(
                                Qt.locale(), Locale.ShortFormat)
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            width: 60
                        }
                        StyledText {
                            text: {
                                const tot = modelData.openMs + modelData.closedMs
                                return tot > 0
                                    ? Math.round(modelData.openMs / tot * 100) + "% open (of measured)"
                                    : "—"
                            }
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                DankButton {
                    text: root.daemon?.active ? "Stop" : "Start"
                    onClicked: root.daemon?.toggle()
                }
            }
        }
    }

    horizontalBarPill: Component {
        StyledRect {
            width: content.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Row {
                id: content
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.iconFor[root.mouthState]
                    size: Theme.iconSizeSmall
                    color: root.stateColor
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.showGap
                    // Same value the daemon compares against threshold (see
                    // MouthGuardDaemon._onMeasurement's `effective`): lastAdjGap
                    // when distance compensation is on, otherwise raw lastGap.
                    // Showing anything else would let the pill number and the
                    // open/closed state visibly disagree.
                    text: (root.daemon?.distComp
                        ? (root.daemon?.lastAdjGap ?? 0)
                        : (root.daemon?.lastGap ?? 0)).toFixed(1)
                    color: root.stateColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) root.daemon?.toggle()
                    else if (mouse.button === Qt.RightButton) {
                        if (root.daemon) root.daemon.alertsMuted = !root.daemon.alertsMuted
                    } else root.triggerPopout()
                }
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: vicon.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            DankIcon {
                id: vicon
                anchors.centerIn: parent
                name: root.iconFor[root.mouthState]
                size: Theme.iconSizeSmall
                color: root.stateColor
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) root.daemon?.toggle()
                    else if (mouse.button === Qt.RightButton) {
                        if (root.daemon) root.daemon.alertsMuted = !root.daemon.alertsMuted
                    } else root.triggerPopout()
                }
            }
        }
    }

    // -- Control Center tile -------------------------------------------
    // Properties verified against PluginComponent.qml and the shipped
    // ControlCenterDetailExample plugin (both read-only references) --
    // ccWidgetIcon/PrimaryText/SecondaryText/IsActive, onCcWidgetToggled
    // and ccDetailContent all exist with the types used below.
    //
    // mouthState has five values; secondary text distinguishes each so a
    // paused session (auto-pause on lock/idle/suspend) never reads as
    // "off" or as a live "Tracking" state.
    ccWidgetIcon: root.iconFor[root.mouthState]
    ccWidgetPrimaryText: "MouthGuard"
    ccWidgetSecondaryText: {
        if (!root.daemon?.active) return "Off"
        if (root.mouthState === "paused") return "Paused"
        if (root.mouthState === "noface") return "No face"
        return root.mouthState === "open" ? "Mouth open" : "Tracking"
    }
    ccWidgetIsActive: root.daemon?.active ?? false

    onCcWidgetToggled: root.daemon?.toggle()

    // The space reserved for the detail panel is driven by ccDetailHeight
    // (default 250 -- see PluginComponent.qml and
    // ControlCenter/utils/detailHeight.js), NOT by any implicitHeight set
    // on the ccDetailContent root: DetailHost's Loader is given an
    // explicit height computed from this property before the content is
    // ever loaded. Sized to what the chart + stats row actually need so
    // the panel isn't left with ~90px of dead space at the default 250.
    ccDetailHeight: 160

    ccDetailContent: Component {
        Rectangle {
            implicitHeight: 160
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadius

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                GapChart {
                    width: parent.width
                    height: 90
                    points: root.daemon?.gapHistory ?? []
                    threshold: root.daemon?.threshold ?? 0
                }

                StyledText {
                    text: "Open " + root._fmt(root.daemon?.sessionStats.openMs)
                        + "   Events " + (root.daemon?.sessionStats.events ?? 0)
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }
}
