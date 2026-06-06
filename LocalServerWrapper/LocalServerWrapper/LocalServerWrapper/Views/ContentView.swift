//
//  ContentView.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import SwiftUI

struct ContentView: View {
    let configurationManager: ConfigurationManager

    var body: some View {
        ConfigurationListView(configurationManager: configurationManager)
    }
}

#Preview {
    ContentView(configurationManager: ConfigurationManager())
}
