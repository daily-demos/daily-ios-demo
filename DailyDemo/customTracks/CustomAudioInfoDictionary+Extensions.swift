import Daily

// These are extensions meant for use on `ParticipantMedia.customAudio`.

extension Dictionary where Key == String, Value == ParticipantAudioInfo {
    /// The names of every custom audio track we could subscribe to.
    ///
    /// All of them, not just the first. Custom *video* subscribes to a single
    /// track because the demo shows one remote participant at a time, but audio
    /// from everyone should be audible at once, whoever is on screen.
    ///
    /// Sorted so that repeated calls compare equal, which is what lets the caller
    /// tell "nothing changed" from "there is a new track".
    var subscribableTrackNames: [String] {
        self.filter { (_, trackInfo) in
            [.loading, .playable, .receivable].contains(trackInfo.state)
        }.keys.sorted()
    }
}
