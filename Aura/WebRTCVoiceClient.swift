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
    private let webhookURL: URL? = URL(string: "https://placing-meets-wage-organisations.trycloudflare.com/api/aura/webhook")

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

    init(backendBaseURL: URL) {
        self.backendBaseURL = backendBaseURL
        super.init()
        setupFactory()
        configureAudioSessionForLoudspeaker()
        registerForAudioSessionNotifications()
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
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
            log("Audio session configured")
        } catch {
            log("Audio session error: \(error.localizedDescription)")
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
            log("🔇 Audio interruption began")
        case .ended:
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            log("🔊 Audio interruption ended, options=\(options)")
            // Reactivate if needed
            activateAudioSessionIfNeeded()
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
            try session.setActive(true)
            updateAudioRouteForCurrentOutputs()
        } catch {
            log("Audio session reactivate error: \(error.localizedDescription)")
        }
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
        switch session.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            session.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        @unknown default:
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
        dataChannel?.delegate = nil
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.close()
        peerConnection = nil
        localAudioTrack = nil
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
        request.httpMethod = "GET"
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
        guard let webhookURL else { return }
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
            req.httpBody = data
            URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
                if let err { self?.log("Webhook error: \(err.localizedDescription)") }
            }.resume()
        } catch {
            log("Webhook JSON encode error: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async {
            self.state = .error
            self.logs.append("ERROR: \(message)")
        }
        postWebhook(event: "error", payload: ["message": message])
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else { return }
        reconnectAttempts += 1
        let delay = pow(2.0, Double(reconnectAttempts)) // 2,4,8s
        log("Reconnecting in \(Int(delay))s… (attempt \(reconnectAttempts))")
        reconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.tearDownPeer()
            self?.createPeerAndConnect()
        }
        reconnectWorkItem = work
        workQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

// MARK: - DataChannel helpers
private extension WebRTCVoiceClient {
    func sendJSONOnDataChannel(_ object: [String: Any]) {
        guard let dc = self.dataChannel else {
            log("⚠️ Tried to send on data channel but it's nil")
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [])
            let ok = dc.sendData(RTCDataBuffer(data: data, isBinary: false))
            log("➡️ DataChannel send (json, \(data.count) bytes) ok=\(ok)")
        } catch {
            log("❌ DataChannel JSON encode error: \(error.localizedDescription)")
        }
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
        if newState == .failed || newState == .disconnected { scheduleReconnect() }
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
        
        // When the data channel is open, request RTP Opus output so audio plays via the remote WebRTC track
        if dataChannel.readyState == .open {
            let update: [String: Any] = [
                "type": "session.update",
                "session": [
                    "voice": "verse",
                    "output_audio_format": "opus"
                ]
            ]
            sendJSONOnDataChannel(update)
        }
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
