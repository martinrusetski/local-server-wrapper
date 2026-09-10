//
//  LocalServerWrapperTests.swift
//  LocalServerWrapperTests
//
//  Created by Martin R on 01.05.2026.
//

import Testing
import Foundation
@testable import LocalServerWrapper

struct LocalServerWrapperTests {

    @Test @MainActor func missingCustomIconUsesBundledPlaceholder() throws {
        let fileManager = FileManager.default
        let bundleURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources")

        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: bundleURL) }

        let defaultIconURL = try #require(DefaultIcon.resourceURL)
        #expect(DefaultIcon.image != nil)
        try IconProcessor.processIcon(customIconPath: nil, bundleURL: bundleURL)

        let generatedIconURL = resourcesURL.appendingPathComponent("AppIcon.icns")
        #expect(try Data(contentsOf: generatedIconURL) == Data(contentsOf: defaultIconURL))
    }

    @Test @MainActor func customIconTakesPrecedenceOverBundledPlaceholder() throws {
        let fileManager = FileManager.default
        let bundleURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources")

        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: bundleURL) }

        let customIconURL = try #require(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
        try IconProcessor.processIcon(customIconPath: customIconURL.path, bundleURL: bundleURL)

        let generatedIconURL = resourcesURL.appendingPathComponent("AppIcon.icns")
        #expect(try Data(contentsOf: generatedIconURL) == Data(contentsOf: customIconURL))
        #expect(try Data(contentsOf: generatedIconURL) != Data(contentsOf: #require(DefaultIcon.resourceURL)))
    }

    @Test @MainActor func generatedInfoPlistAlwaysReferencesProcessedIcon() throws {
        let fileManager = FileManager.default
        let bundleURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")
        let contentsURL = bundleURL.appendingPathComponent("Contents")

        try fileManager.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: bundleURL) }

        let configuration = ServerConfiguration(name: "Icon Test", command: "true")
        try InfoPlistGenerator.generate(for: configuration, at: bundleURL)

        let data = try Data(contentsOf: contentsURL.appendingPathComponent("Info.plist"))
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
    }

    @Test @MainActor func appRowUsesFirstMeaningfulInlineCommand() {
        let configuration = ServerConfiguration(
            name: "Docs",
            command: "",
            scriptSource: .inline,
            inlineScriptContent: "#!/bin/zsh\n# Start docs\nnpm run dev\n"
        )

        #expect(ConfigurationRowView.subtitle(for: configuration) == "npm run dev")
    }

    @Test @MainActor func appRowFallsBackToFixedURLWithoutACommand() {
        let configuration = ServerConfiguration(
            name: "Docs",
            command: "",
            localhostURL: "http://localhost:3000",
            urlDetectionMode: .fixed,
            scriptSource: .inline,
            inlineScriptContent: nil
        )

        #expect(ConfigurationRowView.subtitle(for: configuration) == "http://localhost:3000")
    }

    @Test @MainActor func savingAnEditedConfigurationRegeneratesItsExistingExportInPlace() async throws {
        let configurationID = UUID()
        let configuration = ServerConfiguration(
            id: configurationID,
            name: "Edited-\(configurationID.uuidString)",
            command: "",
            scriptSource: .inline,
            inlineScriptContent: "npm run updated"
        )
        let manager = TestConfigurationManager(configurations: [configuration])
        let fileManager = FileManager.default
        let testDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("LocalServerWrapperTests-\(UUID().uuidString)")
        let exportedURL = testDirectory.appendingPathComponent("Existing Export.app")
        let exportedPathKey = "exported_bundle_path_\(configurationID.uuidString)"
        let canonicalPathKey = "generated_bundle_path_\(configurationID.uuidString)"
        let canonicalHashKey = "generated_config_hash_\(configurationID.uuidString)"

        try fileManager.createDirectory(at: exportedURL, withIntermediateDirectories: true)
        try Data("old bundle".utf8).write(to: exportedURL.appendingPathComponent("old.txt"))
        UserDefaults.standard.set(exportedURL.path, forKey: exportedPathKey)

        defer {
            if let canonicalPath = UserDefaults.standard.string(forKey: canonicalPathKey) {
                try? fileManager.removeItem(atPath: canonicalPath)
            }
            UserDefaults.standard.removeObject(forKey: exportedPathKey)
            UserDefaults.standard.removeObject(forKey: canonicalPathKey)
            UserDefaults.standard.removeObject(forKey: canonicalHashKey)
            try? fileManager.removeItem(at: testDirectory)
        }

        let viewModel = ConfigurationListViewModel(
            configurationManager: manager,
            bundleGenerator: TestAppBundleGenerator()
        )

        viewModel.configurationDidSave(configurationID)

        var regeneratedURL: URL?
        for _ in 0..<100 {
            if case .succeeded(let url) = viewModel.operationState(for: configurationID) {
                regeneratedURL = url
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(regeneratedURL?.standardizedFileURL.path == exportedURL.standardizedFileURL.path)
        #expect(fileManager.fileExists(atPath: exportedURL.path))
        #expect(!fileManager.fileExists(atPath: exportedURL.appendingPathComponent("old.txt").path))

        let embeddedConfigURL = exportedURL.appendingPathComponent("Contents/Resources/configuration.json")
        let embeddedData = try Data(contentsOf: embeddedConfigURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let embeddedConfiguration = try decoder.decode(ServerConfiguration.self, from: embeddedData)
        #expect(embeddedConfiguration.inlineScriptContent == "npm run updated")
    }

    @Test @MainActor func savingWithoutAnExistingExportDoesNotGenerateAnApp() async {
        let configuration = ServerConfiguration(
            name: "Not Yet Exported",
            command: "",
            scriptSource: .inline,
            inlineScriptContent: "npm run dev"
        )
        let generator = TestAppBundleGenerator()
        let viewModel = ConfigurationListViewModel(
            configurationManager: TestConfigurationManager(configurations: [configuration]),
            bundleGenerator: generator
        )

        viewModel.configurationDidSave(configuration.id)
        await Task.yield()

        #expect(generator.generationCount == 0)
        #expect(viewModel.exportedBundleURL(for: configuration.id) == nil)
        #expect(viewModel.operationState(for: configuration.id) == .idle)
    }

}

private final class TestConfigurationManager: ConfigurationManagerProtocol {
    var configurations: [ServerConfiguration]

    init(configurations: [ServerConfiguration]) {
        self.configurations = configurations
    }

    func createConfiguration(_ config: ServerConfiguration) throws {
        configurations.append(config)
    }

    func updateConfiguration(_ config: ServerConfiguration) throws {
        guard let index = configurations.firstIndex(where: { $0.id == config.id }) else { return }
        configurations[index] = config
    }

    func deleteConfiguration(id: UUID) throws {
        configurations.removeAll { $0.id == id }
    }

    func listConfigurations() -> [ServerConfiguration] {
        configurations
    }

    func getConfiguration(id: UUID) -> ServerConfiguration? {
        configurations.first { $0.id == id }
    }
}

private final class TestAppBundleGenerator: AppBundleGeneratorProtocol {
    private(set) var generationCount = 0

    func generate(
        configuration: ServerConfiguration,
        outputPath: URL,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> URL {
        generationCount += 1
        let fileManager = FileManager.default
        let bundleURL = outputPath.appendingPathComponent("\(configuration.name).app")
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources")

        try? fileManager.removeItem(at: bundleURL)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        progressHandler?(0.5, "Embedding configuration…")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(configuration)
        try data.write(to: resourcesURL.appendingPathComponent("configuration.json"))
        progressHandler?(1, "Bundle generation complete")
        return bundleURL
    }
}
