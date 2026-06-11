# semibold-ios

## Requirements

- Xcode 16+
- Swift 5.10+
- iOS 17+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting Started

1. Clone the repo
2. Run `xcodegen generate` to create `semibold.xcodeproj`
3. Open `semibold.xcodeproj` in Xcode
4. SPM dependencies resolve automatically on first build

The `.xcodeproj` is generated from `project.yml` and is not committed to
git — re-run `xcodegen generate` after pulling changes to `project.yml`.

## Dependencies

- [GRDB.swift](https://github.com/groue/GRDB.swift) — local SQLite
- [SwiftLint](https://github.com/realm/SwiftLint) — enforced via SPM build plugin
