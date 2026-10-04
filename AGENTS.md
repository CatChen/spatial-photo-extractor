# AGENTS.md

Spatial Photo Extractor extracts the left-eye and right-eye images (and the primary image) from Apple spatial photos (HEIC files taken with an iPhone 15 Pro or later or with Apple Vision Pro).

## Layout

Pure Swift Package Manager. There's no `.xcodeproj`; to use Xcode, open `Package.swift` (or run `xed .`).

- `Sources/SpatialPhotoKit/`: the library. It runs on macOS, iOS and visionOS, and has to stay free of CLI and macOS-only code because a separate (private) app depends on it by URL.
- `Sources/SpatialPhotoExtractorCLI/`: the `spatial-photo-extractor` command-line tool (macOS only). It uses swift-argument-parser and PhotoKit.
- `Tests/SpatialPhotoKitTests/`: Swift Testing tests. Fixtures are built in memory by `Fixture`, so the repo doesn't carry any personal photos.

## Commands

```bash
swift build
swift test
swift run spatial-photo-extractor --files path/to/IMG_0001.HEIC
swift build -c release --arch arm64 --arch x86_64 --product spatial-photo-extractor
```

## How extraction works

- Never rely on the order of images inside the HEIC; it varies.
- Read `kCGImagePropertyGroups` from the container properties and find the group whose `kCGImagePropertyGroupType` is `kCGImagePropertyGroupTypeStereoPair`. Its `kCGImagePropertyGroupImageIndexLeft` and `kCGImagePropertyGroupImageIndexRight` give the image index for each eye.
- The primary image comes from `CGImageSourceGetPrimaryImageIndex`.
- Spatial photos converted from 2D photos have no stereo pair group, so only the primary image is extracted.

## Conventions

- Swift 6 language mode. Don't use force unwraps in library code; throw `SpatialPhotoError` instead.
- The output file names are user-facing and documented in `README.md`: `<name>_primary.jpg`, `<name>_left.jpg`, `<name>_right.jpg`. Keep them stable.
- `SpatialPhotoKit` is public API with semver tags (`vX.Y.Z`). Breaking changes need a major version bump.
- Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`, which publishes a DMG containing the CLI binary.
