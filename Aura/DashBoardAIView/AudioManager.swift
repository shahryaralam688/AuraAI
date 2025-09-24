


//
//  AudioManager.swift
//  Aura
//
//  Created by Mac Mini on 18/09/2025.
//


import AVFoundation

class AudioManager: ObservableObject {
    private var audioEngine = AVAudioEngine()
    @Published var currentVolume: CGFloat = 0.0
    
    init() {
        start()
    }
    
    func start() {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            let level = buffer.averagePower()
            DispatchQueue.main.async {
                self.currentVolume = max(0, CGFloat(level))
            }
        }
        
        try? audioEngine.start()
    }
}

extension AVAudioPCMBuffer {
    func averagePower() -> Float {
        guard let channelData = self.floatChannelData?[0] else { return 0 }
        let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: Int(frameLength)))
        let rms = sqrt(channelDataArray.map { $0 * $0 }.reduce(0, +) / Float(frameLength))
        let avgPower = 20 * log10(rms)
        let normalized = (avgPower + 50) / 50 // Normalize 0...1
        return max(0, normalized)
    }
}
