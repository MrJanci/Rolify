# Rolify iOS

Native iOS App in Swift/SwiftUI, deployt ueber SideStore.

## Structure

```
apps/ios/
├── project.yml             # XcodeGen-Config → generiert Rolify.xcodeproj
├── Rolify/
│   ├── RolifyApp.swift     # @main entry
│   ├── ContentView.swift   # Root view (placeholder)
│   ├── Info.plist
│   └── Assets.xcassets/    # AppIcon + AccentColor
└── README.md               # diese Datei
```

Das `.xcodeproj` wird **nicht** committed — XcodeGen generiert es on-the-fly aus `project.yml`. Weniger Merge-Konflikte, sauberer Repo.

## Build lokal (auf einem Mac)

```bash
brew install xcodegen
cd apps/ios
xcodegen generate
open Rolify.xcodeproj
```

## Build via GitHub Actions

Push Tag → macOS-Runner baut unsigned `.ipa`:

```bash
git tag v0.0.1-alpha
git push origin v0.0.1-alpha
```

Artifact landet unter Actions → letzter Run → Artifacts → `Rolify-unsigned-ipa`.

## Install aufs iPhone

Siehe Obsidian-Note `01-Projekte/Rolify/Deployment/SideStore-Setup.md` — StosVPN + SideStore + Free Apple-Dev-Cert.
