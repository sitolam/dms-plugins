import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import "MenuModel.js" as MenuModel

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

    function rowsFor(id) {
        const kids = MenuModel.childrenOf(tree, id);
        const out = [];
        for (let i = 0; i < kids.length; i++) {
            out.push({
                id: kids[i].id,
                label: kids[i].label,
                icon: kids[i].icon,
                comment: "",
                kind: MenuModel.kindOf(kids[i]),
                checked: false,
                disabled: false
            });
        }
        return out;
    }

    function showLevel(id) {
        currentId = id;
        query = "";
        list.rows = rowsFor(id);
        list.currentIndex = 0;
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
        // Leaves execute in the next task.
        closeMenu();
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

            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Escape:
                case Qt.Key_Left:
                    root.pop();
                    event.accepted = true;
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Right:
                    root.enter(list.rows[list.currentIndex]);
                    event.accepted = true;
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
                case Qt.Key_Backspace:
                    if (root.query === "") {
                        root.pop();
                        event.accepted = true;
                    }
                    break;
                }
            }

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
