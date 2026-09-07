# DMS Gemini Assistant (Unofficial)

An unofficial Google Gemini AI assistant plugin for Dank Material Shell. This plugin seamlessly integrates the power of Gemini directly into your shell workflow.

## 📦 Installation

Installation is incredibly straightforward. Just download the folder and drop it into your plugins directory.

1. Clone or download this repository.
2. Place the folder into your Dank Material Shell plugins directory:

```
bash
# Clone the repository
git clone [https://github.com/Kishan362/DMS-GeminiAssitant_Unofficial.git](https://github.com/Kishan362/DMS-GeminiAssitant_Unofficial.git)

# Move it to the plugins directory
mv DMS-GeminiAssitant_Unofficial ~/.config/DankMaterialShell/plugins/
'''

##
🛠️ Troubleshooting Dependencies
If the plugin fails to run or throws a "command not found" error (name-based dependency issue), it is likely because your system is missing the core utilities required to communicate with the Gemini API or parse its data.

Ensure you have curl (for API requests) and jq (for JSON parsing) installed on your system.

Here is how to resolve these dependencies based on your Linux distribution:

Arch Linux / CachyOS:

Bash
sudo pacman -S curl jq
Void Linux:

Bash
sudo xbps-install -Su curl jq
Ubuntu / Debian:

Bash
sudo apt update && sudo apt install curl jq
Fedora:

Bash
sudo dnf install curl jq
⚙️ Configuration
To interact with Google Gemini, you will need an API key from Google AI Studio.

Get your API key from Google AI Studio.

Add your key to the appropriate configuration file or environment variable as expected by the plugin script.

🤝 Contributing
Contributions, issues, and feature requests are welcome! Feel free to check the issues page.
