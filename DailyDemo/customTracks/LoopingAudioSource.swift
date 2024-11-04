import Foundation
import Daily
import AVFoundation

class LoopingAudioSource: CustomAudioSource {
    
    private let dispatchQueue = DispatchQueue(label: "co.daily.DailyDemo.LoopingAudioSource")
    private var frameConsumer: CustomAudioFrameConsumer?
    private let microphoneAudioStreamer = MicrophoneAudioStreamer.init()
    
    func attachFrameConsumer(_ frameConsumer: any Daily.CustomAudioFrameConsumer) {
        dispatchQueue.async {
            self.frameConsumer = frameConsumer
            self.microphoneAudioStreamer.startStreaming(frameConsumer: frameConsumer)
        }
    }
    
    func detachFrameConsumer() {
        dispatchQueue.async {
            self.microphoneAudioStreamer.stopStreaming()
            self.frameConsumer = nil
        }
    }
    
}

class MicrophoneAudioStreamer {
    
    private var audioEngine = AVAudioEngine()
    
    func startStreaming(frameConsumer: CustomAudioFrameConsumer) {
        let inputNode = audioEngine.inputNode
        
        // 48 kHz, mono (1 channel)
        let sampleRate: Double = 48000.0
        let channelCount: AVAudioChannelCount = 1
        let inputFormat = AVAudioFormat.init(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channelCount, interleaved: true)!
        
        // Install a tap on the input node to capture microphone audio frames
        let frameLength: AVAudioFrameCount = 480 // 10 ms of audio at 48 kHz

        inputNode.installTap(onBus: 0, bufferSize: frameLength, format: inputFormat) { [weak self] (buffer, time) in
            guard self != nil else { return }
            
            // Only for testing that we are sending the right amount
            //let bytesPerFrame = inputFormat.streamDescription.pointee.mBytesPerFrame
            //print("bytesPerFrame \(bytesPerFrame)")
            
            // Send data to Daily
            frameConsumer.sendFrame(buffer)
        }
        
        do {
            // Start the audio engine
            try audioEngine.start()
            print("Microphone audio streaming started at \(sampleRate) Hz.")
        } catch {
            print("Error starting audio engine: \(error)")
        }
    }

    
    func stopStreaming() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        print("Microphone audio streaming stopped.")
    }
}

