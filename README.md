# Spatial Photo Extractor

You took spatial photos with your iPhone 15/16 Pro (requires iOS 18.2 or above) and your Vision Pro. You want to extract the pair of the stereo photos (the different photos your left eye and right eye see inside Vision Pro) for your own photo processing. Apple doesn't provide a tool to do that. This is the command-line tool for that purpose.

## Usage

Download the `spatial-photo-extractor.dmg` from the [latest release](https://github.com/CatChen/spatial-photo-extractor/releases). Copy the command-line tool file to a directory you plan to use it (e.g. `~/Downloads`). Run the command with `--photos-library` to extract all spatial photos from the Photos app. Run it with `--files file1 (--files file2 ...)` to extract from unmodified spatial photos (named `IMG_*.HEIC` by default) exported from Photos.

### Extract from Photos

Run the command-line tool from the Terminal on macOS:

```zsh
cd ~/Downloads
./spatial-photo-extractor --photos-library
```

If it asks for permissions to access your photos library, approve it or it won't work. The results will be saved to `~/Pictures`. Every spatial photo will create 3 images:

- `IMG_*_left.jpg`: The image for your left eye viewing inside Vision Pro.
- `IMG_*_right.jpg`: The image for your right eye viewing inside Vision Pro.
- `IMG_*_primary.jpg`: The image you see outside of Vision Pro, which is generated by Apple's algorithm with data from the two images from above.

### Extract from Files

You will be responsible for exporting unmodified spatial photos from the Photos app. In the Photos app, choose `File` -> `Export` -> `Export Unmodified Original` from the menu. It will export an `IMG_*.HEIC` file for each photo you select.

The `File` -> `Export` -> `Export` won't work. Drag-and-drop a photo from the Photos app to a directory won't work either. They won't preserve the multiple images inside a single `HEIC` file. They will export the primary image as a single `JPEG` file.

Run the command-line tool from the Terminal on macOS with the files you just exported:

```zsh
cd ~/Downloads
./spatial-photo-extractor \
  --files ~/Pictures/IMG_0001.HEIC \
  --files ~/Pictures/IMG_0002.HEIC \
  --files ~/Pictures/IMG_0003.HEIC
```

It will generate the same 3 `JPEG` images (left, right and primary as described from above) for each `HEIC` file. They will be saved to the same directory as the `HEIC` file.

## FAQ

### Some spatial photos don't export a pair of stereo photos

[Spatial photos created from 2D photos](https://support.apple.com/en-mn/guide/apple-vision-pro/tan1be9a3a0b/visionos) don't have a pair of stereo photos. They were captured as a single photo. Even though they can be viewed like spatial photo in Vision Pro and they show up in the Spatial media type, they contains no stereo photos.

### Can this tool create a spatial photo by combining two stereo photos I have?

Not at the moment. It's not very hard to implement the same process in reverse.

### Does this tool support spatial video extraction?

No. Maybe in the future.

### Can I do the same thing with [ImageMagick](https://github.com/ImageMagick/ImageMagick)?

You will be able to extract all the photos from a single `HEIC` file with the latest version of ImageMagick. However, you won't be able to tell which one is for the left eye and which one is for the right eye. Given a spatial photo `IMG_*.HEIC`, ImageMagick will extract `IMG_*-0.jpg`, `IMG_*-1.jpg` and `IMG_*-2.jpg` from it. Most of the time `[0, 1, 2]` represents `[primary, right, left]` but sometimes it's `[primary, left, right]` instead. Apple doesn't guarantee the order of these images inside an `HEIC` file.
