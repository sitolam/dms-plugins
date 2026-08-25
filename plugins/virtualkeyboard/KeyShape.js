.pragma library

// Per-shape size multipliers and shift/caps label resolution, ported from
// end-4/dots-hyprland's OskKey.qml widthMultiplier/heightMultiplier tables
// and its `Ydotool.shiftMode` label-selection ternary.

var WIDTH_MULTIPLIER = {
    normal: 1,
    fn: 1,
    tab: 1.6,
    caps: 1.9,
    shift: 2.5,
    control: 1.3,
    space: 1,
    expand: 1
};

var HEIGHT_MULTIPLIER = {
    normal: 1,
    fn: 0.7,
    tab: 1,
    caps: 1,
    shift: 1,
    control: 1,
    space: 1,
    expand: 1
};

function widthMultiplier(shape) {
    return WIDTH_MULTIPLIER.hasOwnProperty(shape) ? WIDTH_MULTIPLIER[shape] : 1;
}

function heightMultiplier(shape) {
    return HEIGHT_MULTIPLIER.hasOwnProperty(shape) ? HEIGHT_MULTIPLIER[shape] : 1;
}

// shiftMode: 0 = plain, 1 = shift held, 2 = caps-lock latched.
function labelFor(keyData, shiftMode) {
    if (shiftMode === 2)
        return keyData.labelCaps || keyData.labelShift || keyData.label;
    if (shiftMode === 1)
        return keyData.labelShift || keyData.label;
    return keyData.label;
}
