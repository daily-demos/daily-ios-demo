import Daily
import AVFoundation

/// A custom video source that loops a video file indefinitely.
/// It automatically starts playing when the custom video track is added with `addCustomVideoTrack()`.
/// It automatically pauses when the custom video track is removed or replaced with
/// `removeCustomVideoTrack()` or `updateCustomVideoTrack()` respectively.
class LoopingVideoSource: CustomVideoSource {
    
    // MARK: - Public
    
    /// Method required by `CustomVideoSource`
    func attachFrameConsumer(_ frameConsumer: CustomVideoFrameConsumer) {
        dispatchQueue.async {
            self.frameConsumer = frameConsumer
            self.resume()
        }
    }
    
    /// Method required by `CustomVideoSource`
    func detachFrameConsumer() {
        dispatchQueue.async {
            self.pause()
            self.frameConsumer = nil
        }
    }
    
    // MARK: - Private Helpers
    
    private let dispatchQueue = DispatchQueue(label: "co.daily.DailyDemo.LoopingVideoSource")
    private var player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var currentPlayerItemObservation: NSKeyValueObservation?
    private var currentPlayerItemOutput: AVPlayerItemVideoOutput?
    private var frameConsumer: CustomVideoFrameConsumer?
    private var displayLink: CADisplayLink?
    private var playerStoppedObservation: NSKeyValueObservation?
    
    private func resume() {
        if self.player == nil {
            setup()
        }
        
        guard let player else { return }
        
        // Attach a workaround mechanism for the player unexpectedly stalling
        // when leaving a call.
        // I have no explanation for why this stalling occurs :/
        self.playerStoppedObservation = Self.attachWorkaroundForPlayerStallingOnLeave(
            player: player
        )
        
        DispatchQueue.main.async {
            player.play()
        }
    }
    
    private func pause() {
        guard let player else { return }
        
        // Detach the workaround mechanism for the player unexpectedly stalling.
        // We're about to intentionally pause the player.
        self.playerStoppedObservation = nil
        
        DispatchQueue.main.async {
            player.pause()
        }
    }
    
    private func setup() {
        let templatePlayerItem = Self.createTemplatePlayerItem()
        let loopingPlayer = Self.createLoopingPlayer(
            templatePlayerItem: templatePlayerItem
        )
        self.player = loopingPlayer.player
        self.playerLooper = loopingPlayer.playerLooper
        
        // The looping player plays a sequence of replicas of the template
        // player item. Listen for each time the currently-playing item changes
        // to a new replica, and start getting output from that item.
        self.currentPlayerItemObservation = loopingPlayer.player.observe(\.currentItem) { [weak self] player, _ in
            guard let self, let playerItem = player.currentItem else { return }
            self.currentPlayerItemOutput = Self.wireUpCurrentPlayerItemOutput(
                playerItem: playerItem
            )
        }
        
        // Check continually for newly-available frames from the current player
        // item.
        self.displayLink = CADisplayLink(
            target: self,
            selector: #selector(checkForNewlyAvailableFrame)
        )
        self.displayLink?.add(to: .main, forMode: .common)
    }
    
    private static func createTemplatePlayerItem() -> AVPlayerItem {
        let url = Bundle.main.url(forResource: "movie", withExtension: "mp4")!
        return AVPlayerItem(url: url)
    }
    
    private static func createLoopingPlayer(
        templatePlayerItem: AVPlayerItem
    ) -> (player: AVQueuePlayer, playerLooper: AVPlayerLooper) {
        let player = AVQueuePlayer()
        player.isMuted = true
        let playerLooper = AVPlayerLooper(
            player: player,
            templateItem: templatePlayerItem
        )
        return (player, playerLooper)
    }
    
    private static func wireUpCurrentPlayerItemOutput(
        playerItem: AVPlayerItem
    ) -> AVPlayerItemVideoOutput {
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ])
        playerItem.add(output)
        return output
    }
    
    private static func attachWorkaroundForPlayerStallingOnLeave(
        player: AVQueuePlayer
    ) -> NSKeyValueObservation {
        player.observe(\.rate, options: [.old, .new]) { player, change in
            guard
                let oldRate = change.oldValue,
                let newRate = change.newValue
            else {
                // This should be impossible
                return
            }
            if oldRate > 0 && newRate == 0 {
                // Restart stalled player
                player.play()
            }
        }
    }
    
    // Convert a specific time in the current video loop to the "overall" time
    // (i.e. the amount of time that has elapsed since the video started
    // playing).
    private static func convertCurrentLoopTimeToOverallTimeNs(
        currentLoopTime: CMTime,
        numberOfPriorLoops: Int,
        loopDuration: CMTime
    ) -> Int64 {
        return (
            currentLoopTime.toNs() +
            Int64(numberOfPriorLoops) * loopDuration.toNs()
        )
    }
    
    // MARK: - AVPlayerItemOutputPullDelegate
    
    @objc func checkForNewlyAvailableFrame() {
        guard
            let frameConsumer,
            let currentPlayerItemOutput,
            let playerItem = player?.currentItem,
            let playerLooper
        else {
            return
        }
        
        let itemTime = currentPlayerItemOutput.itemTime(
            forHostTime: CACurrentMediaTime()
        )
        
        guard
            currentPlayerItemOutput.hasNewPixelBuffer(
                forItemTime: itemTime
            ),
            let buffer = currentPlayerItemOutput.copyPixelBuffer(
                forItemTime: itemTime,
                itemTimeForDisplay: nil
            )
        else {
            return
        }
        
        // Note: here we use playerItem.duration since we can assume all 
        // player items are the same duration (they're copies of the template).
        // Ideally we could use the template item directly, but its duration
        // isn't ever loaded since it's never played.
        let overallTimeNs = Self.convertCurrentLoopTimeToOverallTimeNs(
            currentLoopTime: itemTime,
            numberOfPriorLoops: playerLooper.loopCount,
            loopDuration: playerItem.duration
        )
        
        frameConsumer.sendFrame(buffer, withTimeStampNs: overallTimeNs)
    }
}

extension CMTime {
    func toNs() -> Int64 {
        var selfWithNsTimescale = self
        
        // Convert timescale to nanoseconds, if needed.
        if self.timescale != 1_000_000_000 {
            selfWithNsTimescale = self.convertScale(
                1_000_000_000,
                method: .default
            )
        }
        
        return selfWithNsTimescale.value
    }
}
