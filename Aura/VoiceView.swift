//
//  VoiceView.swift
//  Aura
//
//  Created by Cascade on 02/09/2025.
//

import SwiftUI

// MARK: - Message Model
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
    var isTyping: Bool = false
}

struct VoiceView: View {
    @StateObject private var client = WebRTCVoiceClient(backendBaseURL: URL(string: "https://dev.api2.limitless-lighting.co.uk")!)
    @State private var messages: [ChatMessage] = []
    @State private var isListening = false
    @State private var pulseAnimation = false
    @State private var showTextInput = false
    @State private var textInput = ""
    @State private var glowAnimation = false
    @State private var breathingAnimation = false
    @State private var currentTranscription = ""
    @State private var waveAnimation = false
    @State private var wavePhases: [Double] = Array(repeating: 0, count: 8)
    @State private var conversationHistory: [String] = []
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.05, blue: 0.08),
                        Color(red: 0.05, green: 0.08, blue: 0.12),
                        Color(red: 0.08, green: 0.12, blue: 0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // App Title Header
                    appTitleHeader
                    
                    // Live Transcription Area
                    liveTranscriptionView
                        .frame(height: geometry.size.height * 0.40)
                    
                    Spacer()
                    
                    // Central Voice Button
                    centralVoiceButton
                    Spacer()
                    
                    bottomControlsView
                    
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            addWelcomeMessage()
            startBreathingAnimation()
        }
        .onChange(of: client.state) { _, newState in
            handleStateChange(newState)
        }
        .onChange(of: client.lastAITranscript) { _, transcript in
            guard let t = transcript?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                conversationHistory.append("AI: \(t)")
            }
        }
        .onChange(of: isListening) { _, newValue in
            glowAnimation = newValue
            waveAnimation = newValue
            if newValue {
                startWaveAnimation()
            } else {
                stopWaveAnimation()
            }
        }
    }
    
    // MARK: - App Title Header
    private var appTitleHeader: some View {
        VStack(spacing: 8) {
            Text("Aura")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: Color.white.opacity(0.3), radius: 10, x: 0, y: 0)
            
            Text("Powered By Limi")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.top, 60)
        .padding(.bottom, 20)
    }
    
    // MARK: - Live Transcription View
    private var liveTranscriptionView: some View {
        VStack(spacing: 0) {
            // Simple header
            HStack {
                Text("Conversation")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(charlesGreen)
                
                Spacer()
                
                // Live indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(emerald)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isListening ? 1.3 : 1.0)
                        .opacity(isListening ? 1.0 : 0.6)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isListening)
                    
                    Text(isListening ? "Live" : "Ready")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isListening ? emerald : alabaster.opacity(0.7))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // Conversation history in ChatGPT/Siri style
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Show conversation history
                        ForEach(Array(conversationHistory.enumerated()), id: \.offset) { index, message in
                            ConversationBubbleView(
                                message: message,
                                isUser: index % 2 == 0 && !message.hasPrefix("AI:") && !message.hasPrefix("🎤") && !message.hasPrefix("❌")
                            )
                            .id(index)
                        }
                        
                        // Current live transcription
                        if !currentTranscription.isEmpty {
                            ConversationBubbleView(
                                message: currentTranscription,
                                isUser: false,
                                isLive: isListening
                            )
                            .id("current")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .onChange(of: conversationHistory.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.5)) {
                        if let lastIndex = conversationHistory.indices.last {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: currentTranscription) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("current", anchor: .bottom)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(alabaster.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [alabaster.opacity(0.1), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Central Voice Button
    private var centralVoiceButton: some View {
        VStack(spacing: 30) {
            ZStack {
                // Premium wave animation rings (Siri/ChatGPT style)
                if isListening {
                    ForEach(0..<8, id: \.self) { index in
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        emerald.opacity(0.8),
                                        charlesGreen.opacity(0.6),
                                        eton.opacity(0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.5
                            )
                            .frame(width: 180 + CGFloat(index * 25), height: 180 + CGFloat(index * 25))
                            .scaleEffect(1.0 + sin(wavePhases[index]) * 0.15)
                            .opacity(0.9 - (Double(index) * 0.1) + sin(wavePhases[index]) * 0.3)
                            .animation(
                                .easeInOut(duration: 1.2)
                                .repeatForever(autoreverses: false),
                                value: wavePhases[index]
                            )
                    }
                }
                
                // Subtle breathing ring for idle state
                if !isListening {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [eton.opacity(0.4), charlesGreen.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 200, height: 200)
                        .scaleEffect(breathingAnimation ? 1.02 : 0.98)
                        .opacity(breathingAnimation ? 0.6 : 0.3)
                        .animation(
                            .easeInOut(duration: 4.0).repeatForever(autoreverses: true),
                            value: breathingAnimation
                        )
                }
                
                // Main voice button
                Button(action: toggle) {
                    ZStack {
                        // Button background with premium gradient
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(red: 0.15, green: 0.2, blue: 0.25),
                                        Color(red: 0.08, green: 0.12, blue: 0.16)
                                    ],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 90
                                )
                            )
                            .frame(width: 180, height: 180)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [alabaster.opacity(0.3), Color.clear],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(
                                color: isListening ? emerald.opacity(0.8) : alabaster.opacity(0.2),
                                radius: isListening ? 40 : 20,
                                x: 0,
                                y: 0
                            )
                        
                        // Microphone icon with premium styling
                        Image(systemName: microphoneIcon)
                            .font(.system(size: 52, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: isListening ? [emerald, charlesGreen] : [eton, charlesGreen],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(isListening ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.3), value: isListening)
                    }
                }
                .scaleEffect(isListening ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: isListening)
            }
            
            // Status text with better styling
            Text(statusText)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(statusColor)
                .opacity(0.9)
                .shadow(color: statusColor.opacity(0.3), radius: 5, x: 0, y: 0)
        }
    }
    
    // MARK: - Bottom Controls View
    private var bottomControlsView: some View {
        VStack(spacing: 16) {
            // Text input (optional)
            if showTextInput {
                HStack {
                    TextField("Type a message...", text: $textInput)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(.ultraThinMaterial)
                                .background(
                                    RoundedRectangle(cornerRadius: 25)
                                        .fill(Color.white.opacity(0.05))
                                )
                        )
                        .foregroundColor(.white)
                    
                    Button(action: sendTextMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
//            // Bottom control buttons
            HStack(spacing: 40) {
//                // Voice input toggle
//                Button(action: { withAnimation(.spring()) { showTextInput.toggle() } }) {
//                    Image(systemName: "mic.badge.plus")
//                        .font(.system(size: 20, weight: .medium))
//                        .foregroundColor(.white.opacity(0.7))
//                        .frame(width: 50, height: 50)
//                        .background(
//                            Circle()
//                                .fill(.ultraThinMaterial)
//                                .background(Color.white.opacity(0.05))
//                        )
//                }
//                
                // Text input toggle
                Button(action: { withAnimation(.spring()) { showTextInput.toggle() } }) {
                    Image(systemName: showTextInput ? "keyboard.chevron.compact.down" : "keyboard")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 50, height: 50)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .background(Color.white.opacity(0.05))
                        )
                }
                
//                // Settings button
//                Button(action: {}) {
//                    Image(systemName: "gearshape.fill")
//                        .font(.system(size: 20, weight: .medium))
//                        .foregroundColor(.white.opacity(0.7))
//                        .frame(width: 50, height: 50)
//                        .background(
//                            Circle()
//                                .fill(.ultraThinMaterial)
//                                .background(Color.white.opacity(0.05))
//                        )
//                }
            }
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Animation Functions
    private func startBreathingAnimation() {
        withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
            breathingAnimation = true
        }
    }
    
    private func startWaveAnimation() {
        for i in 0..<8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: false)
                ) {
                    wavePhases[i] = .pi * 2
                }
            }
        }
    }
    
    private func stopWaveAnimation() {
        withAnimation(.easeOut(duration: 0.5)) {
            for i in 0..<8 {
                wavePhases[i] = 0
            }
        }
    }
    
    // MARK: - Color Definitions
    private var charlesGreen: Color {
        Color(red: 0.0, green: 0.5, blue: 0.0) // #008000
    }
    
    private var eton: Color {
        Color(red: 0.58, green: 0.75, blue: 0.48) // #96C07B
    }
    
    private var emerald: Color {
        Color(red: 0.31, green: 0.78, blue: 0.47) // #50C878
    }
    
    private var alabaster: Color {
        Color(red: 0.96, green: 0.96, blue: 0.96) // #F5F5F5
    }
    
    // MARK: - Computed Properties
    private var gradientColors: [Color] {
        switch client.state {
        case .connected:
            return [emerald, charlesGreen]
        case .connecting:
            return [eton, charlesGreen]
        case .error:
            return [Color.red, Color.pink]
        case .disconnected:
            return [eton, alabaster.opacity(0.7)]
        }
    }
    
    private var microphoneIcon: String {
        switch client.state {
        case .connected:
            return "mic.fill"
        case .connecting:
            return "mic.badge.plus"
        case .error:
            return "mic.slash.fill"
        case .disconnected:
            return "mic"
        }
    }
    
    private var statusText: String {
        switch client.state {
        case .connected:
            return "Listening..."
        case .connecting:
            return "Connecting..."
        case .error:
            return "Connection Error"
        case .disconnected:
            return "Ready to chat"
        }
    }
    
    private var statusColor: Color {
        switch client.state {
        case .connected:
            return emerald
        case .connecting:
            return eton
        case .error:
            return .red
        case .disconnected:
            return alabaster.opacity(0.7)
        }
    }
    
    // MARK: - Actions
    private func toggle() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if client.state == .connected || client.state == .connecting {
                client.stop()
                isListening = false
            } else {
                client.start()
                isListening = true
            }
        }
    }
    
    private func sendTextMessage() {
        let messageText = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }
        
        // Add to conversation history
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            conversationHistory.append(messageText)
            textInput = ""
        }
        
        // Simulate AI response (in real implementation, this would come from WebRTC data channel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                conversationHistory.append("AI: I received your message. Voice responses will come through the WebRTC connection.")
            }
        }
    }
    
    private func addWelcomeMessage() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                conversationHistory.append("Hello! I'm Limi, your AI voice assistant. Tap the microphone to start our conversation.")
            }
        }
    }
    
    private func handleStateChange(_ newState: VoiceConnectionState) {
        switch newState {
        case .connected:
            withAnimation(.spring()) {
                conversationHistory.append("🎤 Voice connection established. I'm listening!")
            }
        case .error:
            withAnimation(.spring()) {
                conversationHistory.append("❌ Connection error. Please try again.")
            }
            isListening = false
        case .disconnected:
            isListening = false
            if !conversationHistory.isEmpty {
                withAnimation(.spring()) {
                    conversationHistory.append("Connection ended. Tap to reconnect.")
                }
            }
        case .connecting:
            currentTranscription = "Connecting to voice service..."
        }
    }
}

// MARK: - Conversation Bubble View
struct ConversationBubbleView: View {
    let message: String
    let isUser: Bool
    let isLive: Bool
    
    init(message: String, isUser: Bool, isLive: Bool = false) {
        self.message = message
        self.isUser = isUser
        self.isLive = isLive
    }
    
    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 40)
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                isUser ?
                                LinearGradient(
                                    colors: [Color(red: 0.31, green: 0.78, blue: 0.47), Color(red: 0.0, green: 0.5, blue: 0.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.15), Color.clear],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.5
                                    )
                            )
                    )
                    .shadow(
                        color: isUser ? Color(red: 0.31, green: 0.78, blue: 0.47).opacity(0.3) : Color.black.opacity(0.2),
                        radius: 6,
                        x: 0,
                        y: 2
                    )
                
                if isLive {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(Color(red: 0.31, green: 0.78, blue: 0.47))
                                .frame(width: 4, height: 4)
                                .scaleEffect(isLive ? 1.2 : 0.8)
                                .opacity(isLive ? 1.0 : 0.5)
                                .animation(
                                    .easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.2),
                                    value: isLive
                                )
                        }
                        
                        Text("Live")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(red: 0.31, green: 0.78, blue: 0.47))
                    }
                    .padding(.trailing, isUser ? 0 : 16)
                    .padding(.leading, isUser ? 16 : 0)
                }
            }
            
            if !isUser {
                Spacer(minLength: 40)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

// MARK: - Chat Bubble View
struct ChatBubbleView: View {
    let message: ChatMessage
    @State private var showMessage = false
    @State private var typingDots = ""
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Message bubble
                Text(message.isTyping ? "Thinking\(typingDots)" : message.content)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                message.isUser ?
                                LinearGradient(
                                    colors: [Color.purple, Color.blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.2), Color.clear],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .shadow(
                        color: message.isUser ? Color.purple.opacity(0.3) : Color.black.opacity(0.3),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
                
                // Timestamp
                Text(formatTime(message.timestamp))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 4)
            }
            
            if !message.isUser {
                Spacer(minLength: 50)
            }
        }
        .opacity(showMessage ? 1 : 0)
        .offset(y: showMessage ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                showMessage = true
            }
            
            if message.isTyping {
                startTypingAnimation()
            }
        }
    }
    
    private func startTypingAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            withAnimation(.easeInOut(duration: 0.3)) {
                if typingDots.count >= 3 {
                    typingDots = ""
                } else {
                    typingDots += "."
                }
            }
            
            // Stop after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                timer.invalidate()
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    VoiceView()
        .preferredColorScheme(.dark)
}
