pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Ui

BarWidget {
    id: root
    moduleName: "neon-overdrive.cava"

    readonly property var cavaService: bar && bar.shell ? bar.shell.serviceFor("neon-overdrive.cava") : null
    readonly property var levels: cavaService ? cavaService.levels : []
    readonly property real energy: cavaService ? cavaService.energy : 0
    readonly property int barCount: 18

    function levelAt(index) {
        if (!levels || index >= levels.length)
            return 0;
        return Math.max(0, Math.min(1, Number(levels[index]) || 0));
    }

    implicitWidth: vertical ? barSize : 104
    implicitHeight: vertical ? 104 : barSize
    visible: true

    Item {
        id: rotatedCanvas
        width: root.vertical ? root.height : root.width
        height: root.vertical ? root.width : root.height
        anchors.centerIn: parent
        rotation: root.vertical ? 90 : 0

        Row {
            id: spectrum
            anchors.centerIn: parent
            width: parent.width - 10
            height: Math.max(14, parent.height - 8)
            spacing: 2

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: root.energy > 0.32 ? "#FF2BD6" : "#22D3EE"
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
                                color: "#7AFFFF"
                            }
                            GradientStop {
                                position: 0.45
                                color: "#22D3EE"
                            }
                            GradientStop {
                                position: 1.0
                                color: "#FF2BD6"
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
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: if (root.bar)
            root.bar.showTooltip(root, "Cava spectrum  •  " + Math.round(root.energy * 100) + "% energy")
        onExited: if (root.bar)
            root.bar.hideTooltip(root)
    }
}
