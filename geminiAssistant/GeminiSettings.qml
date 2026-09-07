import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: root
    spacing: 14
    width: parent ? parent.width : 400

    property string configPath: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/DankMaterialShell/gemini_config.json"
    property var configData: ({ "apiKey": "", "model": "gemini-2.5-flash", "systemPrompt": "You are an expert desktop assistant on Linux and Niri. Provide concise code and answers." })

    FileView {
        id: configFile
        path: root.configPath
        onLoaded: {
            try {
                root.configData = JSON.parse(text());
                apiKeyField.text = root.configData.apiKey || "";
                modelSelector.currentIndex = Math.max(0, modelSelector.model.indexOf(root.configData.model || "gemini-2.5-flash"));
                promptArea.text = root.configData.systemPrompt || "";
            } catch (e) {}
        }
    }

    function saveSettings() {
        root.configData.apiKey = apiKeyField.text.trim();
        root.configData.model = modelSelector.currentText;
        root.configData.systemPrompt = promptArea.text.trim();
        configFile.setText(JSON.stringify(root.configData, null, 2));
    }

    Label {
        text: "Google Gemini Configuration"
        font.bold: true
        font.pixelSize: 15
        color: Theme.onSurface
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Label {
            text: "Gemini API Key:"
            font.pixelSize: 12
            color: Theme.onSurfaceVariant
        }

        TextField {
            id: apiKeyField
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: "Paste your AI Studio key (AIzaSy...)"
            onTextChanged: root.saveSettings()
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Label {
            text: "Model Selection:"
            font.pixelSize: 12
            color: Theme.onSurfaceVariant
        }

        ComboBox {
            id: modelSelector
            Layout.fillWidth: true
            model: ["gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-pro"]
            onActivated: root.saveSettings()
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Label {
            text: "System Persona:"
            font.pixelSize: 12
            color: Theme.onSurfaceVariant
        }

        TextArea {
            id: promptArea
            Layout.fillWidth: true
            wrapMode: TextEdit.Wrap
            onTextChanged: root.saveSettings()
        }
    }
}
