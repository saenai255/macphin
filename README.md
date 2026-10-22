# Macphin

A native macOS file manager in Swift/SwiftUI, modeled on KDE's [Dolphin](https://github.com/KDE/dolphin).

## Features

- **Tabs**, each with its own optional **split view** (two panes side by side, F3)
- **Places panel** (F9): editable bookmarks (drag to reorder, "Add to Places", reset) plus mounted devices with eject
- **Breadcrumb location bar** with a subfolder menu on every segment; click empty space or press ⌘L to type a path (`~` supported)
- **View modes**: Icons (Quick Look thumbnails), Compact (column flow), Details (sortable table with optional Created, Permissions, Owner and Location columns; right-click the header) — ⌘1/⌘2/⌘3
- Icons and Compact use a native collection view: drag-a-box selection, multi-file drag, keyboard navigation, and type-to-select (start typing a name) in every view; folders with tens of thousands of files stay responsive
- **Git status badges** on files and folders inside repositories (modified, added, untracked, conflicted, ignored)
- **Zoom** slider in the status bar, plus ⌘+ / ⌘− / ⌘0
- **Information panel** (F11): preview, type, size (folder sizes computed recursively), dates, permissions, owner, image dimensions
- **Terminal panel** (F4): embedded shell (SwiftTerm) that follows the active folder
- **Filter bar** (⌥⌘F) and Spotlight-backed **search** scoped to the current folder (toolbar search field)
- File operations: cut/copy/paste, duplicate, inline rename (F2), new folder/file, move to trash, permanent delete, compress to zip, "Open With", copy/move to the other split pane
- **Undo/redo** (⌘Z / ⌘⇧Z) for move, copy, rename, trash, new folder/file, duplicate and compress. Permanent delete cannot be undone
- **Conflict dialog** when a copy or move hits existing names: Replace (old item goes to the Trash), Skip or Keep Both, with size and date comparison
- **Remote locations** (⌘K, the Network section in Places, or type a URL in the location bar): smb, afp, nfs, ftp and webdav(s) mount through macOS NetFS; sftp mounts through sshfs if macFUSE and sshfs are installed. Mounted servers appear under Devices with an eject button
- **Session restore**: windows, tabs, split panes and view modes come back on relaunch (toggle in Settings, ⌘,)
- **Progress panel** for copy, move, trash and delete with size, time left and a cancel button; copies clone instantly on APFS
- **Tabs** can be reordered by dragging, dragged onto another window's tab bar, or moved to a new window from the tab's context menu
- **Share** and your **Quick Actions** (Automator services) in the file context menu; free-space bars on drives in Places
- Drag and drop onto folders, breadcrumb segments, tabs, places, and Trash (⌥ forces copy; cross-volume drops copy)
- Quick Look with Space, show hidden files (⌘⇧.), folders-first sorting, live directory watching

## Build and run

Requires macOS 15+ and a Swift 6 toolchain (Command Line Tools are enough).

```sh
./build-app.sh          # builds build/Macphin.app (release)
open build/Macphin.app
./test.sh               # runs the test suite
```

`swift run` also works for quick iteration.

The first `./build-app.sh` creates a self-signed "Macphin Local Signing" certificate in its own keychain (`~/Library/Keychains/macphin-signing.keychain-db`) and signs every build with it, so macOS keeps Macphin's privacy permissions (Full Disk Access, Desktop, Documents) across rebuilds. Set `MACPHIN_SIGN_IDENTITY` to use a real Developer ID instead. To regenerate the icon, run `swift scripts/make-icon.swift`.

For UI checks without screen-recording permission, `MACPHIN_SNAPSHOT_DIR=/some/dir build/Macphin.app/Contents/MacOS/Macphin` renders a scripted tour of the UI to PNG files (optionally start in a folder with `MACPHIN_SNAPSHOT_START`). It uses separate preferences and does not change your settings.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New / close tab | ⌘T / ⌘W |
| Next / previous tab | ⌘⇧] / ⌘⇧[ |
| Split view / switch pane | F3 / ⌃⇧Tab |
| Places / terminal / information | F9 / F4 / F11 |
| Back / forward / up | ⌘[ / ⌘] / ⌘↑ |
| Open selection | Return or ⌘↓ |
| Edit location | ⌘L |
| Filter | ⌥⌘F |
| Rename | F2 |
| New folder / new text file | ⌘⇧N / ⌥⌘N |
| Move to trash / delete permanently | ⌘⌫ / ⌥⌘⌫ |
| Copy location | ⌥⌘C |
| Invert selection | ⌘⇧A |
| Show hidden files | ⌘⇧. |
| Reload | ⌘R |
| Undo / redo file operation | ⌘Z / ⌘⇧Z |
| Connect to server | ⌘K |

## Limitations

- Passwords typed in Connect to Server are not saved. smb/afp logins can be saved in the Keychain through the system login prompt.
- The undo history covers the current app run only, up to 100 steps.
- The tests move small temporary files to your Trash to exercise trash/undo.
