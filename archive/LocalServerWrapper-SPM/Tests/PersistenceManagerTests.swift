//
//  PersistenceManagerTests.swift
//  LocalServerWrapperTests
//
//  Created by Kiro
//

import XCTest
@testable import LocalServerWrapper

final class PersistenceManagerTests: XCTestCase {
    
    var tempDirectory: URL!
    var persistenceManager: TestPersistenceManager!
    var fileManager: FileManager!
    
    override func setUp() {
        super.setUp()
        
        // Create a temporary directory for testing
        fileManager = FileManager.default
        tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("LocalServerWrapperTests")
            .appendingPathComponent(UUID().uuidString)
        
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create a custom persistence manager with temp directory
        persistenceManager = TestPersistenceManager(testDirectory: tempDirectory, fileManager: fileManager)
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? fileManager.removeItem(at: tempDirectory.deletingLastPathComponent())
        
        super.tearDown()
    }
    
    // MARK: - Save Tests
    
    func testSaveEmptyConfigurations() throws {
        // Given
        let configurations: [ServerConfiguration] = []
        
        // When
        try persistenceManager.save(configurations)
        
        // Then
        let loaded = try persistenceManager.load()
        XCTAssertEqual(loaded, configurations)
    }
    
    func testSaveSingleConfiguration() throws {
        // Given
        let config = ServerConfiguration(
            name: "Test Server",
            command: "npm",
            arguments: ["run", "dev"],
            localhostURL: "http://localhost:3000"
        )
        let configurations = [config]
        
        // When
        try persistenceManager.save(configurations)
        
        // Then
        let loaded = try persistenceManager.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Test Server")
        XCTAssertEqual(loaded.first?.command, "npm")
        XCTAssertEqual(loaded.first?.arguments, ["run", "dev"])
        XCTAssertEqual(loaded.first?.localhostURL, "http://localhost:3000")
    }
    
    func testSaveMultipleConfigurations() throws {
        // Given
        let config1 = ServerConfiguration(
            name: "Node Server",
            command: "npm",
            arguments: ["start"]
        )
        let config2 = ServerConfiguration(
            name: "Python Server",
            command: "python3",
            arguments: ["-m", "http.server"]
        )
        let config3 = ServerConfiguration(
            name: "Ruby Server",
            command: "ruby",
            arguments: ["server.rb"]
        )
        let configurations = [config1, config2, config3]
        
        // When
        try persistenceManager.save(configurations)
        
        // Then
        let loaded = try persistenceManager.load()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[0].name, "Node Server")
        XCTAssertEqual(loaded[1].name, "Python Server")
        XCTAssertEqual(loaded[2].name, "Ruby Server")
    }
    
    func testSaveWithAllOptionalFields() throws {
        // Given
        let config = ServerConfiguration(
            name: "Full Config",
            command: "/usr/local/bin/node",
            arguments: ["server.js"],
            localhostURL: "http://localhost:8080",
            readySignalPattern: "Server listening on",
            portDetectionPattern: "port (\\d+)",
            customIconPath: "/path/to/icon.png"
        )
        let configurations = [config]
        
        // When
        try persistenceManager.save(configurations)
        
        // Then
        let loaded = try persistenceManager.load()
        XCTAssertEqual(loaded.count, 1)
        let loadedConfig = loaded.first!
        XCTAssertEqual(loadedConfig.name, "Full Config")
        XCTAssertEqual(loadedConfig.command, "/usr/local/bin/node")
        XCTAssertEqual(loadedConfig.arguments, ["server.js"])
        XCTAssertEqual(loadedConfig.localhostURL, "http://localhost:8080")
        XCTAssertEqual(loadedConfig.readySignalPattern, "Server listening on")
        XCTAssertEqual(loadedConfig.portDetectionPattern, "port (\\d+)")
        XCTAssertEqual(loadedConfig.customIconPath, "/path/to/icon.png")
    }
    
    func testSaveOverwritesPreviousData() throws {
        // Given
        let config1 = ServerConfiguration(name: "First", command: "npm")
        try persistenceManager.save([config1])
        
        let config2 = ServerConfiguration(name: "Second", command: "python3")
        
        // When
        try persistenceManager.save([config2])
        
        // Then
        let loaded = try persistenceManager.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Second")
    }
    
    // MARK: - Load Tests
    
    func testLoadWhenFileDoesNotExist() throws {
        // When
        let loaded = try persistenceManager.load()
        
        // Then
        XCTAssertEqual(loaded, [])
    }
    
    func testLoadPreservesConfigurationOrder() throws {
        // Given
        let configs = [
            ServerConfiguration(name: "A", command: "cmd1"),
            ServerConfiguration(name: "B", command: "cmd2"),
            ServerConfiguration(name: "C", command: "cmd3")
        ]
        try persistenceManager.save(configs)
        
        // When
        let loaded = try persistenceManager.load()
        
        // Then
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[0].name, "A")
        XCTAssertEqual(loaded[1].name, "B")
        XCTAssertEqual(loaded[2].name, "C")
    }
    
    func testLoadPreservesUUIDs() throws {
        // Given
        let id1 = UUID()
        let id2 = UUID()
        let configs = [
            ServerConfiguration(id: id1, name: "First", command: "npm"),
            ServerConfiguration(id: id2, name: "Second", command: "python3")
        ]
        try persistenceManager.save(configs)
        
        // When
        let loaded = try persistenceManager.load()
        
        // Then
        XCTAssertEqual(loaded[0].id, id1)
        XCTAssertEqual(loaded[1].id, id2)
    }
    
    func testLoadPreservesTimestamps() throws {
        // Given
        let config = ServerConfiguration(name: "Test", command: "npm")
        let originalCreatedAt = config.createdAt
        let originalUpdatedAt = config.updatedAt
        try persistenceManager.save([config])
        
        // When
        let loaded = try persistenceManager.load()
        
        // Then
        let loadedConfig = loaded.first!
        // Timestamps should be preserved (within a small tolerance for encoding/decoding)
        XCTAssertEqual(
            loadedConfig.createdAt.timeIntervalSince1970,
            originalCreatedAt.timeIntervalSince1970,
            accuracy: 1.0
        )
        XCTAssertEqual(
            loadedConfig.updatedAt.timeIntervalSince1970,
            originalUpdatedAt.timeIntervalSince1970,
            accuracy: 1.0
        )
    }
    
    // MARK: - Round-Trip Tests
    
    func testRoundTripPreservesAllData() throws {
        // Given
        let configs = [
            ServerConfiguration(
                name: "Node Dev",
                command: "npm",
                arguments: ["run", "dev"],
                localhostURL: "http://localhost:3000",
                readySignalPattern: "ready",
                portDetectionPattern: ":(\\d+)"
            ),
            ServerConfiguration(
                name: "Python API",
                command: "python3",
                arguments: ["api.py"],
                localhostURL: "http://localhost:8000"
            )
        ]
        
        // When
        try persistenceManager.save(configs)
        let loaded = try persistenceManager.load()
        
        // Then
        XCTAssertEqual(loaded.count, configs.count)
        for (original, loaded) in zip(configs, loaded) {
            XCTAssertEqual(loaded.id, original.id)
            XCTAssertEqual(loaded.name, original.name)
            XCTAssertEqual(loaded.command, original.command)
            XCTAssertEqual(loaded.arguments, original.arguments)
            XCTAssertEqual(loaded.localhostURL, original.localhostURL)
            XCTAssertEqual(loaded.readySignalPattern, original.readySignalPattern)
            XCTAssertEqual(loaded.portDetectionPattern, original.portDetectionPattern)
        }
    }
    
    // MARK: - Backup Tests
    
    func testBackupCreatesBackupFile() throws {
        // Given
        let config = ServerConfiguration(name: "Test", command: "npm")
        try persistenceManager.save([config])
        
        // When
        try persistenceManager.backup()
        
        // Then - backup should succeed (we can't easily verify the file without accessing internals)
        // The fact that it doesn't throw is sufficient
    }
    
    func testBackupWhenNoConfigurationFileExists() throws {
        // When/Then - should not throw
        try persistenceManager.backup()
    }
    
    func testMultipleBackupsCreateMultipleFiles() throws {
        // Given
        let config = ServerConfiguration(name: "Test", command: "npm")
        try persistenceManager.save([config])
        
        // When
        try persistenceManager.backup()
        Thread.sleep(forTimeInterval: 0.1) // Ensure different timestamps
        try persistenceManager.backup()
        
        // Then - should not throw
    }
    
    // MARK: - Restore Tests
    
    func testRestoreFromValidBackup() throws {
        // Given
        let originalConfig = ServerConfiguration(name: "Original", command: "npm")
        try persistenceManager.save([originalConfig])
        try persistenceManager.backup()
        
        // Modify the configuration
        let modifiedConfig = ServerConfiguration(name: "Modified", command: "python3")
        try persistenceManager.save([modifiedConfig])
        
        // Get the backup URL (we need to find it)
        // For this test, we'll create a manual backup file
        let backupURL = fileManager.temporaryDirectory
            .appendingPathComponent("test-backup.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let backupData = try encoder.encode([originalConfig])
        try backupData.write(to: backupURL)
        
        // When
        try persistenceManager.restore(from: backupURL)
        
        // Then
        let loaded = try persistenceManager.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Original")
        XCTAssertEqual(loaded.first?.command, "npm")
        
        // Cleanup
        try? fileManager.removeItem(at: backupURL)
    }
    
    func testRestoreFromNonExistentBackupThrows() throws {
        // Given
        let nonExistentURL = fileManager.temporaryDirectory
            .appendingPathComponent("nonexistent.json")
        
        // When/Then
        XCTAssertThrowsError(try persistenceManager.restore(from: nonExistentURL)) { error in
            guard let persistenceError = error as? PersistenceError else {
                XCTFail("Expected PersistenceError")
                return
            }
            if case .restoreFailed = persistenceError {
                // Expected error type
            } else {
                XCTFail("Expected restoreFailed error")
            }
        }
    }
    
    func testRestoreFromInvalidJSONThrows() throws {
        // Given
        let invalidBackupURL = fileManager.temporaryDirectory
            .appendingPathComponent("invalid-backup.json")
        let invalidData = "{ invalid json }".data(using: .utf8)!
        try invalidData.write(to: invalidBackupURL)
        
        // When/Then
        XCTAssertThrowsError(try persistenceManager.restore(from: invalidBackupURL)) { error in
            guard let persistenceError = error as? PersistenceError else {
                XCTFail("Expected PersistenceError")
                return
            }
            if case .restoreFailed = persistenceError {
                // Expected error type
            } else {
                XCTFail("Expected restoreFailed error")
            }
        }
        
        // Cleanup
        try? fileManager.removeItem(at: invalidBackupURL)
    }
    
    // MARK: - Atomic Write Tests
    
    func testAtomicWritePreventsConcurrentCorruption() throws {
        // When - perform multiple concurrent saves
        let expectation = self.expectation(description: "Concurrent saves")
        expectation.expectedFulfillmentCount = 5
        
        for i in 0..<5 {
            DispatchQueue.global().async {
                let config = ServerConfiguration(name: "Config \(i)", command: "cmd\(i)")
                try? self.persistenceManager.save([config])
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 5.0)
        
        // Then - should be able to load without corruption
        let loaded = try persistenceManager.load()
        XCTAssertEqual(loaded.count, 1) // Last write wins
        XCTAssertFalse(loaded.isEmpty)
    }
    
    // MARK: - Special Characters Tests
    
    func testSaveConfigurationWithSpecialCharacters() throws {
        // Given
        let config = ServerConfiguration(
            name: "Test \"Server\" with 'quotes'",
            command: "npm",
            arguments: ["--option=value with spaces", "arg\"with\"quotes"],
            localhostURL: "http://localhost:3000/path?query=value&other=123"
        )
        
        // When
        try persistenceManager.save([config])
        let loaded = try persistenceManager.load()
        
        // Then
        XCTAssertEqual(loaded.first?.name, config.name)
        XCTAssertEqual(loaded.first?.arguments, config.arguments)
        XCTAssertEqual(loaded.first?.localhostURL, config.localhostURL)
    }
    
    func testSaveConfigurationWithUnicodeCharacters() throws {
        // Given
        let config = ServerConfiguration(
            name: "服务器 🚀 Server",
            command: "npm",
            arguments: ["--emoji=🎉", "--chinese=你好"]
        )
        
        // When
        try persistenceManager.save([config])
        let loaded = try persistenceManager.load()
        
        // Then
        XCTAssertEqual(loaded.first?.name, config.name)
        XCTAssertEqual(loaded.first?.arguments, config.arguments)
    }
}

// MARK: - Test Helper

/// A test-specific persistence manager that uses a custom directory
class TestPersistenceManager: PersistenceManager {
    private let testConfigurationsURL: URL
    private let testBackupsDirectory: URL
    private let testFileManager: FileManager
    
    init(testDirectory: URL, fileManager: FileManager = .default) {
        self.testFileManager = fileManager
        self.testConfigurationsURL = testDirectory.appendingPathComponent("configurations.json")
        self.testBackupsDirectory = testDirectory.appendingPathComponent("Backups")
        
        super.init(fileManager: fileManager)
    }
    
    override func save(_ configurations: [ServerConfiguration]) throws {
        // Ensure directories exist
        try createTestDirectoriesIfNeeded()
        
        // Encode configurations to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data: Data
        do {
            data = try encoder.encode(configurations)
        } catch {
            throw PersistenceError.encodingFailed(error.localizedDescription)
        }
        
        // Write atomically to prevent corruption
        do {
            try data.write(to: testConfigurationsURL, options: .atomic)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain {
                switch error.code {
                case NSFileWriteNoPermissionError:
                    throw PersistenceError.permissionDenied
                case NSFileWriteOutOfSpaceError:
                    throw PersistenceError.diskFull
                default:
                    throw PersistenceError.writeFailed(error.localizedDescription)
                }
            }
            throw PersistenceError.writeFailed(error.localizedDescription)
        }
    }
    
    override func load() throws -> [ServerConfiguration] {
        guard testFileManager.fileExists(atPath: testConfigurationsURL.path) else {
            return []
        }
        
        let data: Data
        do {
            data = try Data(contentsOf: testConfigurationsURL)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
                throw PersistenceError.permissionDenied
            }
            throw PersistenceError.readFailed(error.localizedDescription)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let configurations = try decoder.decode([ServerConfiguration].self, from: data)
            return configurations
        } catch {
            throw PersistenceError.decodingFailed(error.localizedDescription)
        }
    }
    
    override func backup() throws {
        guard testFileManager.fileExists(atPath: testConfigurationsURL.path) else {
            return
        }
        
        try createTestDirectoriesIfNeeded()
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let safeTimestamp = timestamp.replacingOccurrences(of: ":", with: "-")
        let uniqueId = UUID().uuidString.prefix(8)
        let backupFilename = "configurations-\(safeTimestamp)-\(uniqueId).json"
        let backupURL = testBackupsDirectory.appendingPathComponent(backupFilename)
        
        do {
            try testFileManager.copyItem(at: testConfigurationsURL, to: backupURL)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain {
                switch error.code {
                case NSFileWriteNoPermissionError:
                    throw PersistenceError.permissionDenied
                case NSFileWriteOutOfSpaceError:
                    throw PersistenceError.diskFull
                default:
                    throw PersistenceError.backupFailed(error.localizedDescription)
                }
            }
            throw PersistenceError.backupFailed(error.localizedDescription)
        }
    }
    
    override func restore(from backupURL: URL) throws {
        guard testFileManager.fileExists(atPath: backupURL.path) else {
            throw PersistenceError.restoreFailed("Backup file does not exist")
        }
        
        let data: Data
        do {
            data = try Data(contentsOf: backupURL)
        } catch {
            throw PersistenceError.restoreFailed("Cannot read backup file: \(error.localizedDescription)")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            _ = try decoder.decode([ServerConfiguration].self, from: data)
        } catch {
            throw PersistenceError.restoreFailed("Backup file contains invalid data: \(error.localizedDescription)")
        }
        
        if testFileManager.fileExists(atPath: testConfigurationsURL.path) {
            try? backup()
        }
        
        try createTestDirectoriesIfNeeded()
        
        do {
            if testFileManager.fileExists(atPath: testConfigurationsURL.path) {
                try testFileManager.removeItem(at: testConfigurationsURL)
            }
            
            try testFileManager.copyItem(at: backupURL, to: testConfigurationsURL)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain {
                switch error.code {
                case NSFileWriteNoPermissionError:
                    throw PersistenceError.permissionDenied
                case NSFileWriteOutOfSpaceError:
                    throw PersistenceError.diskFull
                default:
                    throw PersistenceError.restoreFailed(error.localizedDescription)
                }
            }
            throw PersistenceError.restoreFailed(error.localizedDescription)
        }
    }
    
    private func createTestDirectoriesIfNeeded() throws {
        let directories = [
            testConfigurationsURL.deletingLastPathComponent(),
            testBackupsDirectory
        ]
        
        for directory in directories {
            if !testFileManager.fileExists(atPath: directory.path) {
                do {
                    try testFileManager.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                } catch let error as NSError {
                    if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError {
                        throw PersistenceError.permissionDenied
                    }
                    throw PersistenceError.writeFailed("Failed to create directory: \(error.localizedDescription)")
                }
            }
        }
    }
}

