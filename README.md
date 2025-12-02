# CrispCloud

[![Live Demo](https://img.shields.io/badge/Live_Demo-Vercel-black?style=for-the-badge&logo=vercel)](https://crisp-cloud.vercel.app/)

**CrispCloud** is an unofficial, cross-platform Flutter client for secure cloud storage services, supporting **Filen.io**, **WebDAV**, and **SFTP** (Secure File Transfer Protocol).

This client provides a **two-panel Commander-style interface** for managing your local files and your remote cloud drive side-by-side, focusing on speed, efficiency, privacy, and batch operations.

It runs natively on Desktop and Mobile, and as a **Progressive Web App (PWA)** directly in your browser.

## ⚠️ Disclaimer

This is an unofficial, open-source project and is **not** affiliated with, endorsed by, or supported by Filen.io or any other storage provider. It is a personal project built for learning and to provide an alternative interface. It is a work in progress. Use it at your own risk.

## Features

* **Provider Support:**
    * **Filen.io:** End-to-end encrypted Upload, Download, and file management. (Web version uses WebCrypto API for higher performance).
    * **WebDAV:** Standard operations (Requires CORS support on Web).
    * **SFTP:** Support for standard SFTP connections (Requires WebSocket proxy on Web).
* **Cross-Platform:** Runs on **Web (PWA)**, **macOS**, **Windows**, **Linux**, **Android**, and **iOS**.
* **Two-Panel View:** Efficient "Commander" interface for moving files between Local and Remote.
* **Web Virtual File System:**
    * On the Web, the "Local" pane acts as a **Staging Area**.
    * Supports picking entire folders (Chrome/Edge) or multiple files.
    * In-memory processing for "Save As" downloads.
* **MacOS Security Scoped Bookmarks:** Support for macOS App Sandbox permissions. The app remembers granted folder access across restarts.
* **Resumable Operations:** Auto-login and state restoration for seamless sessions.
* **Batch Operations:**
    * **Recursive Upload/Download:** Transfer entire folder structures.
    * **Queuing:** Manage multiple transfers with a progress panel.
    * **Conflict Resolution:** Options to skip, overwrite, or rename files.
* **File Management:** Create folders, Rename, Move, Copy, and Delete (Trash/Permanent).
* **Search & Find:**
    * **Deep Search:** Recursively find files within the cloud drive.
    * **Pattern Matching:** Supports glob patterns (e.g., `*.pdf`).
* **Keyboard Centric:** Fully navigable via keyboard shortcuts.

## Web (PWA) Notes

The Web version (Ddemo available at [crisp-cloud.vercel.app](https://crisp-cloud.vercel.app/)) has specific browser security constraints:

1.  **Local File System:** Browsers do not allow direct access to your drive. The "Local" pane works as a **Virtual Staging Area**. You must click "Open Local Folder" to import files/folders into the browser's memory before uploading.
2.  **WebDAV:** Your WebDAV server **must** support CORS (Cross-Origin Resource Sharing) and allow headers like `Depth`, `Destination`, and `Authorization`.
3.  **SFTP:** Browsers cannot open raw TCP sockets. To use SFTP on the web, your server endpoint must be a **WebSocket Proxy** (e.g., using `websockify`) that tunnels SSH traffic.

## Getting Started

### Prerequisites

* [Flutter SDK](https://flutter.dev/docs/get-started/install) (>=3.0.0)
* A Filen.io account, or credentials for an SFTP or WebDAV server.

### Installation

1.  **Clone the repository:**

    ```bash
    git clone [https://github.com/CrispStrobe/cloud-dart.git](https://github.com/CrispStrobe/cloud-dart.git)
    cd cloud-dart
    ```

2.  **Get dependencies:**

    ```bash
    flutter pub get
    ```

3.  **Run the app:**

    Select your target device and run:

    ```bash
    # For Web (Chrome)
    flutter run -d chrome --release

    # For macOS
    flutter run -d macos

    # For Windows
    flutter run -d windows
    ```

## Keyboard Shortcuts

The interface is designed for speed. Use these keys to navigate:

| Key | Action |
| :--- | :--- |
| `Tab` | Switch between Local and Remote panels |
| `Enter` | Open selected folder |
| `Backspace` | Navigate to parent folder |
| `Ctrl`/`Cmd` + `A` | Select all files in the active panel |
| `Escape` | Clear selection in the active panel |
| `Delete` | Delete selected items |
| `F2` | Rename selected item |
| `Ctrl`/`Cmd` + `N` | Create a new folder |
| `Ctrl`/`Cmd` + `R` / `F5` | Refresh the active panel |
| `Ctrl`/`Cmd` + `C` | Copy selected items (Local only) |
| `Ctrl`/`Cmd` + `X` | Move selected items |
| `Ctrl`/`Cmd` + `U` | Upload selected local items to remote |
| `Ctrl`/`Cmd` + `D` | Download selected remote items to local |

## Architecture

This project uses a modular Adapter pattern to abstract specific cloud provider APIs:

* **`CloudStorageClient`**: The abstract interface defining common operations (login, list, upload, download).
* **`FilenClientAdapter`**: Implementation using the Filen API (with WebCrypto optimization).
* **`SFTPClientAdapter`**: Implementation using `dartssh2`. On Web, this uses a custom `WebSSHSocket` wrapper.
* **`WebDAVClientAdapter`**: Implementation using `webdav_client` for generic WebDAV support.
* **`LocalFileService`**: Abstracts file system access.
    * **Desktop/Mobile:** Uses `dart:io` and platform-specific bookmarks.
    * **Web:** Uses a virtual in-memory file tree and `universal_html` for Blob handling.

## Architecture

Known limitations:

* Current architecture will fail e.g. on uploading **large files** (esp. if larger than available free RAM). We could fix this if needed (we would change LocalFileService to return a Stream<List<int>> instead of Uint8List, update CloudStorageClient to accept a Stream, rewrite e.g. FilenClient.uploadFile to encrypt and upload chunks as they stream in, without holding the full file in memory).

## 📄 License

This project is licensed under the **GNU Affero General Public License v3.0**. See the `LICENSE` file for details.

This app is not affiliated with Filen.io or any other cloud/storage provider. All trademarks and brand names belong to their respective owners.