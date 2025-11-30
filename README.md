# Cloud Storage Client (Unofficial)

An unofficial, cross-platform Flutter client for secure cloud storage services, currently supporting **Filen.io**.

This client provides a robust **two-panel Commander-style interface** for managing your local files and your remote cloud drive side-by-side, focusing on speed, efficiency, privacy, and batch operations.

## ⚠️ Disclaimer

This is an unofficial, open-source project and is **not** affiliated with, endorsed by, or supported by **Filen.io**. It is a personal project built for learning and to provide an alternative interface. It is work in progress. Use it at your own risk.

## Features

* **Provider Support:**
    * **Filen.io:** Upload, Download, file management.
* **Cross-Platform:** Runs on **macOS**, **Windows**, **Linux**, **Android**, and **iOS**.
* **Two-Panel View:** efficient "Commander" interface for moving files between Local and Remote.
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

## Getting Started

### Prerequisites

* [Flutter SDK](https://flutter.dev/docs/get-started/install) (>=3.0.0)
* A Filen.io account (or Internxt if enabling that module).

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
* **`FilenClientAdapter`**: Implementation using the Filen API.
* **`LocalFileService`**: Abstracts file system access to handle platform differences (e.g., macOS Scoped Bookmarks vs. standard `dart:io`).

## 📄 License

This project is licensed under the **GNU Affero General Public License v3.0**. See the `LICENSE` file for details.

This app is not affiliated with Filen.io or any other cloud/storage provider. All trademarks and brand names belong to their respective owners.