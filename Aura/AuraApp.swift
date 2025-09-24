//
//  AuraApp.swift
//  Aura
//
//  Created by Mac Mini on 02/09/2025.
//

import SwiftUI
import SwiftData

@main
struct AuraApp: App {
    @StateObject private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .onAppear {
                    locationManager.requestLocationPermission()
                }
        }

    }
}
