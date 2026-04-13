//
//  ContentView.swift
//  VillageWorld
//
//  Root view: SpriteKit game scene + SwiftUI overlays in a ZStack.
//

import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        ZStack {
            // Full-screen game scene
            SpriteView(scene: appState.gameScene)
                .ignoresSafeArea()

            // SwiftUI HUD layer
            HUDOverlay()
                .environmentObject(appState)

            // Dialogue panel — shown when a character is tapped (Phase 2+)
            if appState.isDialogueActive {
                // DialogueView will be wired in Phase 4
                EmptyView()
            }
        }
        .statusBarHidden()
    }
}

#Preview {
    ContentView()
}
