# iQuit

A fresh start without a restart. An [R6.ai](https://r6.ai) product.

iQuit sits in the menu bar and lets you quit one, some, or all running apps from one tidy spot. Hold Option to force quit. Unused apps can quit themselves after a timeout you choose.

## Build

```bash
chmod +x Scripts/build-app.sh Scripts/swiftc-manifest-fix
Scripts/build-app.sh
open dist/iQuit.app
```

Requires macOS 14+ and Swift 6.

## Use

- Click the menu bar icon to see running apps, with optional CPU and memory.
- Quit one app, selected apps, or everything iQuit is allowed to close. Apps can save first.
- Hold **Option** to turn every Quit control into Force Quit.
- Use the ⋯ menu on a row for **Never Quit**. Toggle background apps from the footer.
- Preferences live under **Preferences…** (`⌘,` from the right-click menu): launch at login, auto-quit, shortcuts, and appearance.

## Automation

```bash
dist/iQuit.app/Contents/MacOS/iQuit --quit-all
dist/iQuit.app/Contents/MacOS/iQuit --force-quit-all
dist/iQuit.app/Contents/MacOS/iQuit --quit TextEdit
dist/iQuit.app/Contents/MacOS/iQuit --list
dist/iQuit.app/Contents/MacOS/iQuit --status
```

URL scheme:

```
iquit://quit-all
iquit://force-quit-all
iquit://quit?name=TextEdit
iquit://list
```

Shortcuts: **Quit All Apps**, **Force Quit All Apps**, **iQuit Status**.

## Limits

iQuit will not quit Finder, Dock, or other protected system processes. Some background apps relaunch themselves after quitting. Force quit skips save prompts.
