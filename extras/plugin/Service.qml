pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var shell: null
    property var levels: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property real energy: 0
    property real bass: 0
    property real mids: 0
    property real highs: 0
    property real peak: 0
    property real beat: 0
    property bool wallpaperReactive: true
    property real wallpaperIntensity: 0.60
    property bool hasSignal: false
    property string lastError: ""
    property bool shuttingDown: false
    property bool socketRecreatePending: false
    property int restartDelay: 1200
    property int wallpaperProbeDelay: 2000
    property double lastBeatAt: 0
    property string lastWallpaperGrade: ""
    readonly property int barCount: 18
    readonly property bool running: cavaProcess.running
    readonly property bool available: running && lastError === ""
    // Omarchy 4 discovers user plugins from this canonical path rather than
    // XDG_CONFIG_HOME, so keep the service path aligned with the registry.
    readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/neon-overdrive.cava/cava.conf"
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string wallpaperSocketPath: runtimeDir === ""
        ? ""
        : runtimeDir + "/neon-overdrive-wallpaper.sock"
    readonly property var wallpaperSocket: wallpaperSocketLoader.item
    readonly property string neutralWallpaperGrade: "0:0:0"

    function clearLevels() {
        levels = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        energy = 0;
        bass = 0;
        mids = 0;
        highs = 0;
        peak = 0;
        hasSignal = false;
        beatDecay.stop();
        beat = 0;
        sendWallpaperGrade(true);
    }

    function averageRange(values, first, last) {
        var total = 0;
        var count = Math.max(1, last - first);
        for (var i = first; i < last; i++)
            total += values[i] || 0;
        return total / count;
    }

    function triggerBeat() {
        beatDecay.stop();
        beat = 1;
        beatDecay.start();
    }

    function scheduleCavaRestart(message) {
        clearLevels();
        if (shuttingDown || restartTimer.running)
            return;
        if (lastError === "")
            lastError = message;
        restartTimer.interval = restartDelay;
        restartTimer.restart();
        restartDelay = Math.min(30000, restartDelay * 2);
    }

    function smoothValue(current, next) {
        var amount = next > current ? 0.55 : 0.12;
        return current + (next - current) * amount;
    }

    function wallpaperCommand(name, value) {
        return JSON.stringify({"command": ["set_property", name, value]}) + "\n";
    }

    function oneDecimal(value) {
        return Math.round(value * 10) / 10;
    }

    function sendWallpaperGrade(forceNeutral) {
        var socket = wallpaperSocket;
        if (!socket || !socket.connected)
            return;

        var intensity = Math.max(0, Math.min(1, wallpaperIntensity));
        var reactive = !forceNeutral && wallpaperReactive && hasSignal && intensity > 0;
        var brightness = reactive ? oneDecimal(Math.min(5, energy * 3.2 + beat * 1.8) * intensity) : 0;
        var saturation = reactive ? oneDecimal(Math.min(12, mids * 6.0 + highs * 3.0 + energy * 3.0) * intensity) : 0;
        var contrast = reactive ? oneDecimal(Math.min(4, bass * 3.0 + beat) * intensity) : 0;
        var grade = brightness + ":" + saturation + ":" + contrast;

        if (grade === lastWallpaperGrade)
            return;

        socket.write(
            wallpaperCommand("brightness", brightness)
            + wallpaperCommand("saturation", saturation)
            + wallpaperCommand("contrast", contrast)
        );
        socket.flush();
        lastWallpaperGrade = grade;
    }

    function handleWallpaperConnectedChanged(connected) {
        if (connected) {
            wallpaperProbeDelay = 2000;
            lastWallpaperGrade = "";
            sendWallpaperGrade(false);
        } else {
            lastWallpaperGrade = "";
        }
    }

    function recreateWallpaperSocket(error) {
        if (shuttingDown || socketRecreatePending)
            return;
        socketRecreatePending = true;
        wallpaperSocketLoader.active = false;
        Qt.callLater(function() {
            root.socketRecreatePending = false;
            if (root.shuttingDown)
                return;
            wallpaperSocketLoader.active = true;
            if (root.runtimeDir !== "" && !wallpaperProbe.running)
                wallpaperProbe.running = true;
        });
    }

    function handleFrame(data) {
        var raw = String(data || "").trim();
        if (raw === "")
            return;
        var parts = raw.split(";");
        var next = [];
        var total = 0;
        var nextPeak = 0;

        for (var i = 0; i < barCount; i++) {
            var parsed = i < parts.length ? Number(parts[i]) : 0;
            if (!isFinite(parsed))
                parsed = 0;
            var level = Math.max(0, Math.min(1, parsed / 100));
            next.push(level);
            total += level;
            nextPeak = Math.max(nextPeak, level);
        }

        var previousBass = bass;
        var nextBass = averageRange(next, 0, 5);
        var nextMids = averageRange(next, 5, 12);
        var nextHighs = averageRange(next, 12, barCount);
        var nextEnergy = Math.min(1, total / barCount * 0.65 + nextPeak * 0.55);
        var now = Date.now();

        levels = next;
        energy = smoothValue(energy, nextEnergy);
        bass = smoothValue(bass, nextBass);
        mids = smoothValue(mids, nextMids);
        highs = smoothValue(highs, nextHighs);
        peak = nextPeak;
        lastError = "";
        restartDelay = 1200;

        if (nextPeak > 0.025) {
            hasSignal = true;
            silenceTimer.restart();
        }
        if (nextBass > 0.34 && nextBass - previousBass > 0.09 && now - lastBeatAt > 180) {
            lastBeatAt = now;
            triggerBeat();
        }

        staleTimer.restart();
    }

    Component.onCompleted: {
        cavaProcess.running = true;
        if (runtimeDir !== "")
            wallpaperProbe.running = true;
    }
    Component.onDestruction: {
        shuttingDown = true;
        sendWallpaperGrade(true);
        if (wallpaperSocket)
            wallpaperSocket.connected = false;
        wallpaperSocketLoader.active = false;
    }

    Process {
        id: cavaProcess
        command: ["setpriv", "--pdeathsig", "TERM", "cava", "-p", root.configPath]
        stdout: SplitParser {
            onRead: function (data) {
                root.handleFrame(data);
            }
        }
        stderr: SplitParser {
            onRead: function (data) {
                var message = String(data || "").trim();
                if (message !== "")
                    root.lastError = message.slice(0, 180);
            }
        }
        onExited: function () {
            root.scheduleCavaRestart("Cava stopped unexpectedly");
        }
        onRunningChanged: function () {
            if (!running && !root.shuttingDown && !restartTimer.running)
                root.scheduleCavaRestart("Could not start Cava");
        }
    }

    Component {
        id: wallpaperSocketComponent

        Socket {
            path: root.wallpaperSocketPath
            parser: SplitParser {
                // Drain mpv's JSON replies so its socket buffer never fills.
                onRead: function (data) {}
            }
            onConnectedChanged: root.handleWallpaperConnectedChanged(connected)
            onError: function (error) {
                root.recreateWallpaperSocket(error);
            }
        }
    }

    Loader {
        id: wallpaperSocketLoader
        active: root.runtimeDir !== ""
        sourceComponent: wallpaperSocketComponent
    }

    Process {
        id: wallpaperProbe
        command: ["test", "-S", root.wallpaperSocketPath]
        onExited: function (exitCode) {
            var socket = root.wallpaperSocket;
            if (exitCode === 0 && socket && !socket.connected) {
                root.wallpaperProbeDelay = 2000;
                socket.connected = true;
            } else {
                root.wallpaperProbeDelay = Math.min(30000, root.wallpaperProbeDelay * 2);
            }
        }
    }

    NumberAnimation {
        id: beatDecay
        target: root
        property: "beat"
        from: 1
        to: 0
        duration: 420
        easing.type: Easing.OutCubic
    }

    Timer {
        id: staleTimer
        interval: 1400
        repeat: false
        onTriggered: root.clearLevels()
    }

    Timer {
        id: silenceTimer
        interval: 850
        repeat: false
        onTriggered: {
            root.hasSignal = false;
            root.sendWallpaperGrade(true);
        }
    }

    Timer {
        interval: root.wallpaperProbeDelay
        repeat: true
        running: root.runtimeDir !== "" && !root.socketRecreatePending
            && (!root.wallpaperSocket || !root.wallpaperSocket.connected)
        onTriggered: if (!wallpaperProbe.running)
            wallpaperProbe.running = true
    }

    Timer {
        interval: 166
        repeat: true
        running: root.wallpaperSocket && root.wallpaperSocket.connected && (
            (root.hasSignal && root.wallpaperReactive && root.wallpaperIntensity > 0)
            || root.lastWallpaperGrade !== root.neutralWallpaperGrade
        )
        onTriggered: root.sendWallpaperGrade(false)
    }

    Timer {
        id: restartTimer
        interval: 1200
        repeat: false
        onTriggered: if (!root.shuttingDown && !cavaProcess.running)
            cavaProcess.running = true
    }
}
