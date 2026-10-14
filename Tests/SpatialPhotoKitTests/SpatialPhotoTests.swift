//
//  SpatialPhotoTests.swift
//  SpatialPhotoKitTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SpatialPhotoKit

/// Builds HEIC fixtures in memory so the repo doesn't need to carry personal photos.
enum Fixture {
    /// A solid-color image whose red channel identifies it after a round trip.
    static func image(red: UInt8) -> CGImage {
        let width = 16
        let height = 16
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(red: CGFloat(red) / 255, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// A HEIC with a stereo pair group. The right image is stored first to prove
    /// the reader uses the group metadata rather than the image order.
    static func stereoHEIC(leftRed: UInt8 = 200, rightRed: UInt8 = 50) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 2, nil)!
        let images: [(CGImage, CFString)] = [
            (image(red: rightRed), kCGImagePropertyGroupImageIsRightImage),
            (image(red: leftRed), kCGImagePropertyGroupImageIsLeftImage),
        ]
        for (image, eyeKey) in images {
            let properties: [CFString: Any] = [
                kCGImagePropertyGroups: [
                    kCGImagePropertyGroupIndex: 0,
                    kCGImagePropertyGroupType: kCGImagePropertyGroupTypeStereoPair,
                    eyeKey: true,
                ],
            ]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// GPS for the primary image, like an iPhone spatial photo (the eyes carry none).
    static func gps(latitude: Double = 37.589) -> [CFString: Any] {
        [
            kCGImagePropertyGPSLatitude: latitude, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 122.512, kCGImagePropertyGPSLongitudeRef: "W",
        ]
    }

    /// A spatial-photo layout: a primary image with GPS first, then a stereo pair without GPS.
    /// `eyeGPS` gives the left eye its own GPS, to prove it is never overwritten.
    static func stereoHEICWithPrimaryGPS(eyeGPS: [CFString: Any]? = nil) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 3, nil)!
        CGImageDestinationAddImage(
            destination, image(red: 120), [kCGImagePropertyGPSDictionary: gps()] as CFDictionary)
        let eyes: [(CGImage, CFString)] = [
            (image(red: 50), kCGImagePropertyGroupImageIsRightImage),
            (image(red: 200), kCGImagePropertyGroupImageIsLeftImage),
        ]
        for (image, eyeKey) in eyes {
            var properties: [CFString: Any] = [
                kCGImagePropertyGroups: [
                    kCGImagePropertyGroupIndex: 0,
                    kCGImagePropertyGroupType: kCGImagePropertyGroupTypeStereoPair,
                    eyeKey: true,
                ],
            ]
            if eyeKey == kCGImagePropertyGroupImageIsLeftImage, let eyeGPS {
                properties[kCGImagePropertyGPSDictionary] = eyeGPS
            }
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// A regular single-image HEIC.
    static func flatHEIC() -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image(red: 120), nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

/// The red value of the center pixel, decoded into a known 8-bit RGBA layout.
/// The latitude written to `url`, or nil when the file has no GPS.
func latitude(at url: URL) -> Double? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
    else { return nil }
    return gps[kCGImagePropertyGPSLatitude] as? Double
}

func centerRed(of image: CGImage) -> UInt8 {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
        data: &pixel,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return pixel[0]
}

@Suite struct SpatialPhotoTests {
    @Test func findsStereoPairFromGroupMetadata() throws {
        let photo = try SpatialPhoto(data: Fixture.stereoHEIC())

        #expect(photo.imageCount == 2)
        #expect(photo.hasStereoPair)
        #expect(photo.stereoPairIndexes?.left == 1)
        #expect(photo.stereoPairIndexes?.right == 0)
        #expect(photo.availableComponents == [.primary, .left, .right])
    }

    @Test func decodesEachEye() throws {
        let photo = try SpatialPhoto(data: Fixture.stereoHEIC(leftRed: 200, rightRed: 50))

        // HEIC is lossy, so allow some tolerance.
        #expect(abs(Int(centerRed(of: try photo.image(.left))) - 200) < 10)
        #expect(abs(Int(centerRed(of: try photo.image(.right))) - 50) < 10)
    }

    @Test func flatPhotoHasOnlyPrimary() throws {
        let photo = try SpatialPhoto(data: Fixture.flatHEIC())

        #expect(!photo.hasStereoPair)
        #expect(photo.availableComponents == [.primary])
        _ = try photo.image(.primary)
        #expect(throws: SpatialPhotoError.noStereoPair) {
            try photo.image(.left)
        }
    }

    @Test func rejectsNonImageData() {
        #expect(throws: SpatialPhotoError.unreadableImage) {
            try SpatialPhoto(data: Data("not an image".utf8))
        }
    }

    @Test func outputURLMatchesCLINaming() {
        let directory = URL(filePath: "/tmp/photos", directoryHint: .isDirectory)

        #expect(SpatialPhoto.outputURL(for: .left, in: directory, baseName: "IMG_0001").path == "/tmp/photos/IMG_0001_left.jpg")
        #expect(SpatialPhoto.outputURL(for: .right, in: directory, baseName: "IMG_0001", as: .heic).path == "/tmp/photos/IMG_0001_right.heic")
    }

    @Test func writesComponentsToDisk() throws {
        let photo = try SpatialPhoto(data: Fixture.stereoHEIC())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for component in photo.availableComponents {
            let url = SpatialPhoto.outputURL(for: component, in: directory, baseName: "IMG_0001")
            try photo.write(component, to: url)
            let written = try SpatialPhoto(contentsOf: url)
            #expect(written.imageCount == 1)
            #expect(!written.hasStereoPair)
        }
    }

    @Test(arguments: [UTType.jpeg, .heic, .png])
    func eyesHaveNoLocationByDefault(type: UTType) throws {
        let photo = try SpatialPhoto(data: Fixture.stereoHEICWithPrimaryGPS())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for component in [SpatialPhotoComponent.left, .right] {
            let url = SpatialPhoto.outputURL(for: component, in: directory, baseName: "IMG_0001", as: type)
            try photo.write(component, to: url, as: type)
            #expect(latitude(at: url) == nil)
        }
    }

    @Test(arguments: [UTType.jpeg, .heic, .png])
    func includeLocationCopiesPrimaryGPSToEyes(type: UTType) throws {
        let photo = try SpatialPhoto(data: Fixture.stereoHEICWithPrimaryGPS())
        #expect(photo.primaryLocation != nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for component in [SpatialPhotoComponent.left, .right] {
            let url = SpatialPhoto.outputURL(for: component, in: directory, baseName: "IMG_0001", as: type)
            try photo.write(component, to: url, as: type, includeLocation: true)
            let written = try #require(latitude(at: url))
            #expect(abs(written - 37.589) < 0.0001)
        }
    }

    @Test func includeLocationNeverOverwritesEyeGPS() throws {
        let photo = try SpatialPhoto(data: Fixture.stereoHEICWithPrimaryGPS(eyeGPS: Fixture.gps(latitude: 10.5)))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = SpatialPhoto.outputURL(for: .left, in: directory, baseName: "IMG_0001")
        try photo.write(.left, to: url, includeLocation: true)
        let written = try #require(latitude(at: url))
        #expect(abs(written - 10.5) < 0.0001)
    }

    @Test func includeLocationWithoutPrimaryGPSWritesNone() throws {
        let photo = try SpatialPhoto(data: Fixture.stereoHEIC())
        #expect(photo.primaryLocation == nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = SpatialPhoto.outputURL(for: .left, in: directory, baseName: "IMG_0001")
        try photo.write(.left, to: url, includeLocation: true)
        #expect(latitude(at: url) == nil)
    }
}
