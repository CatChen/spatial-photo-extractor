//
//  main.swift
//  spatial-photo-extractor
//
//  Created by Cat Chen on 12/5/24.
//

import Foundation
import UniformTypeIdentifiers
import PhotosUI
import ArgumentParser

@main
struct ExtractSpatialPhoto: AsyncParsableCommand {
    @Flag(name: .shortAndLong, help: "All spatial photos in the Photos Library.")
    var photosLibrary: Bool = false
    
    @Option(name: .shortAndLong, help: "The files to extract.")
    var files: [String] = []
    
    mutating func validate() throws {
        if photosLibrary && !files.isEmpty {
            throw ValidationError("Cannot specify both --photos-library and --files")
        } else if !photosLibrary && files.isEmpty {
            throw ValidationError("Must specify either --photos-library or --files")
        }
    }
    
    mutating func run() async throws {
        if photosLibrary {
            try await usePhotosLibrary()
        } else {
            try await useFiles(files)
        }
    }
}

func usePhotosLibrary() async throws {
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    
    switch status {
    case .authorized:
        // Full access granted
        print("Full access granted")
        break;
    case .limited:
        // Limited access granted (iOS 14+)
        print("Limited access granted")
        throw ExitCode.failure
    case .restricted:
        // Access restricted (e.g., parental controls)
        print("Access restricted")
        throw ExitCode.failure
    case .denied:
        // Access denied
        print("Access denied")
        throw ExitCode.failure
    case .notDetermined:
        // Status not determined yet
        print("Access not determined")
        throw ExitCode.failure
    @unknown default:
        break
    }
    
    let fetchOptions = PHFetchOptions()
    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    fetchOptions.predicate = NSPredicate(format: "mediaSubtype == %d", PHAssetMediaSubtype.spatialMedia.rawValue)
    
    let spatialPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
    print("Found \(spatialPhotos.count) spatial photos")
    spatialPhotos.enumerateObjects { (asset, _, _) in
        // Process each spatial photo asset
        print(asset.localIdentifier)
        
        let resources = PHAssetResource.assetResources(for: asset)
        let filename = resources.first!.originalFilename
        print(filename)
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.version = .original
        options.isSynchronous = true
        
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (data, uti, _, info) in
            print(String(format: "Received image data of %d bytes", data!.count))
            print(CFCopyDescription(info as CFTypeRef)!)
            let source = CGImageSourceCreateWithData(data! as CFData, nil)
            print("Source created")
            extractImages(from: source!, to: URL.picturesDirectory.appendingPathComponent(filename))
        }
    }
}

func useFiles(_ files: [String]) async throws {
    for file in files {
        if FileManager.default.fileExists(atPath: file) {
            if FileManager.default.isReadableFile(atPath: file) {
                print(file)
                let filename = URL(filePath: file)
                let source = CGImageSourceCreateWithURL(filename as CFURL, nil)
                print("Source created")
                extractImages(from: source!, to: filename)
            } else {
                print("File not readable: \(file)")
            }
        } else {
            print("File not found: \(file)")
        }
    }
}
    
func extractImages(from source: CGImageSource!, to filename: URL!) {
    guard let properties = CGImageSourceCopyProperties(source!, nil) as? [CFString: Any] else {
        return
    }
    print("Properties copied")
    print(CFCopyDescription(properties as CFTypeRef)!)
    
    let imageCount = CGImageSourceGetCount(source!)
    print(String(format: "%d images found", imageCount))
    
    let primaryIndex = CGImageSourceGetPrimaryImageIndex(source!)
    if let primaryImage = CGImageSourceCreateImageAtIndex(source!, primaryIndex, nil),
       let primaryProperties = CGImageSourceCopyPropertiesAtIndex(source!, primaryIndex, nil) {
        print("Primary image found at index \(primaryIndex)")
        print(CFCopyDescription(primaryProperties as CFTypeRef)!)
        saveImage(from: primaryImage, to: filename, name: "primary", properties: primaryProperties)
    }

    if let groups = properties[kCGImagePropertyGroups] as? [[CFString: Any]] {
        let stereoGroup = groups.first(where: {
            let groupType = $0[kCGImagePropertyGroupType] as! CFString
            return groupType == kCGImagePropertyGroupTypeStereoPair
        })
        if stereoGroup == nil {
            print("No stereo pair found")
            return
        }
            
        if let stereoGroup,
           let leftIndex = stereoGroup[kCGImagePropertyGroupImageIndexLeft] as? Int,
           let rightIndex = stereoGroup[ kCGImagePropertyGroupImageIndexRight] as? Int,
           let leftImage = CGImageSourceCreateImageAtIndex(source!, leftIndex, nil),
           let rightImage = CGImageSourceCreateImageAtIndex(source!, rightIndex, nil),
           let leftProperties = CGImageSourceCopyPropertiesAtIndex(source!, leftIndex, nil),
           let rightProperties = CGImageSourceCopyPropertiesAtIndex(source!, rightIndex, nil) {
            print("Stereo pair found at indexes \(leftIndex) and \(rightIndex)")
            print(CFCopyDescription(leftProperties as CFTypeRef)!)
            print(CFCopyDescription(rightProperties as CFTypeRef)!)
            saveImage(from: leftImage, to: filename, name: "left", properties: leftProperties)
            saveImage(from: rightImage, to: filename, name: "right", properties: rightProperties)
        }
    }
}

func saveImage(from image: CGImage, to filename: URL!, name: String!, properties: CFDictionary?) {
    let imageFilename = filename.deletingLastPathComponent().appendingPathComponent("\(filename.deletingPathExtension().lastPathComponent)_\(name!)").appendingPathExtension("jpg")
    let imageFile = CGImageDestinationCreateWithURL(imageFilename as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    CGImageDestinationAddImage(imageFile!, image, properties)
    if CGImageDestinationFinalize(imageFile!) {
        print("\(name!) image saved to \(imageFilename) as String)")
    } else {
        print("Failed to save \(name!) image")
    }
}
