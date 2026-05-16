# Photorg

An iOS app for shooting photos directly into named collections (e.g. "White Teslas") so you never have to sort retroactively.

## Features

- Create and manage collections (name + optional note).
- Pick a collection, then tap the in-app camera button to shoot — every capture is filed automatically into the active collection.
- Import existing photos from the system Photo Library into a collection.
- Export photos to the Photos app / share sheet.

## Architecture

- **SwiftUI** for all UI.
- **SwiftData** for `Collection` and `Photo` models (iOS 17+).
- **AVFoundation** for the in-app camera (so we control orientation + EXIF and write straight to the collection's directory).
- Images are stored on disk under `Application Support/Photorg/originals/<photo-uuid>.heic`. The database row only holds the UUID.

```
╭─────────────╮      ╭─────────────╮      ╭────────────────╮
│ Collections │─────▶│  Collection │─────▶│ Camera / Photo │
│    List     │      │    Detail   │      │   Detail       │
╰─────────────╯      ╰─────────────╯      ╰────────────────╯
       │                    │                      │
       ▼                    ▼                      ▼
   SwiftData            SwiftData             File storage
   (collections)        (photo rows)          (HEIC originals)
```

## Build

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
2. From this directory: `xcodegen generate`
3. Open `Photorg.xcodeproj` in Xcode 15+ and run on an iOS 17+ device (camera needs a real device).


