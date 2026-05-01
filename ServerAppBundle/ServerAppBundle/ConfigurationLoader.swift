//
//  ConfigurationLoader.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import Foundation
import os.log

/// Logger for configuration loading operations
private let logger = OSLog(subsystem: "com.localserverwrapper.serverappbundle", category: "configuration")

/// Errors that can occur when loading embedded configuration
enum ConfigurationLoadError: Error, LocalizedError {
    case configurationFileNotFound
    case invalidJSON(Error)
    case decodingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .configurationFileNotFound:
            return "Configuration file not found in app bundle Resources"
        case .invalidJSON(let error):
            return "Invalid JSON in configuration file: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode configuration: \(error.localizedDescription)"
        }
    }
}

/// Utility for loading embedded server configuration from the app bundle
///
/// This loader ensures bundle relocatability by using `Bundle.main` APIs
/// to access resources relative to the bundle location, with no hardcoded paths.
/// The bundle can be moved to any filesystem location and will continue to function.
struct ConfigurationLoader {
    
    /// Load the embedded configuration from the app bundle's Resources directory
    ///
    /// This method uses `Bundle.main` to locate resources, ensuring the bundle
    /// is relocatable and can function from any filesystem location.
    ///
    /// - Returns: The loaded ServerConfiguration
    /// - Throws: ConfigurationLoadError if loading or parsing fails
    static func loadEmbeddedConfiguration() throws -> ServerConfiguration {
        os_log(.info, log: logger, "Loading embedded configuration")
        
        // Get the main bundle - this works from any bundle location (relocatable)
        let bundle = Bundle.main
        
        // Locate the configuration.json file in the Resources directory
        guard let configURL = bundle.url(forResource: "configuration", withExtension: "json") else {
            os_log(.error, log: logger, "Configuration file not found in bundle resources")
            throw ConfigurationLoadError.configurationFileNotFound
        }
        
        os_log(.debug, log: logger, "Found configuration file at: %{public}@", configURL.path)
        
        // Read the JSON data
        let jsonData: Data
        do {
            jsonData = try Data(contentsOf: configURL)
            os_log(.debug, log: logger, "Read %d bytes from configuration file", jsonData.count)
        } catch {
            os_log(.error, log: logger, "Failed to read configuration file: %{public}@", error.localizedDescription)
            throw ConfigurationLoadError.invalidJSON(error)
        }
        
        // Decode the configuration
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let configuration = try decoder.decode(ServerConfiguration.self, from: jsonData)
            os_log(.info, log: logger, "Successfully loaded configuration: %{public}@", configuration.name)
            return configuration
        } catch {
            os_log(.error, log: logger, "Failed to decode configuration: %{public}@", error.localizedDescription)
            throw ConfigurationLoadError.decodingFailed(error)
        }
    }
    
    /// Load the embedded configuration with a fallback default configuration
    /// This method never throws and returns a default configuration if loading fails
    /// - Returns: The loaded ServerConfiguration or a default configuration
    static func loadEmbeddedConfigurationWithFallback() -> ServerConfiguration {
        do {
            return try loadEmbeddedConfiguration()
        } catch {
            // Log the error
            os_log(.error, log: logger, "Failed to load embedded configuration, using fallback: %{public}@", error.localizedDescription)
            print("⚠️ Failed to load embedded configuration: \(error.localizedDescription)")
            print("⚠️ Using fallback default configuration")
            
            // Return a default configuration
            return ServerConfiguration(
                name: "Default Server",
                command: "/bin/echo",
                arguments: ["Configuration file not found. Please regenerate this app bundle."],
                localhostURL: "http://localhost:3000"
            )
        }
    }
}
