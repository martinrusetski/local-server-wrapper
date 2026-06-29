//
//  main.swift
//  ServerLauncher  (thin launcher stub)
//
//  The entire launcher binary: it owns the .app bundle identity (icon, name, CFBundleIdentifier,
//  and the LSWConfigurationID that ConfigurationLoader reads), and delegates ALL behavior to the
//  shared ServerRuntime.framework loaded from ~/Library/Frameworks at launch.
//
//  Target setup (Phase 1 scaffolding):
//    • App target, this is the only source file.
//    • Link ServerRuntime.framework with "Do Not Embed".
//    • The manager injects the absolute ~/Library/Frameworks rpath per-generation; for dev runs add
//      that path (or @executable_path/../Frameworks) to LD_RUNPATH_SEARCH_PATHS.
//

import ServerRuntime

// `App.main()` is provided by the SwiftUI App protocol. ServerAppBundleApp lives in the framework
// and is made `public` there (Phase 2). This replaces its old `@main` attribute.
ServerAppBundleApp.main()
