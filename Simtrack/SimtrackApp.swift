//
//  SimtrackApp.swift
//  Simtrack
//
//  Created by Eduard Juan on 26/11/26.
//

import SwiftUI

@main
struct SimtrackApp: App {
    init() {
        PCDiscovery.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
