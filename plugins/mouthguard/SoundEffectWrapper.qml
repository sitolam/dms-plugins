import QtQuick
import QtMultimedia

Item {
    id: root

    property alias source: player.source
    property alias volume: player.volume

    SoundEffect {
        id: player
    }

    function play() {
        player.play()
    }

    Component.onDestruction: player.stop()
}
