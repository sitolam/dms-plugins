import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import "MenuModel.js" as MenuModel
import "Search.js" as Search
import "Conditions.js" as ConditionsJs

PanelWindow {
    id: root

    property var tree: ({
            nodes: {},
            roots: [],
            aliases: {},
            orphans: []
        })
    property bool menuVisible: false
    property string currentId: ""
    property string query: ""

    // How many rows are visible before the list starts scrolling. The card
    // hugs its content below that, so a two-row menu is a two-row card rather
    // than a fixed pane with a hole in it.
    readonly property int rowHeight: 44
    readonly property int maxVisibleRows: 9

    // Not `closed`: PanelWindow already has a signal by that name, and the
    // override is silently rejected.
    signal menuClosed

    // The search field's colours, worked out the way spotlight works out its
    // own (Modals/DankLauncherV2/LauncherContent.qml): a flat surfaceContainerHigh
    // slab reads as a grey brick on a card that is itself translucent over a
    // blur. Letting the blur through the field instead keeps it part of the
    // card, and the alpha has to follow the user's blur settings or a
    // transparent theme gets an opaque field and an opaque one gets a milky
    // rectangle.
    readonly property bool blurredLayers: Theme.blurForegroundLayers || Theme.transparentBlurLayers
    readonly property real fieldAlpha: {
        if (Theme.transparentBlurLayers)
            return 0.28;
        if (Theme.blurForegroundLayers)
            return Math.max(Theme.popupTransparency, 0.62);
        return Theme.popupTransparency;
    }
    readonly property color fieldColor: Theme.withAlpha(Theme.surfaceContainerHigh, fieldAlpha)
    readonly property color fieldBorderColor: Theme.withAlpha(Theme.outline, blurredLayers ? 0.16 : Theme.layerOutlineOpacity)
    readonly property color fieldFocusBorderColor: Theme.withAlpha(Theme.primary, blurredLayers ? 0.72 : 1.0)

    readonly property var breadcrumb: MenuModel.breadcrumb(tree, currentId)
    readonly property string headerTitle: currentId && tree.nodes[currentId] ? tree.nodes[currentId].title : "Menu"

    // Empty query: this level's children, in tree order. Non-empty: every
    // runnable leaf at or below this level, ranked, each captioned with where
    // it lives. That makes the root a command palette without a separate mode.
    function rowsFor(id, q) {
        // A launcher plugin's trigger takes the query whole, at any level: the
        // prefix is explicit intent, and the level's scope has nothing to say
        // about "= 12 * 30". Its rows are returned unranked -- the plugin
        // already ordered them, and our scorer would throw away a calculator
        // result whose label ("360") shares no letters with the query.
        const fired = pluginSource.detect(q || "");
        if (fired)
            return pluginSource.rowsFrom(fired.pluginId, fired.query);

        const node = id ? tree.nodes[id] : null;
        if (node && node.provider === "apps")
            return Search.rank(q || "", appSource.entries());

        if (!q) {
            const kids = MenuModel.childrenOf(tree, id);
            const out = [];
            for (let i = 0; i < kids.length; i++) {
                const state = ConditionsJs.applyTo(kids[i], conditions.results);
                if (!state.visible)
                    continue;
                out.push({
                    id: kids[i].id,
                    label: state.label || kids[i].label,
                    icon: kids[i].icon,
                    comment: "",
                    kind: MenuModel.kindOf(kids[i]),
                    checked: state.checked,
                    disabled: state.disabled
                });
            }
            return out;
        }

        const leaves = MenuModel.leavesUnder(tree, id);
        const entries = [];
        for (let i = 0; i < leaves.length; i++) {
            const state = ConditionsJs.applyTo(leaves[i], conditions.results);
            if (!state.visible)
                continue;
            const crumbs = MenuModel.breadcrumb(tree, leaves[i].parent);
            entries.push({
                id: leaves[i].id,
                label: state.label || leaves[i].label,
                icon: leaves[i].icon,
                comment: crumbs.join("  \u203a  "),
                kind: MenuModel.kindOf(leaves[i]),
                aliases: leaves[i].aliases,
                checked: state.checked,
                disabled: state.disabled
            });
        }
        // At the root a query reaches apps as well, so one keystroke sequence
        // finds either a command or a program. Inside a submenu it does not:
        // the level is the scope.
        if (!id)
            entries.push.apply(entries, appSource.entries());

        const ranked = Search.rank(q, entries);
        if (id)
            return ranked;

        // Trigger-less launcher plugins answer every root query. They go on top
        // unranked, for the same reason a triggered plugin's rows are: a plugin
        // returning anything at all has already decided the query was for it.
        return pluginSource.untriggeredRows(q).concat(ranked);
    }

    AppSource {
        id: appSource
    }

    PluginSource {
        id: pluginSource

        // Late plugin answers rebuild the rows in place, holding the highlight
        // where it was -- the same treatment Conditions.onSettled gives a
        // condition that resolves after its level was drawn.
        onItemsUpdated: {
            if (!root.menuVisible)
                return;
            const selected = list.rows[list.currentIndex];
            list.rows = root.rowsFor(root.currentId, root.query);
            list.currentIndex = root.indexOfRow(selected ? selected.id : "");
        }
    }

    // selectId: which row to land on. Popping back out of a submenu passes the
    // submenu's own id, so you return to the row you went in through rather
    // than to the top of the list.
    function showLevel(id, selectId) {
        currentId = id;
        query = "";
        searchInput.text = "";
        list.rows = rowsFor(id, "");
        list.currentIndex = indexOfRow(selectId);
        // Entering a level is what makes its conditions a fresh snapshot, so
        // this run happens even if the same level was just evaluated.
        conditions.invalidate();
        evaluateConditions();
    }

    function indexOfRow(id) {
        if (!id)
            return 0;
        for (let i = 0; i < list.rows.length; i++) {
            if (list.rows[i].id === id)
                return i;
        }
        return 0;
    }

    onQueryChanged: {
        list.rows = rowsFor(currentId, query);
        list.currentIndex = 0;
        evaluateConditions();
    }

    // A search reaches the whole subtree, so its conditions are the subtree's;
    // an unfiltered level only needs its own children. Conditions itself drops
    // a repeat of the set it already ran, so typing through a level of slow
    // conditions costs one run rather than one per keystroke.
    function evaluateConditions() {
        const nodes = query ? MenuModel.leavesUnder(tree, currentId) : MenuModel.childrenOf(tree, currentId);
        conditions.evaluate(nodes);
    }

    Conditions {
        id: conditions

        onSettled: {
            // Rebuilding the rows would otherwise drop the highlight back to
            // the top the moment a condition resolves.
            const selected = list.rows[list.currentIndex];
            list.rows = root.rowsFor(root.currentId, root.query);
            list.currentIndex = root.indexOfRow(selected ? selected.id : "");
        }
    }

    function openAt(route) {
        showLevel(MenuModel.resolve(tree, route));
        menuVisible = true;
    }

    function closeMenu() {
        menuVisible = false;
        menuClosed();
    }

    function enter(row) {
        if (!row || row.disabled)
            return;
        if (row.kind === "submenu" || row.kind === "provider") {
            showLevel(row.id);
            return;
        }
        run(row);
    }

    function run(row) {
        if (row.kind === "plugin") {
            pluginSource.run(row);
            closeMenu();
            return;
        }

        if (row.kind === "app") {
            appSource.launch(row);
            closeMenu();
            return;
        }

        const node = tree.nodes[row.id];
        if (!node) {
            console.warn("dankMenu: no node for row", row.id);
            closeMenu();
            return;
        }

        if (node.action) {
            const proc = actionProcess.createObject(root, {
                script: node.action
            });
            proc.running = true;
        } else if (node.target) {
            Qt.openUrlExternally(node.target);
        }

        closeMenu();
    }

    Component {
        id: actionProcess

        Process {
            property string script: ""

            // bash -lc, not a bare exec: menu actions are shell text. Omarchy's
            // use pipes, $(...), && and quoting freely, and the schema
            // compatibility this plugin keeps is only real if that still works.
            command: ["bash", "-lc", script]

            onExited: exitCode => {
                if (exitCode !== 0)
                    console.warn("dankMenu: action exited", exitCode, "-", script);
                destroy();
            }
        }
    }

    // Escape and Left pop a level; at the root they close. The query belongs
    // to the level, not the session, so it clears on every move.
    function pop() {
        if (!currentId) {
            closeMenu();
            return;
        }
        const cameFrom = currentId;
        showLevel(tree.nodes[currentId] ? tree.nodes[currentId].parent : "", cameFrom);
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

    // Compositor-side blur behind the card only, tracking its rect -- the same
    // treatment DMS gives its own modals, so the menu doesn't read as a flat
    // slab pasted over the desktop.
    WindowBlur {
        targetWindow: root
        blurX: card.x
        blurY: card.y
        blurWidth: root.menuVisible ? card.width : 0
        blurHeight: root.menuVisible ? card.height : 0
        blurRadius: Theme.cornerRadius
    }

    // Backdrop and content share one container so the two are obviously
    // siblings under a single root, which is how DMS's own layershell modals
    // are laid out (Modals/DankLauncherV2: a content root holding a FocusScope).
    Item {
        anchors.fill: parent

        // Dim the desktop; clicking it closes, as omarchy's menu does.
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.35)

            MouseArea {
                anchors.fill: parent
                onClicked: root.closeMenu()
            }
        }

        FocusScope {
            anchors.fill: parent
            focus: root.menuVisible

            Rectangle {
                id: card

                anchors.centerIn: parent
                width: Math.min(560, parent.width - Theme.spacingXL * 2)
                height: Math.min(content.implicitHeight + Theme.spacingM * 2, parent.height - Theme.spacingXL * 2)
                radius: Theme.cornerRadius
                // readableSurface is surfaceContainer at the popup transparency
                // the user has configured -- opaque enough to read against, sheer
                // enough for the blur behind it to show through.
                color: Theme.readableSurface
                border.width: 1
                border.color: Theme.outlineVariant

                // Swallow clicks so they don't reach the backdrop.
                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    id: content

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    StyledText {
                        width: parent.width
                        // One level deep the breadcrumb would just repeat
                        // the title underneath it.
                        visible: root.breadcrumb.length > 1
                        height: visible ? implicitHeight : 0
                        text: root.breadcrumb.join("  ›  ")
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideLeft
                    }

                    StyledText {
                        width: parent.width
                        text: root.headerTitle
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeLarge
                    }

                    Rectangle {
                        width: parent.width
                        height: 36
                        radius: Theme.cornerRadius
                        color: root.fieldColor
                        border.width: searchInput.activeFocus ? 2 : 1
                        border.color: searchInput.activeFocus ? root.fieldFocusBorderColor : root.fieldBorderColor

                        // The field holds focus the whole time the menu is
                        // open, so the focused border is the resting state and
                        // these only animate the open. Matching DankTextField's
                        // own behaviours keeps the menu feeling like the rest
                        // of the shell.
                        Behavior on border.color {
                            ColorAnimation {
                                duration: Theme.shortDuration
                                easing.type: Theme.standardEasing
                            }
                        }

                        Behavior on border.width {
                            NumberAnimation {
                                duration: Theme.shortDuration
                                easing.type: Theme.standardEasing
                            }
                        }

                        DankIcon {
                            id: searchIcon

                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            name: "search"
                            size: Theme.fontSizeMedium
                            color: searchInput.activeFocus ? Theme.primary : Theme.surfaceVariantText
                        }

                        // Sibling of the field rather than a child of it: a
                        // TextInput paints its own text layer over its children,
                        // so a placeholder nested inside it never shows.
                        StyledText {
                            anchors.left: searchIcon.right
                            anchors.leftMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text === ""
                            text: root.currentId ? "Search " + root.headerTitle : "Search"
                            color: Theme.outlineButton
                            font.pixelSize: Theme.fontSizeMedium
                        }

                        TextInput {
                            id: searchInput

                            anchors.fill: parent
                            anchors.leftMargin: searchIcon.width + Theme.spacingM + Theme.spacingS
                            anchors.rightMargin: Theme.spacingM
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            clip: true
                            // The field holds focus while the menu is open, so
                            // typing filters immediately; the FocusScope's Keys
                            // handler still sees navigation keys first.
                            focus: root.menuVisible
                            onTextChanged: root.query = text

                            // Navigation lives on the field, not on an ancestor:
                            // a focused TextInput consumes Left/Right/Backspace
                            // for editing, so an ancestor Keys handler would
                            // never see them. Left and Backspace only navigate
                            // when there is no text to edit, and Right only when
                            // the cursor has nowhere further to go -- otherwise
                            // they do the editing thing the user expects.
                            // Navigation lives on the field, not on an ancestor:
                            // a focused TextInput consumes Left/Right/Backspace
                            // for editing, so an ancestor Keys handler would
                            // never see them. Left and Backspace only navigate
                            // when there is no text to edit, and Right only when
                            // the cursor has nowhere further to go -- otherwise
                            // they do the editing thing the user expects.
                            //
                            // Every vim binding is Ctrl-prefixed. Bare hjkl
                            // cannot navigate here: the field is always focused
                            // and always accepting a query, so plain letters
                            // have to reach it as text.
                            Keys.onPressed: event => {
                                const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                                const lastRow = list.rows.length - 1;
                                const halfPage = Math.max(1, Math.floor(root.maxVisibleRows / 2));

                                function moveBy(delta) {
                                    list.currentIndex = Math.max(0, Math.min(list.currentIndex + delta, lastRow));
                                    event.accepted = true;
                                }

                                switch (event.key) {
                                case Qt.Key_Escape:
                                    root.pop();
                                    event.accepted = true;
                                    break;
                                case Qt.Key_Return:
                                case Qt.Key_Enter:
                                    root.enter(list.rows[list.currentIndex]);
                                    event.accepted = true;
                                    break;
                                case Qt.Key_Right:
                                    if (searchInput.cursorPosition === searchInput.text.length) {
                                        root.enter(list.rows[list.currentIndex]);
                                        event.accepted = true;
                                    }
                                    break;
                                case Qt.Key_Left:
                                case Qt.Key_Backspace:
                                    if (searchInput.text === "") {
                                        root.pop();
                                        event.accepted = true;
                                    }
                                    break;
                                case Qt.Key_Down:
                                    moveBy(1);
                                    break;
                                case Qt.Key_Up:
                                    moveBy(-1);
                                    break;

                                // vim: Ctrl+J/K move, Ctrl+H/L go out and in,
                                // Ctrl+D/U jump half a page, Ctrl+G bails out.
                                // Ctrl+N/P are the readline spelling of J/K.
                                case Qt.Key_J:
                                case Qt.Key_N:
                                    if (ctrl)
                                        moveBy(1);
                                    break;
                                case Qt.Key_K:
                                case Qt.Key_P:
                                    if (ctrl)
                                        moveBy(-1);
                                    break;
                                case Qt.Key_D:
                                    if (ctrl)
                                        moveBy(halfPage);
                                    break;
                                case Qt.Key_U:
                                    if (ctrl)
                                        moveBy(-halfPage);
                                    break;
                                case Qt.Key_H:
                                    if (ctrl) {
                                        root.pop();
                                        event.accepted = true;
                                    }
                                    break;
                                case Qt.Key_L:
                                    if (ctrl) {
                                        root.enter(list.rows[list.currentIndex]);
                                        event.accepted = true;
                                    }
                                    break;
                                case Qt.Key_G:
                                    if (ctrl) {
                                        root.closeMenu();
                                        event.accepted = true;
                                    }
                                    break;
                                }
                            }
                        }
                    }

                    MenuList {
                        id: list

                        width: parent.width
                        // Hug the rows until there are more than fit, then scroll.
                        height: Math.min(contentHeight, root.rowHeight * root.maxVisibleRows)
                        onActivated: row => root.enter(row)
                    }
                }
            }
        }
    }
}
