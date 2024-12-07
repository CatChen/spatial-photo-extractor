//
//  main.swift
//  spatial-photo-extractor
//
//  Created by Cat Chen on 12/5/24.
//

import Foundation
import UniformTypeIdentifiers
import PhotosUI

let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)

switch status {
case .authorized:
    // Full access granted
    print("Full access granted")
    break;
case .limited:
    // Limited access granted (iOS 14+)
    print("Limited access granted")
    exit(1)
case .restricted:
    // Access restricted (e.g., parental controls)
    print("Access restricted")
    exit(1)
case .denied:
    // Access denied
    print("Access denied")
    exit(1)
case .notDetermined:
    // Status not determined yet
    print("Access not determined")
    exit(1)
@unknown default:
    break
}

let fetchOptions = PHFetchOptions()
//fetchOptions.fetchLimit = 1
fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
fetchOptions.predicate = NSPredicate(format: "mediaSubtype == %d", PHAssetMediaSubtype.spatialMedia.rawValue)

let spatialPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
print(String(format:"Found %d spatial photos", spatialPhotos.count))
spatialPhotos.enumerateObjects { (asset, _, _) in
    // Process each spatial photo asset
    print(asset.localIdentifier)

    let resources = PHAssetResource.assetResources(for: asset)
    let filename = resources.first!.originalFilename as NSString
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

        guard let properties = CGImageSourceCopyProperties(source!, nil) as? [CFString: Any] else {
            return
        }
        print("Properties copied")
        print(CFCopyDescription(properties as CFTypeRef)!)
        
        let imageCount = CGImageSourceGetCount(source!)
        print(String(format: "%d images found", imageCount))
        
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
                print("Stereo pair found")
                print(CFCopyDescription(leftProperties as CFTypeRef)!)
                print(CFCopyDescription(rightProperties as CFTypeRef)!)
                
                if let leftImageFilename = CFURLCreateWithFileSystemPathRelativeToBase(kCFAllocatorDefault, "./\(filename.deletingPathExtension)_left.jpg" as CFString, CFURLPathStyle.cfurlposixPathStyle, false, FileManager.default.homeDirectoryForCurrentUser as CFURL) {
                    let leftImageFile = CGImageDestinationCreateWithURL(leftImageFilename, UTType.jpeg.identifier as CFString, 1, nil)
                    CGImageDestinationAddImage(leftImageFile!, leftImage, CGImageSourceCopyPropertiesAtIndex(source!, leftIndex, nil))
                    if CGImageDestinationFinalize(leftImageFile!) {
                        print("Left image saved to \(CFURLGetString(leftImageFilename)! as String)")
                    } else {
                        print("Failed to save left image")
                    }

                } else {
                    print("Failed to create left image file")
                    return
                }
                
                if let rightImageFilename = CFURLCreateWithFileSystemPathRelativeToBase(kCFAllocatorDefault, "./\(filename.deletingPathExtension)_right.jpg" as CFString, CFURLPathStyle.cfurlposixPathStyle, false, FileManager.default.homeDirectoryForCurrentUser as CFURL) {
                    let rightImageFile = CGImageDestinationCreateWithURL(rightImageFilename, UTType.jpeg.identifier as CFString, 1, nil)
                    
                    CGImageDestinationAddImage(rightImageFile!, rightImage, CGImageSourceCopyPropertiesAtIndex(source!, rightIndex, nil))
                    if CGImageDestinationFinalize(rightImageFile!) {
                        print("Right image saved to \(CFURLGetString(rightImageFilename)! as String)")
                    } else {
                        print("Failed to save right image")
                    }
                } else {
                    print("Failed to create right image file")
                    return
                }
            }
        }
    }
}
