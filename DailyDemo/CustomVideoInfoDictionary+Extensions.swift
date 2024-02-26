import Daily

// These are extensions meant for use on `ParticipantMedia.customVideo`.

extension Dictionary where Key == String, Value == ParticipantVideoInfo {
    var firstPlayableTrack: VideoTrack? {
        self.first { (trackName, trackInfo) in
            trackInfo.track != nil
        }?.value.track
    }
    
    var firstSubscribableTrackName: String? {
        self.first { (trackName, trackInfo) in
            [.loading, .playable, .receivable].contains(trackInfo.state)
        }?.key
    }
}
