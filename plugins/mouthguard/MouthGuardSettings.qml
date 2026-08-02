import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// SliderSetting (Modules/Plugins/SliderSetting.qml in DMS 1.5.3, confirmed
// against the live shell at /nix/store/16lzj41bslxwwbpwwl9ga6nvq6pqa46j-
// dms-shell-1.5.3) wraps DankSlider, and both are integer-only end to end:
// SliderSetting declares `property int defaultValue` / `property int
// value`, and DankSlider itself declares `property int value` and rounds
// every drag/wheel update with Math.round(). Neither exposes `from`, `to`,
// or `stepSize` -- those are not real properties on this component in this
// DMS version; every SliderSetting below uses the real API (`minimum` /
// `maximum`, whole-number defaultValue) instead.
//
// The threshold control is the one place that cannot tolerate int
// truncation: mouthguard_core.DEFAULT_THRESHOLD and
// MouthGuardDaemon.DEFAULT_THRESHOLD are both 3.5 exactly (see
// CALIBRATION.md), and a rounded 3 or 4 default here would disagree with
// the daemon as soon as this page is opened and a value is saved -- the
// exact "settings page and daemon disagree" bug this task exists to avoid.
// It is hand-built from DankSlider directly, storing tenths internally
// (10-100 representing 1.0-10.0 gap units) and converting on load/save, so
// the real number persisted under the "threshold" key is always the exact
// value the daemon compares against.
PluginSettings {
    pluginId: "mouthGuard"

    SelectionSetting {
        settingKey: "device"
        label: "Camera"
        description: "Which video device to read"
        options: [
            { label: "/dev/video0", value: "/dev/video0" },
            { label: "/dev/video1", value: "/dev/video1" }
        ]
        defaultValue: "/dev/video0"
    }

    // Custom control -- see file header. Mirrors the load/save contract
    // every other setting here uses (walk up `parent` for a PluginSettings
    // ancestor, then call its saveValue/loadValue), just with a
    // real-gap-units <-> int-tenths conversion in between so the slider can
    // move the "threshold" pluginData value in 0.1 steps.
    Column {
        id: thresholdSetting
        width: parent.width
        spacing: Theme.spacingS

        readonly property real scale: 10
        readonly property real minReal: 1.0
        readonly property real maxReal: 10.0
        readonly property real defaultValue: 3.5
        property real value: defaultValue
        property bool isInitialized: false

        function findSettings() {
            let item = parent
            while (item) {
                if (item.saveValue !== undefined && item.loadValue !== undefined)
                    return item
                item = item.parent
            }
            return null
        }

        function loadValue() {
            const settings = findSettings()
            if (settings && settings.pluginService) {
                value = settings.loadValue("threshold", defaultValue)
                isInitialized = true
            }
        }

        Component.onCompleted: loadValue()

        onValueChanged: {
            if (!isInitialized) return
            const settings = findSettings()
            if (settings) settings.saveValue("threshold", value)
        }

        StyledText {
            text: "Sensitivity threshold"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            text: "Lip gap that counts as open, in the detector's own gap units " +
                  "(see CALIBRATION.md) -- not pixels or a percentage. Lower is " +
                  "more sensitive. Current: " + thresholdSetting.value.toFixed(1) +
                  ". Calibrated default: " + thresholdSetting.defaultValue.toFixed(1) + "."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
        }

        DankSlider {
            width: parent.width
            minimum: Math.round(thresholdSetting.minReal * thresholdSetting.scale)
            maximum: Math.round(thresholdSetting.maxReal * thresholdSetting.scale)
            value: Math.round(thresholdSetting.value * thresholdSetting.scale)
            unit: ""
            wheelEnabled: false
            thumbOutlineColor: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
            onSliderValueChanged: newValue => {
                thresholdSetting.value = newValue / thresholdSetting.scale
            }
        }
    }

    SliderSetting {
        settingKey: "alertDelay"
        label: "Detection window"
        // Whole seconds, not the brief's 0.1s step -- SliderSetting has no
        // fractional support in this DMS version (see file header). This is
        // an acceptable simplification here, unlike threshold: the default
        // (1) is exactly 1.0, so it cannot disagree with the daemon's
        // fallback the way a rounded threshold default would.
        description: "Mouth must stay open this long, in whole seconds, to be detected and trigger an alert"
        minimum: 0
        maximum: 10
        defaultValue: 1
        unit: " s"
    }

    ToggleSetting {
        settingKey: "distanceCompensation"
        label: "Distance compensation"
        description: "Keep sensitivity consistent regardless of how far you sit from the camera"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "soundType"
        label: "Alert sound"
        options: [
            { label: "Soft beep", value: "soft" },
            { label: "Chime", value: "chime" },
            { label: "Double beep", value: "double" },
            { label: "Buzz", value: "buzz" },
            { label: "High ping", value: "ping" },
            { label: "None", value: "none" }
        ]
        defaultValue: "soft"
    }

    SliderSetting {
        settingKey: "volume"
        label: "Volume"
        minimum: 0
        maximum: 100
        defaultValue: 85
        unit: "%"
    }

    ToggleSetting {
        settingKey: "notifications"
        label: "Desktop notifications"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "fps"
        label: "Detection rate"
        description: "Frames per second. Lower uses less CPU. Measured throughput on this hardware is roughly 5-6fps in practice, so values toward the top of this range are unlikely to be reached even though the slider allows them."
        minimum: 5
        maximum: 15
        defaultValue: 10
        unit: " fps"
    }

    SliderSetting {
        settingKey: "noFaceTimeout"
        label: "Stop after no face"
        description: "Minutes without a detected face before the session ends. 0 disables."
        minimum: 0
        maximum: 15
        defaultValue: 5
        unit: " min"
    }

    ToggleSetting {
        settingKey: "autoPause"
        label: "Pause when locked or idle"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showGapInPill"
        label: "Show gap value in the bar"
        description: "Reserved for the upcoming gap chart and control-center tile; has no effect yet"
        defaultValue: false
    }
}
