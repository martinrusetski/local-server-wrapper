//
//  IconProcessor.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation
import AppKit

/// Utility for processing and converting icons for app bundles
class IconProcessor {
    
    // MARK: - Public Methods
    
    /// Process and copy an icon to the bundle's Resources directory
    /// - Parameters:
    ///   - customIconPath: Optional path to a custom icon file
    ///   - bundleURL: The URL of the bundle being created
    /// - Throws: GenerationError.resourceCopyFailed only if default icon generation also fails
    static func processIcon(customIconPath: String?, bundleURL: URL) throws {
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources")
        let iconURL = resourcesURL.appendingPathComponent("AppIcon.icns")
        
        if let customIconPath = customIconPath, !customIconPath.isEmpty {
            // Use custom icon
            let sourceURL = URL(fileURLWithPath: customIconPath)
            
            // Check if source file exists
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                // Fall back to default icon if custom icon doesn't exist
                print("⚠️ Custom icon not found at \(customIconPath), using default icon")
                do {
                    try copyDefaultIcon(to: iconURL)
                } catch {
                    print("⚠️ Failed to use default icon: \(error.localizedDescription)")
                    throw error
                }
                return
            }
            
            // Check if the file is already in .icns format
            if sourceURL.pathExtension.lowercased() == "icns" {
                // Copy directly
                do {
                    try copyIconFile(from: sourceURL, to: iconURL)
                } catch {
                    // Fall back to default icon if copy fails
                    print("⚠️ Failed to copy custom icon: \(error.localizedDescription), using default icon")
                    do {
                        try copyDefaultIcon(to: iconURL)
                    } catch {
                        print("⚠️ Failed to use default icon: \(error.localizedDescription)")
                        throw error
                    }
                }
            } else {
                // Convert to .icns format
                do {
                    try convertToIcns(from: sourceURL, to: iconURL)
                } catch {
                    // Fall back to default icon if conversion fails
                    print("⚠️ Failed to convert custom icon: \(error.localizedDescription), using default icon")
                    do {
                        try copyDefaultIcon(to: iconURL)
                    } catch {
                        print("⚠️ Failed to use default icon: \(error.localizedDescription)")
                        throw error
                    }
                }
            }
        } else {
            // Use default icon
            do {
                try copyDefaultIcon(to: iconURL)
            } catch {
                print("⚠️ Failed to use default icon: \(error.localizedDescription)")
                throw error
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Copy an icon file from source to destination
    /// - Parameters:
    ///   - sourceURL: The source icon file URL
    ///   - destinationURL: The destination URL for the icon
    /// - Throws: GenerationError.resourceCopyFailed if copying fails
    private static func copyIconFile(from sourceURL: URL, to destinationURL: URL) throws {
        do {
            // Remove existing icon if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Copy the icon file
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw GenerationError.resourceCopyFailed("Failed to copy icon file: \(error.localizedDescription)")
        }
    }
    
    /// Convert an image file to .icns format
    /// - Parameters:
    ///   - sourceURL: The source image file URL (png, jpg, etc.)
    ///   - destinationURL: The destination URL for the .icns file
    /// - Throws: GenerationError.resourceCopyFailed if conversion fails
    private static func convertToIcns(from sourceURL: URL, to destinationURL: URL) throws {
        // Load the source image
        guard let sourceImage = NSImage(contentsOf: sourceURL) else {
            throw GenerationError.resourceCopyFailed("Failed to load image from \(sourceURL.path)")
        }
        
        // Create an iconset with multiple resolutions
        // macOS .icns files contain multiple sizes: 16x16, 32x32, 128x128, 256x256, 512x512, 1024x1024
        // Each size also has a @2x retina variant
        
        // Create a temporary directory for the iconset
        let tempDir = FileManager.default.temporaryDirectory
        let iconsetURL = tempDir.appendingPathComponent("\(UUID().uuidString).iconset")
        
        do {
            try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
            
            // Generate all required icon sizes
            let sizes: [(size: Int, scale: Int, name: String)] = [
                (16, 1, "icon_16x16.png"),
                (16, 2, "icon_16x16@2x.png"),
                (32, 1, "icon_32x32.png"),
                (32, 2, "icon_32x32@2x.png"),
                (128, 1, "icon_128x128.png"),
                (128, 2, "icon_128x128@2x.png"),
                (256, 1, "icon_256x256.png"),
                (256, 2, "icon_256x256@2x.png"),
                (512, 1, "icon_512x512.png"),
                (512, 2, "icon_512x512@2x.png")
            ]
            
            for (size, scale, filename) in sizes {
                let actualSize = size * scale
                let resizedImage = resizeImage(sourceImage, to: NSSize(width: actualSize, height: actualSize))
                let imageURL = iconsetURL.appendingPathComponent(filename)
                
                guard let pngData = resizedImage.pngData() else {
                    throw GenerationError.resourceCopyFailed("Failed to generate PNG data for \(filename)")
                }
                
                try pngData.write(to: imageURL)
            }
            
            // Use iconutil to convert the iconset to .icns
            try convertIconsetToIcns(iconsetURL: iconsetURL, destinationURL: destinationURL)
            
            // Clean up temporary iconset directory
            try? FileManager.default.removeItem(at: iconsetURL)
            
        } catch let error as GenerationError {
            // Clean up on error
            try? FileManager.default.removeItem(at: iconsetURL)
            throw error
        } catch {
            // Clean up on error
            try? FileManager.default.removeItem(at: iconsetURL)
            throw GenerationError.resourceCopyFailed("Failed to create iconset: \(error.localizedDescription)")
        }
    }
    
    /// Resize an image to the specified size
    /// - Parameters:
    ///   - image: The source image to resize
    ///   - size: The target size
    /// - Returns: A resized NSImage
    private static func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()
        
        // Use high quality interpolation
        NSGraphicsContext.current?.imageInterpolation = .high
        
        // Draw the image scaled to the new size
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        
        resizedImage.unlockFocus()
        return resizedImage
    }
    
    /// Convert an iconset directory to .icns format using iconutil
    /// - Parameters:
    ///   - iconsetURL: The URL of the .iconset directory
    ///   - destinationURL: The destination URL for the .icns file
    /// - Throws: GenerationError.resourceCopyFailed if conversion fails
    private static func convertIconsetToIcns(iconsetURL: URL, destinationURL: URL) throws {
        // Remove existing .icns file if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        
        // Create the iconutil process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        
        // Set up arguments
        // -c icns: Convert to icns format
        // -o: Output file path
        process.arguments = [
            "-c", "icns",
            "-o", destinationURL.path,
            iconsetURL.path
        ]
        
        // Capture output for error reporting
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Run the iconutil process
        do {
            try process.run()
            process.waitUntilExit()
            
            // Check exit status
            if process.terminationStatus != 0 {
                // Read error output
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw GenerationError.resourceCopyFailed("iconutil failed with status \(process.terminationStatus): \(errorOutput)")
            }
            
        } catch let error as GenerationError {
            throw error
        } catch {
            throw GenerationError.resourceCopyFailed("Failed to execute iconutil: \(error.localizedDescription)")
        }
    }
    
    /// Copy the default icon to the destination
    /// - Parameter destinationURL: The destination URL for the icon
    /// - Throws: GenerationError.resourceCopyFailed if copying fails
    private static func copyDefaultIcon(to destinationURL: URL) throws {
        if let defaultIconURL = DefaultIcon.resourceURL {
            try copyIconFile(from: defaultIconURL, to: destinationURL)
        } else {
            try generateDefaultIcon(to: destinationURL)
        }
    }
    
    /// Generate a simple default icon programmatically
    /// - Parameter destinationURL: The destination URL for the icon
    /// - Throws: GenerationError.resourceCopyFailed if generation fails
    private static func generateDefaultIcon(to destinationURL: URL) throws {
        // Create a simple icon with a colored background and text
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // Draw a gradient background
        let gradient = NSGradient(colors: [
            NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),
            NSColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1.0)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        
        // Draw a rounded rectangle border
        let borderRect = NSRect(x: 40, y: 40, width: 432, height: 432)
        let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: 60, yRadius: 60)
        NSColor.white.withAlphaComponent(0.3).setStroke()
        borderPath.lineWidth = 8
        borderPath.stroke()
        
        // Draw text "S" for Server
        let text = "S"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 280, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        let textX = (size.width - textSize.width) / 2
        let textY = (size.height - textSize.height) / 2
        let textRect = NSRect(x: textX, y: textY, width: textSize.width, height: textSize.height)
        attributedString.draw(in: textRect)
        
        image.unlockFocus()
        
        // Convert to .icns format
        let tempImageURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        
        do {
            // Save as PNG first
            guard let pngData = image.pngData() else {
                throw GenerationError.resourceCopyFailed("Failed to generate PNG data for default icon")
            }
            try pngData.write(to: tempImageURL)
            
            // Convert to .icns
            try convertToIcns(from: tempImageURL, to: destinationURL)
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempImageURL)
            
        } catch let error as GenerationError {
            try? FileManager.default.removeItem(at: tempImageURL)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: tempImageURL)
            throw GenerationError.resourceCopyFailed("Failed to generate default icon: \(error.localizedDescription)")
        }
    }
}

// MARK: - NSImage Extension for PNG Data

extension NSImage {
    /// Convert NSImage to PNG data
    /// - Returns: PNG data representation of the image, or nil if conversion fails
    func pngData() -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        return bitmapImage.representation(using: .png, properties: [:])
    }
}
