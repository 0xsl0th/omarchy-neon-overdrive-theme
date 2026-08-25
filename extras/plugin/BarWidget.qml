pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "neon-overdrive.cava"

    readonly property var cavaService: bar && bar.shell ? bar.shell.serviceFor("neon-overdrive.cava") : null
    readonly property var levels: cavaService ? cavaService.levels : []
    readonly property real energy: cavaService ? cavaService.energy : 0
    readonly property real bass: cavaService ? cavaService.bass : 0
    readonly property int barCount: cavaService ? cavaService.barCount : 18
    readonly property bool analyzerAvailable: cavaService ? cavaService.available : false
    readonly property bool showIdle: booleanSetting("showIdle", true)
    readonly property bool glowEnabled: booleanSetting("glow", true)
    readonly property int widgetWidth: Math.max(72, Math.min(180, Number(setting("width", 104)) || 104))
    readonly property bool tooltipHovered: visible && pointer.containsMouse

    function booleanSetting(name, fallback) {
        var value = setting(name, fallback);
        if (typeof value === "boolean")
            return value;
        if (typeof value === "string") {
            var normalized = value.toLowerCase();
            if (normalized === "true" || normalized === "1" || normalized === "yes" || normalized === "on")
                return true;
            if (normalized === "false" || normalized === "0" || normalized === "no" || normalized === "off")
                return false;
        }
        return fallback;
    }

    function syncSettings() {
        if (cavaService) {
            cavaService.wallpaperReactive = booleanSetting("wallpaperReactive", true);
            cavaService.wallpaperIntensity = Math.max(0, Math.min(1, Number(setting("wallpaperIntensity", 60)) / 100));
        }
    }

    function tooltipText() {
        if (!cavaService)
            return "Neon spectrum  •  service unavailable";
        if (!cavaService.available)
            return "Neon spectrum  •  " + (cavaService.lastError || "audio analyzer unavailable");
        if (!cavaService.hasSignal)
            return "Neon spectrum  •  listening for system audio";
        return "Neon spectrum  •  " + Math.round(root.energy * 100) + "% pulse";
    }

    function levelAt(index) {
        if (!levels || index >= levels.length)
            return 0;
        return Math.max(0, Math.min(1, Number(levels[index]) || 0));
    }

    implicitWidth: vertical ? barSize : (visible ? widgetWidth : 0)
    implicitHeight: vertical ? (visible ? widgetWidth : 0) : barSize
    visible: !analyzerAvailable || showIdle || (cavaService && cavaService.hasSignal)

    onCavaServiceChanged: syncSettings()
    onSettingsChanged: syncSettings()
    Component.onCompleted: syncSettings()

    Item {
        id: rotatedCanvas
        width: root.vertical ? root.height : root.width
        height: root.vertical ? root.width : root.height
        anchors.centerIn: parent
        rotation: root.vertical ? 90 : 0

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 6
            height: Math.max(10, parent.height - 6)
            radius: height / 2
            color: Color.accent
            opacity: root.analyzerAvailable ? 0.035 + root.energy * 0.11 : 0.025
            scale: 1 + root.bass * 0.035

            Behavior on opacity {
                NumberAnimation { duration: 120 }
            }
            Behavior on scale {
                NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
            }
        }

        Row {
            id: spectrum
            anchors.centerIn: parent
            width: parent.width - 10
            height: Math.max(14, parent.height - 8)
            spacing: 2

            visible: root.analyzerAvailable
            layer.enabled: root.glowEnabled
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: root.energy > 0.32 ? Color.bar.active : Color.accent
                shadowBlur: 0.95
                shadowOpacity: 0.50 + root.energy * 0.50
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }

            Repeater {
                model: root.barCount

                Item {
                    required property int index
                    readonly property real level: root.levelAt(index)
                    width: (spectrum.width - spectrum.spacing * (root.barCount - 1)) / root.barCount
                    height: spectrum.height

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(2, parent.height * parent.level)
                        radius: width / 2
                        opacity: parent.level > 0.015 ? 1 : 0.22
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: Qt.lighter(Color.accent, 1.35)
                            }
                            GradientStop {
                                position: 0.45
                                color: Color.accent
                            }
                            GradientStop {
                                position: 1.0
                                color: Color.bar.active
                            }
                        }

                        Behavior on height {
                            NumberAnimation {
                                duration: 45
                                easing.type: Easing.OutQuad
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 100
                            }
                        }
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: !root.analyzerAvailable
            text: "󰝛"
            color: Color.bar.active
            font.family: root.bar ? root.bar.fontFamily : "monospace"
            font.pixelSize: Math.max(12, parent.height * 0.46)
            opacity: 0.82
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        onEntered: if (root.bar)
            root.bar.showTooltip(root, root.tooltipText())
        onExited: if (root.bar)
            root.bar.hideTooltip(root)
    }

}
