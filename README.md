# semibold-ios

![version](https://img.shields.io/badge/version-v0.1.0-blue)

## Requirements

- Xcode 16+
- Swift 5.10+
- iOS 17+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting Started

1. Clone this repo alongside its sibling `semibold-docs` repo, under a
   common parent directory (e.g. `semi-bold/semibold-ios` and
   `semi-bold/semibold-docs`) — `CLAUDE.md` and `.claude/` workflows
   reference it via `../semibold-docs`
2. Run `xcodegen generate` to create `semibold.xcodeproj`
3. Open `semibold.xcodeproj` in Xcode
4. SPM dependencies resolve automatically on first build

The `.xcodeproj` is generated from `project.yml` and is not committed to
git — re-run `xcodegen generate` after pulling changes to `project.yml`.

## Running in Simulator

1. Select a scheme (`semibold`) and an iPhone simulator in Xcode
2. Press `⌘R` to build and run

To run the test suite from the terminal:

```bash
xcodebuild test \
  -scheme semibold \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Dependencies

- Core Data (`NSPersistentContainer`/`NSPersistentCloudKitContainer`) — local
  persistence, part of the iOS SDK, no SPM package required
- [SwiftLint](https://github.com/realm/SwiftLint) — enforced via SPM build plugin
