//
//  main.swift
//  ServerLauncher  (thin launcher stub)
//
//  The entire launcher binary: it owns the .app bundle identity (icon, name, CFBundleIdentifier,
//  and the LSWConfigurationID that ConfigurationLoader reads), and delegates ALL behavior to the
//  ServerRuntime.framework embedded in the app bundle at launch.
//
//  Target setup (Phase 1 scaffolding):
//    • App target, this is the only source file.
//    • Link and embed ServerRuntime.framework with code signing on copy.
//    • Use only @executable_path/../Frameworks for the runtime search path.
//

import ServerRuntime

// `App.main()` is provided by the SwiftUI App protocol. ServerAppBundleApp lives in the framework
// and is made `public` there (Phase 2). This replaces its old `@main` attribute.
ServerAppBundleApp.main()
