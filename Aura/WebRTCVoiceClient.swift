//
//  WebRTCVoiceClient.swift
//  Aura
//
//  Created by Cascade on 02/09/2025.
//

import Foundation
import Combine
import AVFAudio
import WebRTC
import AVFoundation
import MediaPlayer

// MARK: - Connection State
enum VoiceConnectionState: String {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
    case error = "Error"
}

// MARK: - WebRTC Client
final class WebRTCVoiceClient: NSObject, ObservableObject {
    // Public
    @Published private(set) var state: VoiceConnectionState = .disconnected
    @Published private(set) var logs: [String] = []

    // Configure this to your backend base URL (must be HTTPS in production)
    private let backendBaseURL: URL
    // Optional webhook to forward conversation events
    private let webhookURL: URL? = URL(string: "https://dev.api.limitless-lighting.co.uk/api/aura/webhook")

    // RTC
    private var factory: RTCPeerConnectionFactory!
    private var peerConnection: RTCPeerConnection?
    private var localAudioTrack: RTCAudioTrack?
    private var dataChannel: RTCDataChannel?

    // Reconnection
    private var reconnectAttempts = 0
    private var maxReconnectAttempts = 3
    private var reconnectWorkItem: DispatchWorkItem?

    // Token
    private var ephemeralKey: String?

    // Queues
    private let workQueue = DispatchQueue(label: "webrtc.voice.client")

    // Notifications
    private var notificationObservers: [NSObjectProtocol] = []
    
    // Remote command center
    private var remoteCommandCenterConfigured = false
    private let commandCenter = MPRemoteCommandCenter.shared()

    init(backendBaseURL: URL) {
        self.backendBaseURL = backendBaseURL
        super.init()
        setupFactory()
        configureAudioSessionForLoudspeaker()
        registerForAudioSessionNotifications()
        setupNowPlaying(isActive: false)
    }

    deinit {
        removeAudioSessionNotifications()
    }

    // MARK: Public API
    func start() {
        guard state != .connecting && state != .connected else { return }
        state = .connecting
        log("Starting voice session…")
        postWebhook(event: "session_start", payload: [:])
        requestMicPermission { [weak self] granted in
            guard let self else { return }
            if !granted {
                self.fail("Microphone permission denied")
                return
            }
            self.configureAVAudioSession()
            self.configureRemoteCommandCenter()
            self.fetchEphemeralKey { [weak self] result in
                switch result {
                case .success(let key):
                    self?.ephemeralKey = key
                    self?.createPeerAndConnect()
                case .failure(let error):
                    self?.fail("Token error: \(error.localizedDescription)")
                }
            }
        }
    }

    func stop() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        ephemeralKey = nil
        tearDownPeer()
        state = .disconnected
        log("Stopped voice session")
        postWebhook(event: "session_stop", payload: [:])
        teardownRemoteCommandCenter()
        setupNowPlaying(isActive: false)
        deactivateAudioSession()
    }

    // MARK: Setup
    private func setupFactory() {
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
    }

    private func configureAVAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Enhanced audio session configuration with better error handling
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP])
            try session.setActive(true, options: [])
            log("Audio session configured successfully")
        } catch let error as NSError {
            log("Audio session error: \(error.localizedDescription) (code: \(error.code))")
            // Attempt recovery with fallback configuration
            do {
                try session.setCategory(.playAndRecord, options: [.defaultToSpeaker])
                try session.setActive(true, options: [])
                log("Audio session configured with fallback settings")
            } catch {
                log("Audio session fallback failed: \(error.localizedDescription)")
            }
        }
    }

    private func configureAudioSessionForLoudspeaker() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Failed to set audio session category to loudspeaker: \(error)")
        }
    }

    // MARK: Audio Session Observing & Route Handling
    private func registerForAudioSessionNotifications() {
        let center = NotificationCenter.default
        let obs1 = center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleAudioSessionInterruption(note)
        }
        let obs2 = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleAudioRouteChange(note)
        }
        let obs3 = center.addObserver(forName: AVAudioSession.mediaServicesWereLostNotification, object: nil, queue: .main) { [weak self] _ in
            self?.log("Audio media services were lost — will attempt to restore")
        }
        let obs4 = center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.log("Audio media services were reset — reconfiguring session")
            self?.reconfigureAudioSessionAfterReset()
        }
        notificationObservers.append(contentsOf: [obs1, obs2, obs3, obs4])
    }

    private func removeAudioSessionNotifications() {
        let center = NotificationCenter.default
        for obs in notificationObservers { center.removeObserver(obs) }
        notificationObservers.removeAll()
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            log("🔇 Audio interruption began - pausing microphone")
            // Gracefully handle interruption without full shutdown
            postWebhook(event: "audio_interrupted", payload: ["type": "began"])
        case .ended:
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            log("🔊 Audio interruption ended, options=\(options)")
            
            // Enhanced recovery logic
            if options.contains(.shouldResume) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.recoverFromAudioInterruption()
                }
            } else {
                log("Audio interruption ended but should not resume automatically")
            }
            postWebhook(event: "audio_interrupted", payload: ["type": "ended", "shouldResume": options.contains(.shouldResume)])
        @unknown default:
            break
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
        log("🔀 Route change: reason=\(reason.rawValue)")
        updateAudioRouteForCurrentOutputs()
    }

    private func reconfigureAudioSessionAfterReset() {
        // Re-apply category and activation, then update route.
        configureAudioSessionForLoudspeaker()
        updateAudioRouteForCurrentOutputs()
    }

    private func activateAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true, options: [])
            updateAudioRouteForCurrentOutputs()
            log("Audio session reactivated successfully")
        } catch {
            log("Audio session reactivate error: \(error.localizedDescription)")
            // Attempt recovery without throwing error
            recoverFromAudioSessionError()
        }
    }
    
    private func recoverFromAudioInterruption() {
        log("Attempting recovery from audio interruption")
        configureAVAudioSession()
        updateAudioRouteForCurrentOutputs()
        
        // Recreate audio track if connection is still active
        if state == .connected, let pc = peerConnection {
            recreateLocalAudioTrack(for: pc)
        }
    }
    
    private func recoverFromAudioSessionError() {
        log("Attempting recovery from audio session error")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.configureAVAudioSession()
        }
    }
    
    private func recreateLocalAudioTrack(for peerConnection: RTCPeerConnection) {
        // Remove old track
        if let oldTrack = localAudioTrack {
            let senders = peerConnection.senders.filter { $0.track?.trackId == oldTrack.trackId }
            for sender in senders {
                peerConnection.removeTrack(sender)
            }
        }
        
        // Create and add new track
        let newTrack = createLocalAudioTrack()
        localAudioTrack = newTrack
        peerConnection.add(newTrack, streamIds: ["stream0"])
        log("Local audio track recreated successfully")
    }

    private func updateAudioRouteForCurrentOutputs() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        let hasHeadphonesOrBT = outputs.contains { out in
            switch out.portType {
            case .headphones, .headsetMic, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                return true
            default:
                return false
            }
        }

        do {
            if hasHeadphonesOrBT {
                // Respect external routes; no override.
                try session.overrideOutputAudioPort(.none)
                log("🔈 Using external audio route: \(outputs.map { $0.portType.rawValue }.joined(separator: ", "))")
            } else {
                // Ensure loudspeaker when on device only.
                try session.overrideOutputAudioPort(.speaker)
                log("📢 Forced output to loudspeaker")
            }
        } catch {
            log("Audio route override error: \(error.localizedDescription)")
        }
    }

    // MARK: Mic
    private func requestMicPermission(_ completion: @escaping (Bool) -> Void) {
        let session = AVAudioSession.sharedInstance()
        
        log("Checking microphone permission status: \(session.recordPermission.rawValue)")
        
        switch session.recordPermission {
        case .granted:
            log("Microphone permission already granted")
            completion(true)
        case .denied:
            log("Microphone permission denied - user needs to enable in Settings")
            postWebhook(event: "mic_permission_denied", payload: [:])
            completion(false)
        case .undetermined:
            log("Requesting microphone permission from user")
            session.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.log("Microphone permission request result: \(granted)")
                    self?.postWebhook(event: "mic_permission_requested", payload: ["granted": granted])
                    completion(granted)
                }
            }
        @unknown default:
            log("Unknown microphone permission state")
            completion(false)
        }
    }

    private func createLocalAudioTrack() -> RTCAudioTrack {
        let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let track = factory.audioTrack(with: audioSource, trackId: "ARDAMSa0")
        return track
    }

    // MARK: Peer
    private func createPeerAndConnect() {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]) // Add TURN in production
        ]
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        self.peerConnection = pc

        // Local audio
        let track = createLocalAudioTrack()
        self.localAudioTrack = track
        // Add the microphone track to the peer connection
        _ = pc?.add(track, streamIds: ["stream0"])

        // Create data channel for JSON/text events from OpenAI
        let dcConfig = RTCDataChannelConfiguration()
        dcConfig.isOrdered = true
        if let dc = pc?.dataChannel(forLabel: "oai-events", configuration: dcConfig) {
            dc.delegate = self
            self.dataChannel = dc
            log("DataChannel created: label=\(dc.label)")
        } else {
            log("DataChannel creation failed")
        }

        // Offer
        let offerConstraints = RTCMediaConstraints(mandatoryConstraints: [
            "OfferToReceiveAudio": "true",
            "VoiceActivityDetection": "true"
        ], optionalConstraints: nil)
        pc?.offer(for: offerConstraints) { [weak self] sdp, error in
            guard let self else { return }
            if let error {
                self.fail("Offer error: \(error.localizedDescription)")
                return
            }
            guard let sdp else {
                self.fail("Offer error: nil SDP")
                return
            }
            pc?.setLocalDescription(sdp) { [weak self] err in
                if let err { self?.fail("setLocalDescription error: \(err.localizedDescription)"); return }
                self?.sendOfferToBackend(offer: sdp)
            }
        }
    }

    private func tearDownPeer() {
        log("Tearing down peer connection gracefully")
        
        // Gracefully close data channel
        if let dc = dataChannel {
            dc.delegate = nil
            if dc.readyState == .open {
                dc.close()
            }
            dataChannel = nil
        }
        
        // Remove local audio track before closing connection
        if let track = localAudioTrack, let pc = peerConnection {
            let senders = pc.senders.filter { $0.track?.trackId == track.trackId }
            for sender in senders {
                pc.removeTrack(sender)
            }
        }
        localAudioTrack = nil
        
        // Close peer connection
        if let pc = peerConnection {
            pc.close()
        }
        peerConnection = nil
        
        log("Peer connection torn down successfully")
    }

    // MARK: Backend
    private struct TokenResponse: Decodable { let key: String }
    private struct SDPObject: Codable { let type: String; let sdp: String }
    private struct OfferRequest: Codable { let key: String; let sdp: String }
    private struct AnswerResponse: Decodable { let sdp: String }
    private struct IceCandidatePayload: Codable {
        let key: String
        let candidate: String
        let sdpMid: String?
        let sdpMLineIndex: Int32
    }

    private func fetchEphemeralKey(completion: @escaping (Result<String, Error>) -> Void) {
        let url = backendBaseURL.appendingPathComponent("/api/aura/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Log outgoing request
        log("➡️ Request: GET \(url.absoluteString)")
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            log("➡️ Headers: \(headers)")
        }

        URLSession.shared.dataTask(with: request) { data, resp, err in
            // Log response status and headers
            if let http = resp as? HTTPURLResponse {
                self.log("⬅️ Status: \(http.statusCode) from \(url.host ?? "?")")
                self.log("⬅️ Response Headers: \(http.allHeaderFields)")
            }

            if let err {
                self.log("❌ Token request error: \(err.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(err)) }
                return
            }
            guard let data else {
                self.log("❌ Token response had empty body")
                DispatchQueue.main.async { completion(.failure(NSError(domain: "token", code: -1))) }
                return
            }

            // Log raw body
            if let body = String(data: data, encoding: .utf8) {
                self.log("⬅️ Body: \(body)")
            }

            do {
                let t = try JSONDecoder().decode(TokenResponse.self, from: data)
                self.log("✅ Parsed token key: \(t.key)")
                DispatchQueue.main.async { completion(.success(t.key)) }
            } catch {
                self.log("❌ Token decode error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    private func sendOfferToBackend(offer: RTCSessionDescription) {
        guard let key = ephemeralKey else { fail("Missing ephemeral key"); return }
        // OpenAI Realtime WebRTC expects POST to /v1/realtime?model=...
        // with headers: Authorization: Bearer <ephemeral-key>, OpenAI-Beta: realtime=v1, Content-Type: application/sdp
        // and raw SDP in the body, returning SDP answer as text.
        let model = "gpt-realtime"
        guard let url = URL(string: "https://api.openai.com/v1/realtime?model=\(model)") else { fail("Invalid OpenAI URL"); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.setValue("application/sdp", forHTTPHeaderField: "Accept")
        request.httpBody = offer.sdp.data(using: .utf8)

        // Log outgoing request
        log("➡️ Request: POST \(url.absoluteString) [application/sdp] body=\(offer.sdp.count) chars\n📝 SDP (first 200): \(String(offer.sdp.prefix(200)))…")

        URLSession.shared.dataTask(with: request) { [weak self] data, resp, err in
            guard let self else { return }
            if let http = resp as? HTTPURLResponse {
                self.log("⬅️ Status: \(http.statusCode) from \(url.host ?? "?")")
                self.log("⬅️ Response Headers: \(http.allHeaderFields)")
            }
            if let err { self.fail("Offer POST error: \(err.localizedDescription)"); return }
            guard let data else { self.fail("Empty answer body"); return }
            // Try to decode as text SDP first; if it's JSON, log the error JSON explicitly
            if let contentType = (resp as? HTTPURLResponse)?.allHeaderFields["Content-Type"] as? String, contentType.contains("application/json"),
               let json = String(data: data, encoding: .utf8) {
                self.fail("OpenAI error JSON: \(json)")
                return
            }
            guard let answerSDP = String(data: data, encoding: .utf8) else {
                self.fail("Answer not UTF-8 text")
                return
            }
            self.log("⬅️ Answer SDP size=\(answerSDP.count) chars\n📝 SDP (first 200): \(String(answerSDP.prefix(200)))…")
            let remote = RTCSessionDescription(type: .answer, sdp: answerSDP)
            self.peerConnection?.setRemoteDescription(remote) { [weak self] err in
                if let err { self?.fail("setRemoteDescription error: \(err.localizedDescription)"); return }
                DispatchQueue.main.async {
                    self?.state = .connected
                    self?.reconnectAttempts = 0
                    self?.log("Connected")
                    self?.postWebhook(event: "connected", payload: [:])
                    self?.setupNowPlaying(isActive: true)
                }
            }
        }.resume()
    }

    private func postLocalIceCandidate(_ candidate: RTCIceCandidate) {
        // No-op for OpenAI Realtime WebRTC — ICE trickling handled internally by the peer connection
        log("ICE candidate generated (not posted): sdpMid=\(candidate.sdpMid ?? "nil"), index=\(candidate.sdpMLineIndex)")
    }

    // MARK: Logging
    private func log(_ message: String) {
        DispatchQueue.main.async {
            let line = "[\(Date())] \(message)"
            self.logs.append(line)
            // Also mirror to Xcode console
            print(line)
        }
    }

    // MARK: Webhook Forwarding
    private func postWebhook(event: String, payload: [String: Any]) {
        guard let webhookURL else {
            log("Webhook skipped: webhookURL is nil")
            return
        }
        var body: [String: Any] = [
            "event": event,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "payload": payload
        ]
        // Attach app-side context if helpful
        body["state"] = state.rawValue

        do {
            let data = try JSONSerialization.data(withJSONObject: body, options: [])
            var req = URLRequest(url: webhookURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.httpBody = data
            // Log outgoing request
            if let jsonString = String(data: data, encoding: .utf8) {
                log("➡️ Webhook Request: POST \(webhookURL.absoluteString)\nHeaders: \(req.allHTTPHeaderFields ?? [:])\nBody: \(jsonString)")
            } else {
                log("➡️ Webhook Request: POST \(webhookURL.absoluteString) [body=\(data.count) bytes]")
            }

            URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
                // Log response status and headers
                if let http = resp as? HTTPURLResponse {
                    self?.log("⬅️ Webhook Response Status: \(http.statusCode) from \(webhookURL.host ?? "?")")
                    self?.log("⬅️ Webhook Response Headers: \(http.allHeaderFields)")
                }

                if let err {
                    self?.log("❌ Webhook error: \(err.localizedDescription)")
                    return
                }
                guard let data else {
                    self?.log("❌ Webhook response had empty body")
                    return
                }
                if let body = String(data: data, encoding: .utf8) {
                    self?.log("⬅️ Webhook Body: \(body)")
                } else {
                    self?.log("⬅️ Webhook Body (\(data.count) bytes)")
                }
            }.resume()
        } catch {
            log("Webhook JSON encode error: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        log("FAILURE: \(message)")
        
        DispatchQueue.main.async {
            // Only change state if not already in error state
            if self.state != .error {
                self.state = .error
            }
        }
        
        postWebhook(event: "error", payload: ["message": message, "reconnect_attempts": reconnectAttempts])
        
        // Only schedule reconnect if we haven't exceeded max attempts
        if reconnectAttempts < maxReconnectAttempts {
            scheduleReconnect()
        } else {
            log("Max reconnect attempts reached - not scheduling further reconnects")
            // Deactivate audio session to prevent resource leaks
            deactivateAudioSession()
        }
    }
    
    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            log("Audio session deactivated")
        } catch {
            log("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Now Playing & Remote Commands
    private func setupNowPlaying(isActive: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "Limi AI Assistant",
            MPMediaItemPropertyArtist: isActive ? "Listening & Speaking" : "Idle",
        ]
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommandCenter() {
        guard !remoteCommandCenterConfigured else { return }
        remoteCommandCenterConfigured = true

        let cc = commandCenter
        cc.playCommand.isEnabled = true
        cc.pauseCommand.isEnabled = true
        cc.stopCommand.isEnabled = true

        cc.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.start()
            self.setupNowPlaying(isActive: true)
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.stop()
            self.setupNowPlaying(isActive: false)
            return .success
        }
        cc.stopCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.stop()
            self.setupNowPlaying(isActive: false)
            return .success
        }
    }

    private func teardownRemoteCommandCenter() {
        guard remoteCommandCenterConfigured else { return }
        remoteCommandCenterConfigured = false

        let cc = commandCenter
        cc.playCommand.removeTarget(nil)
        cc.pauseCommand.removeTarget(nil)
        cc.stopCommand.removeTarget(nil)
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            log("Max reconnect attempts (\(maxReconnectAttempts)) reached - stopping")
            fail("Connection failed after \(maxReconnectAttempts) attempts")
            return
        }
        
        // Don't reconnect if already connected or connecting
        guard state != .connected && state != .connecting else {
            log("Skipping reconnect - already connected/connecting")
            return
        }
        
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Cap at 30s
        log("Reconnecting in \(Int(delay))s… (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")
        
        reconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Ensure audio session is still active before reconnecting
            self.configureAVAudioSession()
            
            self.tearDownPeer()
            
            // Add small delay before creating new connection
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.createPeerAndConnect()
            }
        }
        reconnectWorkItem = work
        workQueue.asyncAfter(deadline: .now() + delay, execute: work)
        
        postWebhook(event: "reconnect_scheduled", payload: ["attempt": reconnectAttempts, "delay": delay])
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCVoiceClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        log("Signaling state: \(stateChanged.rawValue)")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        log("ICE state: \(newState.rawValue)")
        postWebhook(event: "ice_state_change", payload: ["state": newState.rawValue])
        
        switch newState {
        case .connected, .completed:
            log("ICE connection established successfully")
            reconnectAttempts = 0 // Reset on successful connection
        case .disconnected:
            log("ICE connection disconnected - attempting recovery")
            // Don't immediately reconnect, try to recover first
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                if self.peerConnection?.iceConnectionState == .disconnected {
                    self.scheduleReconnect()
                }
            }
        case .failed:
            log("ICE connection failed - scheduling reconnect")
            scheduleReconnect()
        case .checking:
            log("ICE connection checking...")
        case .new:
            log("ICE connection new")
        case .closed:
            log("ICE connection closed")
        @unknown default:
            log("ICE connection unknown state: \(newState.rawValue)")
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        log("ICE gathering: \(newState.rawValue)")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        postLocalIceCandidate(candidate)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        log("DataChannel opened by remote: label=\(dataChannel.label)")
        self.dataChannel = dataChannel
        dataChannel.delegate = self
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        // Remote audio will be played automatically by WebRTC when audio track is received and AVAudioSession is active.
        log("Remote track added: \(rtpReceiver.track?.kind ?? "?")")
    }
}

// MARK: - RTCDataChannelDelegate
extension WebRTCVoiceClient: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        log("DataChannel state=\(dataChannel.readyState.rawValue) label=\(dataChannel.label)")
        postWebhook(event: "datachannel_state", payload: ["state": dataChannel.readyState.rawValue, "label": dataChannel.label])
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if buffer.isBinary {
            if let text = String(data: buffer.data, encoding: .utf8) {
                log("📩 DataChannel binary->text: \(text)")
                postWebhook(event: "oai_event", payload: ["raw_text": text, "format": "binary->text"])
            } else {
                log("📩 DataChannel received binary message (\(buffer.data.count) bytes)")
                postWebhook(event: "oai_event_binary", payload: ["bytes": buffer.data.count])
            }
        } else {
            let text = String(decoding: buffer.data, as: UTF8.self)
            log("📩 DataChannel text: \(text)")
            postWebhook(event: "oai_event", payload: ["raw_text": text, "format": "text"])
        }
    }
}
