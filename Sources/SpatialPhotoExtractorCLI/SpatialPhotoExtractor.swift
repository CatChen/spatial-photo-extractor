//
//  SpatialPhotoExtractor.swift
//  spatial-photo-extractor
//
//  Created by Cat Chen on 12/5/24.
//

import ArgumentParser
import Foundation
import Photos
import SpatialPhotoKit

@main
struct ExtractSpatialPhoto: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spatial-photo-extractor",
        abstract: "Extract the left and right eye images from spatial photos."
    )

    @Flag(name: .shortAndLong, help: "All spatial photos in the Photos Library.")
    var photosLibrary: Bool = false

    @Option(name: .shortAndLong, help: "The files to extract.")
    var files: [String] = []

    @Flag(name: .shortAndLong, help: "Print image properties for debugging.")
    var verbose: Bool = false

    mutating func validate() throws {
        if photosLibrary && !files.isEmpty {
            throw ValidationError("Cannot specify both --photos-library and --files")
        } else if !photosLibrary && files.isEmpty {
            throw ValidationError("Must specify either --photos-library or --files")
        }
    }

    mutating func run() async throws {
        if photosLibrary {
            try await usePhotosLibrary(verbose: verbose)
        } else {
            useFiles(files, verbose: verbose)
        }
    }
}

func usePhotosLibrary(verbose: Bool) async throws {
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)

    switch status {
    case .authorized:
        print("Full access granted")
    case .limited:
        print("Limited access granted")
        throw ExitCode.failure
    case .restricted:
        // Access restricted (e.g., parental controls)
        print("Access restricted")
        throw ExitCode.failure
    case .denied:
        print("Access denied")
        throw ExitCode.failure
    case .notDetermined:
        print("Access not determined")
        throw ExitCode.failure
    @unknown default:
        break
    }

    let fetchOptions = PHFetchOptions()
    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    fetchOptions.predicate = NSPredicate(format: "mediaSubtype == %d", PHAssetMediaSubtype.spatialMedia.rawValue)

    let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
    print("Found \(fetchResult.count) spatial photos")

    var assets: [PHAsset] = []
    fetchResult.enumerateObjects { asset, _, _ in
        assets.append(asset)
    }

    for asset in assets {
        print(asset.localIdentifier)
        guard let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename else {
            print("No original file found")
            continue
        }
        print(filename)

        do {
            let data = try await requestOriginalImageData(for: asset)
            print("Received image data of \(data.count) bytes")
            let output = URL.picturesDirectory.appendingPathComponent(filename)
            try extractImages(from: SpatialPhoto(data: data), to: output, verbose: verbose)
        } catch {
            print("Failed to extract \(filename): \(error)")
        }
    }
}

func requestOriginalImageData(for asset: PHAsset) async throws -> Data {
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .none
    options.version = .original

    return try await withCheckedThrowingContinuation { continuation in
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
            if let data {
                continuation.resume(returning: data)
            } else {
                let error = info?[PHImageErrorKey] as? Error ?? SpatialPhotoError.unreadableImage
                continuation.resume(throwing: error)
            }
        }
    }
}

func useFiles(_ files: [String], verbose: Bool) {
    for file in files {
        guard FileManager.default.fileExists(atPath: file) else {
            print("File not found: \(file)")
            continue
        }
        guard FileManager.default.isReadableFile(atPath: file) else {
            print("File not readable: \(file)")
            continue
        }
        print(file)

        let url = URL(filePath: file)
        do {
            try extractImages(from: SpatialPhoto(contentsOf: url), to: url, verbose: verbose)
        } catch {
            print("Failed to extract \(file): \(error)")
        }
    }
}

/// Saves `<name>_primary.jpg`, `<name>_left.jpg` and `<name>_right.jpg` next to `filename`.
func extractImages(from photo: SpatialPhoto, to filename: URL, verbose: Bool) throws {
    if verbose {
        print(photo.properties)
    }
    print("\(photo.imageCount) images found")

    print("Primary image found at index \(photo.primaryIndex)")
    if let stereoPairIndexes = photo.stereoPairIndexes {
        print("Stereo pair found at indexes \(stereoPairIndexes.left) and \(stereoPairIndexes.right)")
    } else {
        print("No stereo pair found")
    }

    let directory = filename.deletingLastPathComponent()
    let baseName = filename.deletingPathExtension().lastPathComponent
    for component in photo.availableComponents {
        if verbose {
            print(try photo.properties(component))
        }
        let output = SpatialPhoto.outputURL(for: component, in: directory, baseName: baseName)
        try photo.write(component, to: output)
        print("\(component.rawValue) image saved to \(output.path)")
    }
}
