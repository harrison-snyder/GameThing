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

            // Dialogue panel
            if appState.isDialogueActive {
                DialogueView()
                    .environmentObject(appState)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(duration: 0.3), value: appState.isDialogueActive)
            }
        }
        .statusBarHidden()
    }
}

#Preview {
    ContentView()
}
