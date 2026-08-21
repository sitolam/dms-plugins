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
// DMS version. Every SliderSetting below uses the real API (`minimum` /
// `maximum`, whole-number defaultValue), and the two settings that need
// finer-than-1 real-world resolution (threshold, alertDelay) are given
// integer-native units instead of a custom control, so the stock component
// can be used everywhere:
//
//   - threshold is stored in TENTHS of a gap-unit (pixel). The calibrated
//     internal default is 3.5 (mouthguard_core.DEFAULT_THRESHOLD /
//     MouthGuardDaemon.DEFAULT_THRESHOLD, see CALIBRATION.md); stored here
//     as 35. MouthGuardDaemon.qml divides pluginData.threshold by 10 to
//     recover the real value -- see the comment at that read site.
//   - alertDelay is stored in MILLISECONDS, not seconds, so its native
//     0-10s / 0.1s-step range (ported from the original web app) becomes a
//     natural 0-10000 integer range. MouthGuardDaemon.qml reads it directly
//     as ms with no `* 1000` -- see the comment at that read site.
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

    SliderSetting {
        settingKey: "threshold"
        label: "Sensitivity threshold"
        // Stored in tenths of a gap-unit -- see file header. Calibrated
        // internal default is 3.5 (mouthguard_core.DEFAULT_THRESHOLD);
        // stored/shown here as 35.
        description: "Lip gap that counts as open, on a 10-100 sensitivity scale (see CALIBRATION.md). Lower is more sensitive. Calibrated default 35."
        minimum: 10
        maximum: 100
        defaultValue: 35
        unit: ""
    }

    SliderSetting {
        settingKey: "alertDelay"
        label: "Detection window"
        // Stored in milliseconds -- see file header. This is finer than the
        // original web app's 0.1s step (100ms), not coarser.
        description: "Mouth must stay open this long to be detected and trigger an alert"
        minimum: 0
        maximum: 10000
        defaultValue: 1000
        unit: "ms"
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
