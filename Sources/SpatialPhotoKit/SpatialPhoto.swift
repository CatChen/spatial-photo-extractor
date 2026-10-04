//
//  SpatialPhoto.swift
//  SpatialPhotoKit
//
//  Created by Cat Chen on 12/5/24.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One of the images stored inside a spatial photo.
public enum SpatialPhotoComponent: String, CaseIterable, Sendable {
    /// The image shown outside of Vision Pro.
    case primary
    /// The image for the left eye.
    case left
    /// The image for the right eye.
    case right
}

public enum SpatialPhotoError: Error, Equatable {
    /// The data could not be read as an image.
    case unreadableImage
    /// The photo has no stereo pair (e.g. a spatial photo converted from a 2D photo).
    case noStereoPair
    /// The image at the given index could not be decoded.
    case imageDecodingFailed(index: Int)
    /// An image destination could not be created at the given URL.
    case destinationCreationFailed(URL)
    /// Writing the image to the given URL failed.
    case writeFailed(URL)
}

/// A photo that may contain a stereo pair, read from a HEIC file.
///
/// Spatial photos store the left and right images in a stereo pair group
/// (`kCGImagePropertyGroupTypeStereoPair`). The group tells which image index
/// belongs to which eye, so the order of images inside the file doesn't matter.
public struct SpatialPhoto {
    private let source: CGImageSource

    /// The index of the primary image inside the file.
    public let primaryIndex: Int

    /// The indexes of the left and right images, or `nil` if the photo has no stereo pair.
    public let stereoPairIndexes: (left: Int, right: Int)?

    /// The number of images inside the file.
    public var imageCount: Int {
        CGImageSourceGetCount(source)
    }

    /// Whether the photo contains a stereo pair.
    public var hasStereoPair: Bool {
        stereoPairIndexes != nil
    }

    /// The components available in this photo, in extraction order.
    public var availableComponents: [SpatialPhotoComponent] {
        hasStereoPair ? [.primary, .left, .right] : [.primary]
    }

    public init(source: CGImageSource) throws {
        guard CGImageSourceGetCount(source) > 0 else {
            throw SpatialPhotoError.unreadableImage
        }
        self.source = source
        self.primaryIndex = CGImageSourceGetPrimaryImageIndex(source)
        self.stereoPairIndexes = Self.findStereoPairIndexes(in: source)
    }

    public init(data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw SpatialPhotoError.unreadableImage
        }
        try self.init(source: source)
    }

    public init(contentsOf url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw SpatialPhotoError.unreadableImage
        }
        try self.init(source: source)
    }

    /// The container-level properties of the file.
    public var properties: [CFString: Any] {
        CGImageSourceCopyProperties(source, nil) as? [CFString: Any] ?? [:]
    }

    /// The index of the given component inside the file.
    public func index(of component: SpatialPhotoComponent) throws -> Int {
        switch component {
        case .primary:
            return primaryIndex
        case .left:
            guard let stereoPairIndexes else { throw SpatialPhotoError.noStereoPair }
            return stereoPairIndexes.left
        case .right:
            guard let stereoPairIndexes else { throw SpatialPhotoError.noStereoPair }
            return stereoPairIndexes.right
        }
    }

    /// Decodes the image for the given component.
    public func image(_ component: SpatialPhotoComponent) throws -> CGImage {
        let index = try index(of: component)
        guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
            throw SpatialPhotoError.imageDecodingFailed(index: index)
        }
        return image
    }

    /// The image properties (EXIF, orientation, etc.) for the given component.
    public func properties(_ component: SpatialPhotoComponent) throws -> [CFString: Any] {
        let index = try index(of: component)
        return CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
    }

    /// Writes the given component to `url` as a single image, keeping its properties.
    public func write(_ component: SpatialPhotoComponent, to url: URL, as type: UTType = .jpeg) throws {
        let image = try image(component)
        let properties = try properties(component)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw SpatialPhotoError.destinationCreationFailed(url)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw SpatialPhotoError.writeFailed(url)
        }
    }

    /// The output URL for a component, e.g. `IMG_0001_left.jpg` next to `IMG_0001.HEIC`.
    public static func outputURL(
        for component: SpatialPhotoComponent,
        in directory: URL,
        baseName: String,
        as type: UTType = .jpeg
    ) -> URL {
        let url = directory.appendingPathComponent("\(baseName)_\(component.rawValue)")
        // UTType prefers "jpeg", but the CLI has always written "jpg".
        guard let pathExtension = type == .jpeg ? "jpg" : type.preferredFilenameExtension else {
            return url
        }
        return url.appendingPathExtension(pathExtension)
    }

    private static func findStereoPairIndexes(in source: CGImageSource) -> (left: Int, right: Int)? {
        guard let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let groups = properties[kCGImagePropertyGroups] as? [[CFString: Any]] else {
            return nil
        }
        for group in groups {
            guard let groupType = group[kCGImagePropertyGroupType] as? String,
                  groupType == kCGImagePropertyGroupTypeStereoPair as String,
                  let left = group[kCGImagePropertyGroupImageIndexLeft] as? Int,
                  let right = group[kCGImagePropertyGroupImageIndexRight] as? Int else {
                continue
            }
            return (left, right)
        }
        return nil
    }
}
