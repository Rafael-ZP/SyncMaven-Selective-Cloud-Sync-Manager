<p align="center">
  <a href="https://github.com/Rafael-ZP/SyncMaven-Selective-Cloud-Sync-Manager">
    <img src="https://github.com/user-attachments/assets/4b93eb0a-6902-4ad4-b350-75f4b3a90dfc" />
" alt="Logo" width="80" height="80">
  </a>
</p>

<h1 align="center">SyncMaven</h1>

<p align="center">
  Your intelligent, rule-based file synchronization manager for macOS.
  <br />
  <a href="https://github.com/Rafael-ZP/SyncMaven-Selective-Cloud-Sync-Manager/releases"><strong>Download the App »</strong></a>
  <br />
  <br />
  <a href="https://github.com/Rafael-ZP/SyncMaven-Selective-Cloud-Sync-Manager/issues">Report Bug</a>
  ·
  <a href="https://github.com/Rafael-ZP/SyncMaven-Selective-Cloud-Sync-Manager/issues">Request Feature</a>
</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/macOS-12.0%2B-blue"></a>
  <a href="#"><img src="https://img.shields.io/badge/Swift-5.7-orange.svg"></a>
  <a href="https://github.com/Rafael-ZP/SyncMaven-Selective-Cloud-Sync-Manager/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-lightgrey.svg"></a>
</p>

---

SyncMaven is a native macOS menu bar application that automates the synchronization of files from your local folders to Google Drive. Define your own rules and let SyncMaven handle the rest.

## Features

-   **Menu Bar App:** Lives in your menu bar for quick and easy access.
-   **Folder Watching:** Monitors local folders for new files in real-time.
-   **Google Drive Integration:** Securely upload files to your Google Drive.
-   **Rule-Based Syncing:** Use rules to filter which files get uploaded based on criteria like file size.
-   **Secure Authentication:** Uses OAuth 2.0 with PKCE for secure authentication with Google Drive.
-   **Persistent Folder Access:** Securely maintains access to your selected folders across app launches.
-   **Multi-Account Support:** Designed to support multiple Google Drive accounts.

## How It Works

SyncMaven is built with Swift and SwiftUI, providing a modern and native macOS experience. It uses the Combine framework for reactive programming and `FSEventStream` for efficient folder monitoring.

The application's architecture is modular, with distinct components for managing accounts, synchronization, and UI. This ensures a clean separation of concerns and makes the codebase easy to maintain and extend.

-   **`SyncManager`:** The core component that orchestrates the file synchronization process.
-   **`AccountManager`:** Manages linked Google Drive accounts.
-   **`GoogleDriveManager`:** Handles all interactions with the Google Drive API.
-   **`RuleEngine`:** Filters files based on user-defined rules.
-   **SwiftUI Views:** Provide a modern and responsive user interface.

## Screenshots

<p align="center">
  <img src="<img width="903" height="697" alt="image" src="https://github.com/user-attachments/assets/4a364f19-c241-487e-8e77-a3377422bb3a" />
" alt="Main Window Screenshot" width="400"/>
  <br/>
  <em>Main application window showing watched folders.</em>
</p>

<p align="center">
  <img src="<img width="916" height="694" alt="Screenshot 2025-11-28 at 20 23 49" src="https://github.com/user-attachments/assets/861ab838-9529-44f7-9d56-65d85606fc8a" />
" alt="Accounts Tab Screenshot" width="400"/>
  <br/>
  <em>Accounts tab for managing cloud accounts.</em>
</p>

## Installation

You can download the latest version of SyncMaven from the [GitHub Releases page](https://github.com/Rafael-ZP/SyncMaven-Selective-Cloud-Sync-Manager/releases).

**Note:** Since the app is not yet notarized by Apple, you will see a warning when you first open it. To bypass this, right-click the app icon and select "Open". You will then be able to open the app normally.

## Beta Program

We are currently running a beta program for SyncMaven. We are looking for up to 100 testers to help us identify bugs and provide feedback. If you would like to join the beta program, please [create an issue](https://github.com/Rafael-ZP/SyncMaven-Selective-Cloud-Sync-Manager/issues) with your email address and we will add you to the list of testers.

## For Developers

If you want to contribute to SyncMaven or build it from source, please follow the instructions below.

### Prerequisites

-   macOS 12.0 or later
-   Xcode 14.0 or later

### Building from Source

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/Rafael-ZP/SyncMaven-Selective-Cloud-Sync-Manager.git
    cd SyncMaven-Selective-Cloud-Sync-Manager
    ```

2.  **Open the project in Xcode:**
    ```bash
    open SyncMaven/SyncMaven.xcodeproj
    ```

3.  **Configure Signing & Capabilities:**
    -   In the project navigator, select the `SyncMaven` project, then the `SyncMaven` target.
    -   Go to the "Signing & Capabilities" tab.
    -   Select your development team.

4.  **Add Google Client ID:**
    -   Open `SyncMaven/SyncMaven/Core/OAuth2PKCE.swift`.
    -   Replace the placeholder values for `clientID` and `clientSecret` with your actual credentials from the Google Cloud Console.

5.  **Build and Run from Xcode:**
    -   Select the `SyncMaven` scheme and a run destination (My Mac).
    -   Click the "Run" button (or press `Cmd+R`).

6.  **Build from the Command Line:**

    You can also build the project from the command line using `xcodebuild`. However, it is recommended to use the provided build script, which ensures the correct parameters are used.

    ```bash
    ./SyncMaven/scripts/build.sh
    ```

    Alternatively, you can run `xcodebuild` directly:

    ```bash
    xcodebuild -scheme SyncMaven -project SyncMaven/SyncMaven.xcodeproj build -configuration Release
    ```

## Usage

1.  Launch SyncMaven. The app icon will appear in your menu bar.
2.  Click the icon to open the main window.
3.  In the "Watched Folders" tab, click the "+" button to add a folder you want to monitor.
4.  In the "Accounts" tab, add your Google Drive accounts.
5.  Configure your synchronization rules in the "Rules" tab.
6.  SyncMaven will now automatically upload new files from your watched folders to your cloud storage based on your rules.

## Contributing

Contributions are welcome! If you have a feature request or have found a bug, please [create an issue](https://github.com/Rafael-ZP/SyncMaven-Selective-Cloud-Sync-Manager/issues). If you would like to contribute code, please fork the repository and create a pull request.

1.  Fork the repository.
2.  Create your feature branch (`git checkout -b feature/AmazingFeature`).
3.  Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4.  Push to the branch (`git push origin feature/AmazingFeature`).
5.  Open a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/Rafael-ZP/SyncMaven-Selective-Cloud-Sync-Manager/blob/main/LICENSE) file for details.
