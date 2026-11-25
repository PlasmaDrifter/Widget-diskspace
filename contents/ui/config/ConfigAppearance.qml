import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support

KCM.SimpleKCM {
    id: root

    property alias cfg_bgOpacity: opacitySlider.value
    property string cfg_textColor: plasmoid.configuration.textColor
    property alias cfg_showTitle: showTitleCheckbox.checked
    property alias cfg_fontWeight: fontWeightCombo.currentIndex
    property string cfg_driveColors: plasmoid.configuration.driveColors
    property string cfg_driveLabels: plasmoid.configuration.driveLabels
    property string cfg_displayedDrives: plasmoid.configuration.displayedDrives
    property string cfg_driveOrder: plasmoid.configuration.driveOrder

    property var addedDrives: ({})
    property var displayedMap: ({})
    property var colorsMap: ({})
    property var labelsMap: ({})

    ListModel {
        id: drivesModel
    }

    function getDefaultFriendlyName(mount) {
        if (mount === '/') return i18n("Root");
        if (mount === '/home') return i18n("Home");
        return mount.split('/').pop() || mount;
    }

    function parseMountMap(raw, validator) {
        var result = {};
        var lines = (raw || "").split('\n');
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (!line) continue;
            var sep = line.indexOf(':');
            if (sep <= 0) continue;
            var mount = line.slice(0, sep).trim();
            var value = line.slice(sep + 1).trim();
            if (!validator || validator(value)) {
                result[mount] = value;
            }
        }
        return result;
    }

    function loadSettings() {
        drivesModel.clear();

        var displayedMap = {};
        var displayedDrives = root.cfg_displayedDrives.split('\n').map(function(m) { return m.trim(); }).filter(function(m) { return m; });
        displayedDrives.forEach(function(mount) {
            displayedMap[mount] = true;
        });

        var colorsMap = root.parseMountMap(root.cfg_driveColors, function(v) {
            return /^#[0-9A-Fa-f]{6}$/.test(v);
        });
        var labelsMap = root.parseMountMap(root.cfg_driveLabels, function(v) {
            return v.length > 0;
        });

        var added = {};
        displayedDrives.forEach(function(mount) {
            if (!added[mount]) {
                drivesModel.append({
                    mountPoint: mount,
                    displayed: true,
                    color: colorsMap[mount] || "#ffffff",
                    customLabel: labelsMap[mount] || ""
                });
                added[mount] = true;
            }
        });

        for (var mount in colorsMap) {
            if (!added[mount]) {
                drivesModel.append({
                    mountPoint: mount,
                    displayed: false,
                    color: colorsMap[mount],
                    customLabel: labelsMap[mount] || ""
                });
                added[mount] = true;
            }
        }

        for (var mount in labelsMap) {
            if (!added[mount]) {
                drivesModel.append({
                    mountPoint: mount,
                    displayed: false,
                    color: colorsMap[mount] || "#ffffff",
                    customLabel: labelsMap[mount] || ""
                });
                added[mount] = true;
            }
        }
        
        root.addedDrives = added;
        root.displayedMap = displayedMap;
        root.colorsMap = colorsMap;
        root.labelsMap = labelsMap;
    }

    function saveSettings() {
        var displayed = [];
        var colors = [];
        var labels = [];
        for (var i = 0; i < drivesModel.count; i++) {
            var item = drivesModel.get(i);
            if (item.displayed) {
                displayed.push(item.mountPoint);
            }
            colors.push(item.mountPoint + ":  " + item.color);
            if (item.customLabel && item.customLabel.trim().length > 0) {
                labels.push(item.mountPoint + ":  " + item.customLabel.trim());
            }
        }
        root.cfg_displayedDrives = displayed.join("\n");
        root.cfg_driveOrder = root.cfg_displayedDrives;
        root.cfg_driveColors = colors.join("\n");
        root.cfg_driveLabels = labels.join("\n");
    }

    function parseDfOutput(stdout) {
        if (!stdout) return;
        var lines = stdout.split('\n');
        lines.forEach(function(rawLine) {
            var mount = rawLine.trim();
            if (!mount || mount === 'Mounted on') return;
            if (mount.startsWith('/') && !mount.startsWith('/sys') && !mount.startsWith('/proc') && !mount.startsWith('/run') && !mount.startsWith('/dev')) {
                if (!root.addedDrives[mount]) {
                    drivesModel.append({
                        mountPoint: mount,
                        displayed: false,
                        color: root.colorsMap[mount] || "#ffffff",
                        customLabel: root.labelsMap[mount] || ""
                    });
                    root.addedDrives[mount] = true;
                }
            }
        });
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            var stdout = data["stdout"]
            if (stdout) {
                root.parseDfOutput(stdout)
            }
            disconnectSource(sourceName)
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    Component.onCompleted: {
        root.loadSettings()
        executable.exec("timeout 3 df -BK -l --output=target 2>/dev/null")
    }

    Kirigami.FormLayout {
        anchors.fill: parent

        // --- General Appearance ---
        Kirigami.Separator { Kirigami.FormData.label: i18n("General Settings"); Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: showTitleCheckbox
            Kirigami.FormData.label: i18n("Show widget title:")
            text: i18n("Show Title")
        }

        QQC2.ComboBox {
            id: fontWeightCombo
            Kirigami.FormData.label: i18n("Font weight:")
            model: [
                i18n("Normal"),
                i18n("Medium"),
                i18n("Demi-Bold"),
                i18n("Bold")
            ]
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Background opacity:")
            QQC2.Slider {
                id: opacitySlider
                from: 0.0
                to: 1.0
                stepSize: 0.05
            }
            QQC2.Label {
                text: Math.round(opacitySlider.value * 100) + "%"
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Text color:")
            Rectangle {
                id: textColorPreview
                width: Kirigami.Units.gridUnit * 1.6
                height: Kirigami.Units.gridUnit * 1.6
                color: root.cfg_textColor
                border.color: Kirigami.Theme.textColor
                border.width: 1
                radius: 4
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: textColorDialog.open()
                }
            }
            QQC2.Button {
                text: i18n("Choose…")
                onClicked: textColorDialog.open()
            }
            ColorDialog {
                id: textColorDialog
                selectedColor: root.cfg_textColor
                onAccepted: root.cfg_textColor = selectedColor
            }
        }

        // --- Drives Configuration ---
        Kirigami.Separator { Kirigami.FormData.label: i18n("Drive Space & Colors"); Kirigami.FormData.isSection: true }

        ColumnLayout {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 32
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.largeSpacing

            Repeater {
                model: drivesModel
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    QQC2.CheckBox {
                        checked: model.displayed
                        onToggled: {
                            drivesModel.setProperty(index, "displayed", checked);
                            root.saveSettings();
                        }
                    }

                    Rectangle {
                        width: Kirigami.Units.gridUnit * 1.6
                        height: Kirigami.Units.gridUnit * 1.6
                        color: model.color
                        border.color: Kirigami.Theme.textColor
                        border.width: 1
                        radius: 4
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: driveColorDialog.open()
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        QQC2.TextField {
                            text: model.customLabel
                            font.bold: model.displayed
                            Layout.fillWidth: true
                            placeholderText: root.getDefaultFriendlyName(model.mountPoint)
                            onTextEdited: {
                                drivesModel.setProperty(index, "customLabel", text);
                                root.saveSettings();
                            }
                        }

                        QQC2.Label {
                            text: model.mountPoint
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize - 2
                            color: Kirigami.Theme.textColor
                            opacity: 0.7
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    RowLayout {
                        spacing: 2
                        QQC2.ToolButton {
                            icon.name: "go-up"
                            display: QQC2.AbstractButton.IconOnly
                            enabled: index > 0
                            implicitWidth: Kirigami.Units.gridUnit * 1.8
                            implicitHeight: Kirigami.Units.gridUnit * 1.8
                            onClicked: {
                                drivesModel.move(index, index - 1, 1);
                                root.saveSettings();
                            }
                        }
                        QQC2.ToolButton {
                            icon.name: "go-down"
                            display: QQC2.AbstractButton.IconOnly
                            enabled: index < drivesModel.count - 1
                            implicitWidth: Kirigami.Units.gridUnit * 1.8
                            implicitHeight: Kirigami.Units.gridUnit * 1.8
                            onClicked: {
                                drivesModel.move(index, index + 1, 1);
                                root.saveSettings();
                            }
                        }
                    }

                    ColorDialog {
                        id: driveColorDialog
                        selectedColor: model.color
                        onAccepted: {
                            drivesModel.setProperty(index, "color", driveColorDialog.selectedColor.toString());
                            root.saveSettings();
                        }
                    }
                }
            }
        }
    }
}
