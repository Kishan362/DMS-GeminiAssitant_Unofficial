import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: root
    spacing: 16
    width: parent ? parent.width : 420

    property string configPath: Quickshell.env("HOME") + "/.config/DankMaterialShell/gemini_config.json"
    property var configData: ({ "apiKey": "", "model": "gemini-3.6-flash", "systemPrompt": "You are an expert desktop assistant on Linux. When given an image, code, or document, directly analyze and answer questions about it." })
    property string statusMsg: ""

    FileView {
        id: settingsFileReader
        path: root.configPath
        watchChanges: true
        onLoaded: {
            try {
                var raw = text().trim();
                if (raw) {
                    root.configData = JSON.parse(raw);
                    apiKeyField.text = root.configData.apiKey || "";
                    var idx = modelSelector.model.indexOf(root.configData.model || "gemini-3.6-flash");
                    modelSelector.currentIndex = Math.max(0, idx);
                    systemPromptArea.text = root.configData.systemPrompt || "";
                }
            } catch (e) {}
        }
    }

    Process {
        id: saveProcess
        onExited: (code, status) => {
            if (code === 0) {
                root.statusMsg = "✓ Settings saved!";
                resetStatusTimer.restart();
            }
        }
    }

    Timer {
        id: resetStatusTimer
        interval: 2500
        onTriggered: root.statusMsg = ""
    }

    function saveAll() {
        root.configData.apiKey = apiKeyField.text.trim();
        root.configData.model = modelSelector.currentText;
        root.configData.systemPrompt = systemPromptArea.text.trim();

        var jsonStr = JSON.stringify(root.configData, null, 2);
        saveProcess.exec(["sh", "-c", "mkdir -p ~/.config/DankMaterialShell && printf '%s' " + Qt.btoa(jsonStr) + " | base64 -d > " + root.configPath]);
    }

    // Title & Status
    RowLayout {
        Layout.fillWidth: true
        Label {
            text: "Gemini Configuration"
            font.bold: true
            font.pixelSize: 15
            color: Theme.onSurface
        }
        Item { Layout.fillWidth: true }
        Label {
            visible: root.statusMsg !== ""
            text: root.statusMsg
            font.pixelSize: 11
            color: Theme.primary
        }
    }

    // API Key Field
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Label {
            text: "Google AI Studio API Key:"
            font.pixelSize: 12
            color: Theme.onSurfaceVariant
        }

        TextField {
            id: apiKeyField
            Layout.fillWidth: true
            echoMode: showKeyBox.checked ? TextInput.Normal : TextInput.Password
            placeholderText: "AIzaSy..."
            color: Theme.onSurface
            font.pixelSize: 12
            onTextChanged: root.saveAll()
        }

        CheckBox {
            id: showKeyBox
            text: "Show Key"
            font.pixelSize: 11
        }
    }

    // Model Selector
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Label {
            text: "Gemini Model:"
            font.pixelSize: 12
            color: Theme.onSurfaceVariant
        }

        ComboBox {
            id: modelSelector
            Layout.fillWidth: true
            model: ["gemini-3.6-flash", "gemini-2.0-flash", "gemini-1.5-pro"]
            onActivated: root.saveAll()
        }
    }

    // System Persona Field
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Label {
            text: "System Persona:"
            font.pixelSize: 12
            color: Theme.onSurfaceVariant
        }

        TextArea {
            id: systemPromptArea
            Layout.fillWidth: true
            wrapMode: TextEdit.Wrap
            font.pixelSize: 12
            color: Theme.onSurface
            onTextChanged: root.saveAll()
        }
    }
}
