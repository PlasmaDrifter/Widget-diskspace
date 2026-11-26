import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    property string currentCmd: ""
    property var lastKnownStats: ({})
    readonly property var fontWeights: [400, 500, 600, 700]

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    function fallbackLabel(mount) {
        if (mount === '/') return i18n("Root")
        if (mount === '/home') return i18n("Home")
        return mount.split('/').pop() || mount
    }

    function parseMountMap(raw, validator) {
        const result = {}
        const lines = (raw || "").split('\n')
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].trim()
            if (!line) continue
            const sep = line.indexOf(':')
            if (sep <= 0) continue
            const driveName = line.slice(0, sep).trim()
            const val = line.slice(sep + 1).trim()
            if (!validator || validator(val)) {
                result[driveName] = val
            }
        }
        return result
    }

    function getDisplayedDrives() {
        return (plasmoid.configuration.displayedDrives || "")
            .split('\n')
            .map(function(m) { return m.trim(); })
            .filter(function(m) { return m.length > 0; })
    }

    Plasma5Support.DataSource {
        id: dataSource
        engine: "executable"
        connectedSources: []

        function update() {
            if (root.currentCmd) {
                disconnectSource(root.currentCmd)
            }

            const displayedDrives = root.getDisplayedDrives()
            if (displayedDrives.length === 0) {
                diskModel.clear()
                return
            }

            const localMounts = []
            const externalMounts = []
            for (let i = 0; i < displayedDrives.length; ++i) {
                const mount = displayedDrives[i]
                if (mount.indexOf("/mnt/") === 0 || mount.indexOf("/media/") === 0 || mount.indexOf("/run/media/") === 0) {
                    externalMounts.push(mount)
                } else {
                    localMounts.push(mount)
                }
            }

            let script = ""
            if (localMounts.length > 0) {
                script = "timeout 2 df -BK --output=pcent,avail,target -- " + localMounts.map(root.shellQuote).join(" ") + " 2>/dev/null"
            }
            if (externalMounts.length > 0) {
                const extJobs = externalMounts.map(function(m) {
                    return "timeout 2 df -BK --output=pcent,avail,target -- " + root.shellQuote(m) + " 2>/dev/null &"
                }).join(" ")
                script = (script ? script + "; " : "") + extJobs + " wait"
            }
            root.currentCmd = script
            connectSource(root.currentCmd)
        }

        onNewData: function(source, data) {
            if (source === root.currentCmd) {
                parseDiskData(data.stdout)
                disconnectSource(source)
            }
        }
    }

    Connections {
        target: plasmoid.configuration
        function onDisplayedDrivesChanged() {
            dataSource.update()
        }
        function onDriveColorsChanged() {
            root.syncDiskModel()
        }
        function onDriveLabelsChanged() {
            root.syncDiskModel()
        }
    }

    ListModel {
        id: diskModel
    }

    function formatSize(kb) {
        const units = ["KB", "MB", "GB", "TB"]
        let size = parseInt(kb, 10) || 0
        let i = 0
        while (size >= 1024 && i < units.length - 1) {
            size /= 1024
            i++
        }
        return size.toFixed(1) + " " + units[i]
    }

    function syncDiskModel() {
        const displayedDrives = root.getDisplayedDrives()
        if (displayedDrives.length === 0) {
            diskModel.clear()
            return
        }

        const colors = root.parseMountMap(plasmoid.configuration.driveColors, function(v) {
            return /^#[0-9A-Fa-f]{6}$/.test(v)
        })
        const labels = root.parseMountMap(plasmoid.configuration.driveLabels, function(v) {
            return v.length > 0
        })

        const items = displayedDrives.map(function(mount) {
            const stats = root.lastKnownStats[mount]
            if (stats) {
                return {
                    "mount": mount,
                    "avail": stats.avail,
                    "usedPercent": stats.usedPercent,
                    "freePercent": stats.freePercent,
                    "color": colors[mount] || "#FFFFFF",
                    "isOffline": false,
                    "mountName": labels[mount] || root.fallbackLabel(mount)
                }
            }
            return {
                "mount": mount,
                "avail": i18n("Offline"),
                "usedPercent": 0,
                "freePercent": 0,
                "color": colors[mount] || "#FFFFFF",
                "isOffline": true,
                "mountName": labels[mount] || root.fallbackLabel(mount)
            }
        })

        let sameOrder = (diskModel.count === items.length)
        if (sameOrder) {
            for (let i = 0; i < items.length; ++i) {
                if (diskModel.get(i).mount !== items[i].mount) {
                    sameOrder = false
                    break
                }
            }
        }

        if (sameOrder) {
            for (let i = 0; i < items.length; ++i) {
                diskModel.set(i, items[i])
            }
        } else {
            diskModel.clear()
            for (let i = 0; i < items.length; ++i) {
                diskModel.append(items[i])
            }
        }
    }

    function parseDiskData(output) {
        const allDisks = {}
        const lines = (output || "").split('\n')
        const rowRe = /^\s*(\d+)%\s+(\d+)K\s+(.+?)\s*$/

        for (let i = 0; i < lines.length; ++i) {
            const match = rowRe.exec(lines[i])
            if (!match) continue

            const usedPercent = parseInt(match[1], 10) || 0
            const availKb = parseInt(match[2], 10) || 0
            const mount = match[3]
            if (!mount.startsWith('/') || mount.startsWith('/sys') || mount.startsWith('/proc') || mount.startsWith('/run')) {
                continue
            }

            allDisks[mount] = {
                "avail": formatSize(availKb),
                "usedPercent": usedPercent,
                "freePercent": Math.max(0, Math.min(100, 100 - usedPercent))
            }
        }

        root.lastKnownStats = allDisks
        root.syncDiskModel()
    }

    Component.onCompleted: {
        dataSource.update()
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: dataSource.update()
    }

    compactRepresentation: Component {
        Item {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 2
            Layout.minimumHeight: Kirigami.Units.gridUnit * 1
            clip: true

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: plasmoid.configuration.bgOpacity
                radius: 12
                z: 0
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                z: 1
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: i18n("Disk Space")
                    font.bold: true
                    color: plasmoid.configuration.textColor
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 2
                    visible: plasmoid.configuration.showTitle
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: diskModel
                    spacing: 15
                    clip: true

                    delegate: ColumnLayout {
                        width: ListView.view ? ListView.view.width : 0
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            PlasmaComponents.Label {
                                text: model.mountName
                                color: model.isOffline ? Kirigami.Theme.disabledTextColor : plasmoid.configuration.textColor
                                Layout.fillWidth: true
                                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize - 1
                                font.weight: root.fontWeights[plasmoid.configuration.fontWeight] || 400
                                elide: Text.ElideRight
                            }

                            PlasmaComponents.Label {
                                text: i18n("Offline")
                                color: Kirigami.Theme.disabledTextColor
                                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize - 2
                                visible: model.isOffline
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 4
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.2)
                            opacity: model.isOffline ? 0.35 : 1.0

                            Rectangle {
                                width: parent.width * (model.freePercent / 100)
                                height: parent.height
                                radius: 2
                                color: model.color
                            }
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.expanded = !root.expanded
            }
        }
    }

    fullRepresentation: Component {
        Item {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 4
            Layout.minimumHeight: Kirigami.Units.gridUnit * 3
            clip: true

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: plasmoid.configuration.bgOpacity
                radius: 12
                z: 0
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.gridUnit
                z: 1
                spacing: Kirigami.Units.gridUnit

                PlasmaComponents.Label {
                    text: i18n("Disk Space")
                    font.bold: true
                    color: plasmoid.configuration.textColor
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 4
                    visible: plasmoid.configuration.showTitle
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: plasmoid.configuration.textColor
                    opacity: 0.3
                    visible: plasmoid.configuration.showTitle
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: diskModel
                    spacing: 15
                    clip: true

                    delegate: ColumnLayout {
                        width: ListView.view ? ListView.view.width : 0
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            PlasmaComponents.Label {
                                text: model.mountName
                                color: model.isOffline ? Kirigami.Theme.disabledTextColor : plasmoid.configuration.textColor
                                Layout.fillWidth: true
                                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 1
                                font.weight: root.fontWeights[plasmoid.configuration.fontWeight] || 400
                                elide: Text.ElideRight
                            }

                            PlasmaComponents.Label {
                                text: model.avail
                                color: model.isOffline ? Kirigami.Theme.disabledTextColor : plasmoid.configuration.textColor
                                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                                font.weight: root.fontWeights[plasmoid.configuration.fontWeight] || 400
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 6
                            radius: 3
                            color: Qt.rgba(1, 1, 1, 0.2)
                            opacity: model.isOffline ? 0.35 : 1.0

                            Rectangle {
                                width: parent.width * (model.freePercent / 100)
                                height: parent.height
                                radius: 3
                                color: model.color
                            }
                        }
                    }
                }
            }
        }
    }
}
