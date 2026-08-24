import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var shell: null
    property var levels: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property real energy: 0
    property bool shuttingDown: false
    readonly property int barCount: 18
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property string configPath: configHome + "/omarchy/plugins/neon-overdrive.cava/cava.conf"

    function clearLevels() {
        levels = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        energy = 0;
    }

    function handleFrame(data) {
        var raw = String(data || "").trim();
        if (raw === "")
            return;
        var parts = raw.split(";");
        var next = [];
        var total = 0;
        var peak = 0;

        for (var i = 0; i < barCount; i++) {
            var parsed = i < parts.length ? Number(parts[i]) : 0;
            if (!isFinite(parsed))
                parsed = 0;
            var level = Math.max(0, Math.min(1, parsed / 100));
            next.push(level);
            total += level;
            peak = Math.max(peak, level);
        }

        levels = next;
        energy = Math.min(1, total / barCount * 0.65 + peak * 0.55);
        staleTimer.restart();
    }

    Component.onCompleted: cavaProcess.running = true
    Component.onDestruction: shuttingDown = true

    Process {
        id: cavaProcess
        command: ["setpriv", "--pdeathsig", "TERM", "cava", "-p", root.configPath]
        stdout: SplitParser {
            onRead: function (data) {
                root.handleFrame(data);
            }
        }
        onExited: function () {
            root.clearLevels();
            if (!root.shuttingDown)
                restartTimer.restart();
        }
    }

    Timer {
        id: staleTimer
        interval: 700
        repeat: false
        onTriggered: root.clearLevels()
    }

    Timer {
        id: restartTimer
        interval: 1500
        repeat: false
        onTriggered: if (!root.shuttingDown && !cavaProcess.running)
            cavaProcess.running = true
    }
}
