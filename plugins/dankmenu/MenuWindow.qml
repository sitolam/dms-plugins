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

    readonly property var breadcrumb: MenuModel.breadcrumb(tree, currentId)
    readonly property string headerTitle: currentId && tree.nodes[currentId] ? tree.nodes[currentId].title : "Menu"

    // Empty query: this level's children, in tree order. Non-empty: every
    // runnable leaf at or below this level, ranked, each captioned with where
    // it lives. That makes the root a command palette without a separate mode.
    function rowsFor(id, q) {
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
                    label: kids[i].label,
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
                label: leaves[i].label,
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

        return Search.rank(q, entries);
    }

    AppSource {
        id: appSource
    }

    function showLevel(id) {
        currentId = id;
        query = "";
        searchInput.text = "";
        list.rows = rowsFor(id, "");
        list.currentIndex = 0;
        evaluateConditions();
    }

    onQueryChanged: {
        list.rows = rowsFor(currentId, query);
        list.currentIndex = 0;
        evaluateConditions();
    }

    // A search reaches the whole subtree, so its conditions are the subtree's;
    // an unfiltered level only needs its own children.
    function evaluateConditions() {
        const nodes = query ? MenuModel.leavesUnder(tree, currentId) : MenuModel.childrenOf(tree, currentId);
        conditions.clear();
        conditions.evaluate(nodes);
    }

    Conditions {
        id: conditions

        onSettled: {
            list.rows = root.rowsFor(root.currentId, root.query);
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
        showLevel(tree.nodes[currentId] ? tree.nodes[currentId].parent : "");
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
                        visible: root.breadcrumb.length > 0
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
                        color: Theme.surfaceContainerHigh

                        TextInput {
                            id: searchInput

                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
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
                            Keys.onPressed: event => {
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
                                    list.currentIndex = Math.min(list.currentIndex + 1, list.rows.length - 1);
                                    event.accepted = true;
                                    break;
                                case Qt.Key_Up:
                                    list.currentIndex = Math.max(list.currentIndex - 1, 0);
                                    event.accepted = true;
                                    break;
                                case Qt.Key_N:
                                    if (event.modifiers & Qt.ControlModifier) {
                                        list.currentIndex = Math.min(list.currentIndex + 1, list.rows.length - 1);
                                        event.accepted = true;
                                    }
                                    break;
                                case Qt.Key_P:
                                    if (event.modifiers & Qt.ControlModifier) {
                                        list.currentIndex = Math.max(list.currentIndex - 1, 0);
                                        event.accepted = true;
                                    }
                                    break;
                                }
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: searchInput.text === ""
                                text: "Search"
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeMedium
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
