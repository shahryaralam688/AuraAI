//
//  VoiceView.swift
//  Aura
//
//  Created by Cascade on 02/09/2025.
//

import SwiftUI

struct VoiceView: View {
    @StateObject private var client = WebRTCVoiceClient(backendBaseURL: URL(string: "https://family-jelsoft-laden-cast.trycloudflare.com")!)

    var body: some View {
        VStack(spacing: 24) {
            // Status
            Text(client.state.rawValue)
                .font(.headline)

            // Mic button
            Button(action: toggle) {
                ZStack {
                    Circle()
                        .fill(client.state == .connected ? Color.green : (client.state == .connecting ? Color.orange : Color.blue))
                        .frame(width: 96, height: 96)
                        .shadow(radius: 8)
                    Image(systemName: client.state == .connected ? "mic.fill" : "mic")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .accessibilityLabel(client.state == .connected ? "Stop" : "Start")

            // Controls
            HStack(spacing: 16) {
                Button("Start") { client.start() }
                    .buttonStyle(.borderedProminent)
                Button("Stop") { client.stop() }
                    .buttonStyle(.bordered)
            }

            // Logs
            List(client.logs.suffix(200), id: \.self) { line in
                Text(line)
                    .font(.caption.monospaced())
            }
        }
        .padding()
        .navigationTitle("Voice")
    }

    private func toggle() {
        if client.state == .connected || client.state == .connecting {
            client.stop()
        } else {
            client.start()
        }
    }
}

#Preview {
    VoiceView()
}
