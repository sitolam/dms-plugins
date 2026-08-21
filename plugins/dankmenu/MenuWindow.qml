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

    // Backdrop and content share one container so the two are obviously
    // siblings under a single root, which is how DMS's own layershell modals
    // are laid out (Modals/DankLauncherV2: a content root holding a FocusScope).
    Item {
        anchors.fill: parent

        // Dimmed backdrop; clicking it closes, as omarchy's menu does.
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)

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
                anchors.centerIn: parent
                width: Math.min(720, parent.width - Theme.spacingXL * 2)
                height: Math.min(520, parent.height - Theme.spacingXL * 2)
                radius: Theme.cornerRadius
                color: Theme.surfaceContainer
                border.width: 1
                border.color: Theme.outline

                // Swallow clicks so they don't reach the backdrop.
                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    StyledText {
                        width: parent.width
                        text: root.breadcrumb.length ? root.breadcrumb.join("  ›  ") : "Menu"
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
                        height: parent.height - y
                        onActivated: row => root.enter(row)
                    }
                }
            }
        }
    }
}
