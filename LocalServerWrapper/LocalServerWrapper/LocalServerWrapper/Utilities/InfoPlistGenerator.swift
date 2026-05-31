//
//  InfoPlistGenerator.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation

/// Utility for generating Info.plist files for app bundles
struct InfoPlistGenerator {
    
    // MARK: - Public Methods
    
    /// Generate an Info.plist file for a server configuration
    /// - Parameters:
    ///   - configuration: The server configuration to generate Info.plist for
    ///   - bundleURL: The URL of the app bundle where Info.plist should be created
    /// - Throws: GenerationError if Info.plist creation fails
    static func generate(for configuration: ServerConfiguration, at bundleURL: URL) throws {
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        
        // Create Info.plist dictionary
        let infoPlist = createInfoPlistDictionary(for: configuration)
        
        // Write Info.plist to file
        do {
            let plistData = try PropertyListSerialization.data(
                fromPropertyList: infoPlist,
                format: .xml,
                options: 0
            )
            try plistData.write(to: infoPlistURL)
        } catch {
            throw GenerationError.bundleCreationFailed("Failed to write Info.plist: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    /// Create the Info.plist dictionary with all required keys
    /// - Parameter configuration: The server configuration
    /// - Returns: Dictionary containing all Info.plist key-value pairs
    private static func createInfoPlistDictionary(for configuration: ServerConfiguration) -> [String: Any] {
        var infoPlist: [String: Any] = [:]
        
        // Required: Info.plist format version
        infoPlist["CFBundleInfoDictionaryVersion"] = "6.0"
        
        // Required: Development region
        infoPlist["CFBundleDevelopmentRegion"] = "en"
        
        // Bundle identifier - unique per configuration
        infoPlist["CFBundleIdentifier"] = "com.localserverwrapper.generated.\(configuration.id.uuidString.lowercased())"
        
        // Bundle name - from configuration name
        infoPlist["CFBundleName"] = configuration.name
        
        // Display name - also use configuration name
        infoPlist["CFBundleDisplayName"] = configuration.name
        
        // Executable name - fixed to ServerAppBundle
        infoPlist["CFBundleExecutable"] = "ServerAppBundle"
        
        // Bundle version
        infoPlist["CFBundleVersion"] = "1.0.0"
        infoPlist["CFBundleShortVersionString"] = "1.0.0"
        
        // Package type - application
        infoPlist["CFBundlePackageType"] = "APPL"
        
        // Copyright
        infoPlist["NSHumanReadableCopyright"] = ""
        
        // Icon file - set if custom icon provided
        if configuration.customIconPath != nil {
            infoPlist["CFBundleIconFile"] = "AppIcon"
        }
        
        // Minimum system version - macOS 13.0
        infoPlist["LSMinimumSystemVersion"] = "13.0"
        
        // High resolution capable
        infoPlist["NSHighResolutionCapable"] = true
        
        // Principal class (for SwiftUI apps)
        infoPlist["NSPrincipalClass"] = "NSApplication"
        
        // Application category
        infoPlist["LSApplicationCategoryType"] = "public.app-category.developer-tools"
        
        // Support for dark mode
        infoPlist["NSRequiresAquaSystemAppearance"] = false
        
        return infoPlist
    }
}
