import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var chatHistory: []
    property bool isRequesting: false
    property bool isProcessingFile: false

    // Dynamic Sizing Properties
    property int customWidth: 460
    property int customHeight: 250
    property bool isMaximized: false
    property bool hasUserResized: false

    // Attachment State
    property bool hasAttachment: false
    property string attachedFileName: ""
    property string attachedFileSize: ""
    property string attachedMimeType: ""
    property string attachedImagePath: ""
    property string attachedBase64: ""
    property bool attachedIsImage: false
    property string copyFeedback: ""

    property string configPath: Quickshell.env("HOME") + "/.config/DankMaterialShell/gemini_config.json"
    property var configData: ({ "apiKey": "", "model": "gemini-3.6-flash", "systemPrompt": "You are an expert desktop assistant on Linux and Niri. When given an image, code, or document, directly analyze and answer questions about it." })

    FileView {
        id: configFile
        path: root.configPath
        watchChanges: true
        onLoaded: {
            try {
                root.configData = JSON.parse(text());
            } catch (e) {}
        }
    }

    // Reads the JSON payload created by attach_helper.py
    FileView {
        id: attachmentJsonReader
        watchChanges: true
        onLoaded: {
            try {
                var data = JSON.parse(text());
                root.attachedFileName = data.name;
                root.attachedFileSize = data.size;
                root.attachedMimeType = data.mime;
                root.attachedIsImage = data.isImage;
                root.attachedImagePath = data.imagePath || "";
                root.attachedBase64 = data.b64;
                root.hasAttachment = true;
                root.isProcessingFile = false;
            } catch (e) {
                root.isProcessingFile = false;
            }
        }
    }

    // Native Wayland File Picker
    FileDialog {
        id: filePicker
        title: "Select file to attach to Gemini"
        onAccepted: {
            var path = selectedFile.toString();
            if (path.startsWith("file://")) {
                path = decodeURIComponent(path.substring(7));
            }
            processFileWithPython(path);
        }
    }

    Process {
        id: pythonAttachProc
        onExited: (code, status) => {
            if (code === 0) {
                attachmentJsonReader.path = "";
                attachmentJsonReader.path = "/tmp/dms_gemini_attach.json";
            } else {
                root.isProcessingFile = false;
                appendMessage("System", "Could not process file.", null);
            }
        }
    }

    function processFileWithPython(filePath) {
        root.isProcessingFile = true;
        var helper = Quickshell.env("HOME") + "/.config/DankMaterialShell/plugins/geminiAssistant/attach_helper.py";
        pythonAttachProc.exec([helper, filePath]);
    }

    // Screenshot Process (📸)
    Process {
        id: fullScreenProc
        onExited: (code, status) => {
            if (code === 0) {
                processFileWithPython("/tmp/dms_gemini_shot.jpg");
            } else {
                root.isProcessingFile = false;
                appendMessage("System", "Screenshot capture failed.", null);
            }
        }
    }

    function captureFullScreen() {
        root.isProcessingFile = true;
        var cmd = "rm -f /tmp/dms_gemini_shot.jpg && grim -t jpeg -q 75 /tmp/dms_gemini_shot.jpg";
        fullScreenProc.exec(["sh", "-c", cmd]);
    }

    function discardAttachment() {
        root.hasAttachment = false;
        root.attachedFileName = "";
        root.attachedFileSize = "";
        root.attachedMimeType = "";
        root.attachedImagePath = "";
        root.attachedBase64 = "";
        root.attachedIsImage = false;
    }

    Process {
        id: saveKeyProcess
    }

    function saveApiKeyDirectly(key) {
        root.configData.apiKey = key;
        var jsonStr = JSON.stringify(root.configData, null, 2);
        saveKeyProcess.exec(["sh", "-c", "printf '%s' " + Qt.btoa(jsonStr) + " | base64 -d > " + root.configPath]);
        appendMessage("System", "✓ API key saved successfully!", null);
    }

    Process {
        id: copyProcess
    }

    function copyToClipboard(content, index) {
        copyProcess.exec(["sh", "-c", "printf '%s' " + Qt.btoa(content) + " | base64 -d | wl-copy"]);
        root.copyFeedback = "copied_" + index;
        feedbackTimer.restart();
    }

    Timer {
        id: feedbackTimer
        interval: 1800
        onTriggered: root.copyFeedback = ""
    }

    function sendPrompt(inputRef) {
        var text = inputRef.text.trim();
        if (text === "" && !root.hasAttachment) return;
        if (root.isRequesting) return;

        if (text.startsWith("/key ")) {
            saveApiKeyDirectly(text.substring(5).trim());
            inputRef.text = "";
            return;
        }

        var apiKey = (root.configData && root.configData.apiKey) ? root.configData.apiKey.trim() : "";
        if (!apiKey) {
            appendMessage("System", "Please set your API key: /key YOUR_KEY", null);
            return;
        }

        var modelName = (root.configData && root.configData.model) ? root.configData.model : "gemini-3.6-flash";
        var promptText = text !== "" ? text : "Please examine and explain this attached file.";

        var sentAttachmentInfo = null;
        if (root.hasAttachment && root.attachedBase64 !== "") {
            sentAttachmentInfo = {
                "name": root.attachedFileName,
                "size": root.attachedFileSize,
                "mime": root.attachedMimeType || "application/octet-stream",
                "isImage": root.attachedIsImage,
                "imagePath": root.attachedImagePath,
                "b64": root.attachedBase64
            };
            discardAttachment();
        }

        appendMessage("User", promptText, sentAttachmentInfo);
        inputRef.text = "";
        root.isRequesting = true;

        var contentsPayload = [];
        for (var i = 0; i < root.chatHistory.length; i++) {
            var entry = root.chatHistory[i];
            if (entry.sender === "User") {
                var userParts = [];
                if (entry.attachment && entry.attachment.b64) {
                    userParts.push({
                        "inlineData": {
                            "mimeType": entry.attachment.mime,
                            "data": entry.attachment.b64
                        }
                    });
                }
                userParts.push({ "text": entry.text });
                contentsPayload.push({ "role": "user", "parts": userParts });
            } else if (entry.sender === "Gemini") {
                contentsPayload.push({ "role": "model", "parts": [{ "text": entry.text }] });
            }
        }

        var reqBody = {
            "contents": contentsPayload,
            "systemInstruction": {
                "parts": [{ "text": (root.configData && root.configData.systemPrompt) ? root.configData.systemPrompt : "You are an expert desktop assistant on Linux and Niri. When given an image, code, or document, directly analyze and answer questions about it." }]
            }
        };

        var xhr = new XMLHttpRequest();
        var url = "https://generativelanguage.googleapis.com/v1beta/models/" + modelName + ":generateContent?key=" + apiKey;

        xhr.open("POST", url, true);
        xhr.setRequestHeader("Content-Type", "application/json");

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.isRequesting = false;
                if (xhr.status === 200) {
                    try {
                        var res = JSON.parse(xhr.responseText);
                        var reply = res.candidates[0].content.parts[0].text;
                        appendMessage("Gemini", reply, null);
                    } catch (e) {
                        appendMessage("Error", "Parsing error: " + e.message, null);
                    }
                } else {
                    appendMessage("Error", "HTTP " + xhr.status + ": " + xhr.responseText, null);
                }
            }
        };

        xhr.send(JSON.stringify(reqBody));
    }

    function appendMessage(sender, text, attachment) {
        var updated = root.chatHistory.slice();
        updated.push({ "sender": sender, "text": text, "attachment": attachment });
        root.chatHistory = updated;
    }

    // Horizontal bar pill
    horizontalBarPill: Component {
        Item {
            implicitWidth: pillRow.implicitWidth + 14
            implicitHeight: 28

            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: 5

                Text {
                    text: "✦"
                    font.pixelSize: 13
                    color: Theme.primary
                }

                Text {
                    text: "Gemini"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: Theme.onSurface
                }
            }
        }
    }

    // Vertical bar pill
    verticalBarPill: Component {
        Item {
            implicitWidth: 28
            implicitHeight: 28
            Text {
                anchors.centerIn: parent
                text: "✦"
                font.pixelSize: 14
                color: Theme.primary
            }
        }
    }

    // Popout Card with Dynamic Width & Height
    popoutContent: Component {
        Rectangle {
            id: cardContainer

            // Calculate dynamic height: compact when empty, expands with conversation
            readonly property int naturalHeight: root.chatHistory.length === 0 
                ? (root.hasAttachment ? 290 : 230)
                : 580

            implicitWidth: root.isMaximized 
                ? 720 
                : (root.hasUserResized ? root.customWidth : 460)

            implicitHeight: root.isMaximized 
                ? 780 
                : (root.hasUserResized ? root.customHeight : naturalHeight)

            Behavior on implicitWidth {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on implicitHeight {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            color: Theme.surfaceContainer
            radius: 20
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.25)
            border.width: 1
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.primaryContainer
                        Text {
                            anchors.centerIn: parent
                            text: "✦"
                            font.pixelSize: 13
                            color: Theme.onPrimaryContainer
                        }
                    }

                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "Gemini AI"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: Theme.onSurface
                        }
                        Text {
                            text: (root.configData && root.configData.model) ? root.configData.model : "gemini-3.6-flash"
                            font.pixelSize: 10
                            color: Theme.onSurfaceVariant
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Maximize / Restore Toggle Button
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: maxHover.hovered ? Theme.surfaceContainerHighest : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: root.isMaximized ? "⤡" : "⤢"
                            font.pixelSize: 12
                            color: Theme.onSurfaceVariant
                        }

                        HoverHandler { id: maxHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.isMaximized = !root.isMaximized
                        }
                    }

                    // Clear button
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: clearHover.hovered ? Theme.surfaceContainerHighest : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.pixelSize: 11
                            color: Theme.onSurfaceVariant
                        }

                        HoverHandler { id: clearHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.chatHistory = [];
                                root.discardAttachment();
                                root.hasUserResized = false;
                            }
                        }
                    }
                }

                // Empty State Quick Prompts (Visible only when chat is empty)
                RowLayout {
                    visible: root.chatHistory.length === 0
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        height: 26
                        radius: 13
                        color: Theme.surfaceContainerHighest
                        implicitWidth: qp1Text.implicitWidth + 16

                        Text {
                            id: qp1Text
                            anchors.centerIn: parent
                            text: "📸 Analyze Screen"
                            font.pixelSize: 11
                            color: Theme.onSurface
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.captureFullScreen();
                                chatInput.text = "Explain what is on my screen.";
                            }
                        }
                    }

                    Rectangle {
                        height: 26
                        radius: 13
                        color: Theme.surfaceContainerHighest
                        implicitWidth: qp2Text.implicitWidth + 16

                        Text {
                            id: qp2Text
                            anchors.centerIn: parent
                            text: "📎 Inspect File"
                            font.pixelSize: 11
                            color: Theme.onSurface
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: filePicker.open()
                        }
                    }
                }

                // Chat Messages List (Grows dynamically as conversation happens)
                ListView {
                    id: chatList
                    visible: root.chatHistory.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 10
                    model: root.chatHistory
                    onCountChanged: chatList.positionViewAtEnd()

                    delegate: ColumnLayout {
                        width: chatList.width
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            layoutDirection: modelData.sender === "User" ? Qt.RightToLeft : Qt.LeftToRight

                            Rectangle {
                                Layout.maximumWidth: chatList.width * 0.88
                                radius: 14
                                color: modelData.sender === "User" 
                                       ? Theme.primary 
                                       : (modelData.sender === "System" ? Theme.surfaceContainerHighest : Theme.surface)
                                border.color: modelData.sender === "Gemini" ? Qt.rgba(Theme.outlineVariant.r, Theme.outlineVariant.g, Theme.outlineVariant.b, 0.3) : "transparent"
                                border.width: 1
                                implicitWidth: Math.max(bubbleCol.implicitWidth + 24, modelData.attachment ? 200 : 60)
                                implicitHeight: bubbleCol.implicitHeight + 20

                                ColumnLayout {
                                    id: bubbleCol
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 6

                                    // Attachment Thumbnail/Chip inside bubble
                                    Rectangle {
                                        visible: !!modelData.attachment
                                        Layout.fillWidth: true
                                        implicitHeight: modelData.attachment && modelData.attachment.isImage ? 140 : 36
                                        radius: 8
                                        color: Qt.rgba(0, 0, 0, 0.25)
                                        clip: true

                                        Image {
                                            visible: !!(modelData.attachment && modelData.attachment.isImage)
                                            anchors.fill: parent
                                            cache: false
                                            source: (modelData.attachment && modelData.attachment.imagePath) ? modelData.attachment.imagePath : ""
                                            fillMode: Image.PreserveAspectCrop
                                        }

                                        RowLayout {
                                            visible: !(modelData.attachment && modelData.attachment.isImage)
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 6

                                            Text {
                                                text: "📎"
                                                font.pixelSize: 13
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.attachment ? (modelData.attachment.name + " (" + modelData.attachment.size + ")") : ""
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                                color: Theme.onPrimary
                                                elide: Text.ElideMiddle
                                            }
                                        }
                                    }

                                    // Gemini Bubble Header with Copy Button
                                    RowLayout {
                                        visible: modelData.sender === "Gemini"
                                        Layout.fillWidth: true

                                        Text {
                                            text: "Gemini"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: Theme.primary
                                        }

                                        Item { Layout.fillWidth: true }

                                        Rectangle {
                                            width: 48
                                            height: 18
                                            radius: 9
                                            color: copyHover.hovered ? Theme.primaryContainer : "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.copyFeedback === ("copied_" + index) ? "✓ Done" : "Copy"
                                                font.pixelSize: 10
                                                font.weight: Font.Medium
                                                color: root.copyFeedback === ("copied_" + index) ? Theme.primary : Theme.onSurfaceVariant
                                            }

                                            HoverHandler { id: copyHover }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.copyToClipboard(modelData.text, index)
                                            }
                                        }
                                    }

                                    TextEdit {
                                        Layout.fillWidth: true
                                        readOnly: true
                                        selectByMouse: true
                                        wrapMode: TextEdit.Wrap
                                        textFormat: TextEdit.MarkdownText
                                        text: modelData.text
                                        font.pixelSize: 12
                                        font.family: "Sans"
                                        color: modelData.sender === "User" ? Theme.onPrimary : Theme.onSurface
                                    }
                                }
                            }
                        }
                    }
                }

                // Loading Indicator
                RowLayout {
                    visible: root.isRequesting || root.isProcessingFile
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "✦"
                        font.pixelSize: 11
                        color: Theme.primary
                    }
                    Text {
                        text: root.isProcessingFile ? "Attaching file..." : "Gemini is analyzing..."
                        font.pixelSize: 11
                        font.italic: true
                        color: Theme.onSurfaceVariant
                    }
                }

                // Live Visual Attachment Preview Card
                Rectangle {
                    visible: root.hasAttachment
                    Layout.fillWidth: true
                    height: 56
                    radius: 12
                    color: Theme.surfaceContainerHighest
                    border.color: Theme.primary
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 8

                        Rectangle {
                            visible: root.attachedIsImage
                            Layout.preferredWidth: 64
                            Layout.fillHeight: true
                            radius: 6
                            color: "black"
                            clip: true

                            Image {
                                anchors.fill: parent
                                cache: false
                                source: root.attachedImagePath
                                fillMode: Image.PreserveAspectCrop
                            }
                        }

                        Rectangle {
                            visible: !root.attachedIsImage
                            Layout.preferredWidth: 42
                            Layout.fillHeight: true
                            radius: 6
                            color: Theme.primaryContainer

                            Text {
                                anchors.centerIn: parent
                                text: "📄"
                                font.pixelSize: 18
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: root.attachedFileName
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: Theme.onSurface
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                            Text {
                                text: root.attachedFileSize + " • Ready to send"
                                font.pixelSize: 10
                                color: Theme.onSurfaceVariant
                            }
                        }

                        // Remove attachment
                        Rectangle {
                            width: 26
                            height: 26
                            radius: 13
                            color: discardHover.hovered ? Theme.errorContainer : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.pixelSize: 11
                                color: discardHover.hovered ? Theme.onErrorContainer : Theme.onSurfaceVariant
                            }

                            HoverHandler { id: discardHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.discardAttachment()
                            }
                        }
                    }
                }

                // Composer Input Bar
                Rectangle {
                    Layout.fillWidth: true
                    height: 46
                    radius: 23
                    color: Theme.surfaceContainerHighest
                    border.color: Qt.rgba(Theme.outlineVariant.r, Theme.outlineVariant.g, Theme.outlineVariant.b, 0.4)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 6

                        // Full Screen (📸)
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: fullCamHover.hovered ? Theme.surfaceContainerHigh : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "📸"
                                font.pixelSize: 14
                            }

                            HoverHandler { id: fullCamHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.captureFullScreen()
                            }
                        }

                        // File Attachment (📎)
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: attachHover.hovered ? Theme.surfaceContainerHigh : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "📎"
                                font.pixelSize: 14
                                color: Theme.onSurfaceVariant
                            }

                            HoverHandler { id: attachHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: filePicker.open()
                            }
                        }

                        // Text Field
                        TextField {
                            id: chatInput
                            Layout.fillWidth: true
                            placeholderText: root.hasAttachment ? ("Ask about " + root.attachedFileName + "...") : "Ask Gemini..."
                            font.pixelSize: 12
                            color: Theme.onSurface
                            background: null
                            onAccepted: root.sendPrompt(chatInput)
                        }

                        // Send Button
                        Rectangle {
                            width: 34
                            height: 34
                            radius: 17
                            color: chatInput.text.trim() !== "" || root.hasAttachment ? Theme.primary : Theme.surfaceContainerLow

                            Text {
                                anchors.centerIn: parent
                                text: "➤"
                                font.pixelSize: 12
                                color: chatInput.text.trim() !== "" || root.hasAttachment ? Theme.onPrimary : Theme.outline
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.isRequesting && (chatInput.text.trim() !== "" || root.hasAttachment)
                                onClicked: root.sendPrompt(chatInput)
                            }
                        }
                    }
                }
            }

            // Interactive Drag-to-Resize Corner Handle (Bottom-Right)
            Item {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 20
                height: 20

                Text {
                    anchors.centerIn: parent
                    text: "⋰"
                    font.pixelSize: 12
                    color: Theme.outline
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeFDiagCursor
                    property point startPos

                    onPressed: (mouse) => {
                        startPos = Qt.point(mouse.x, mouse.y);
                        root.hasUserResized = true;
                    }

                    onPositionChanged: (mouse) => {
                        var dx = mouse.x - startPos.x;
                        var dy = mouse.y - startPos.y;

                        root.customWidth = Math.max(380, Math.min(950, cardContainer.implicitWidth + dx));
                        root.customHeight = Math.max(220, Math.min(900, cardContainer.implicitHeight + dy));
                    }
                }
            }
        }
    }
}