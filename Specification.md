# Project: UnjailTheos - iOS Local Theos Compiler GUI

## 1. Target Environment
- Platform: iOS 15.0+ (TrollStore installation)
- Entitlements: Unsandboxed, com.apple.private.security.no-sandbox, Root Helper enabled.

## 2. Architecture & Modules

### Module A: Environment Initializer
- **Feature 1**: Online SDK Downloader. Fetch from predefined URL (e.g., GitHub Theos SDKs), stream download via `URLSession` with progress tracking.
- **Feature 2**: Manual SDK Importer. Use `fileImporter` to copy local `.zip`/`.tar.xz` SDKs to `$App_Documents/theos/sdks/`.
- **Feature 3**: Auto-extract logic. Invoke system `tar` via Root Helper to preserve symbolic links.

### Module B: Code Editor GUI
- **Component**: Integrate `Runestone` or native UITextView with standard text storage.
- **Features**: Sidebar file tree browser targeting specific Tweak project folder; syntax highlighting for `.x`, `.xm`, `Makefile`.

### Module C: Root Helper Executor
- **Mechanism**: Implement a Root Helper binary running via `posix_spawn` / `NSTask`.
- **Command**: Trigger `export THEOS=... && make package`.
- **Log Pipe**: Real-time stdout/stderr redirection to a SwiftUI ScrollView log console.

## 3. GitHub Action Integration (Cloud Build Fallback)
- **Feature**: Add a "Push to GitHub & Build" button.
- **Logic**: Automatically generate a `.github/workflows/build.yml` in the project directory, commit the local changes via a mini-git wrapper, and push to the user's repo to trigger remote compilation.