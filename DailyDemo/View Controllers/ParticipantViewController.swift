import UIKit

import Combine

import Daily

class ParticipantViewController: UIViewController {
    var isActiveSpeaker: Bool = false {
        didSet {
            self.didUpdate(isActiveSpeaker: self.isActiveSpeaker)
        }
    }

    var isViewHidden: Bool = false {
        didSet {
            UIView.animate(withDuration: 0.25, delay: 0.0) {
                self.view.isHidden = self.isViewHidden
            }
        }
    }

    var participant: Participant? = nil {
        didSet {
            if self.participant != oldValue {
                self.didUpdate(participant: self.participant)
            }
        }
    }

    var callClient: CallClient?

    private(set) var videoSize: CGSize = .zero

    var videoSizePublisher: AnyPublisher<CGSize, Never> {
        self.videoSizeSubject.eraseToAnyPublisher()
    }

    private let videoSizeSubject: CurrentValueSubject<CGSize, Never> = .init(
        .zero
    )

    @IBOutlet private weak var activeSpeakerImageView: UIImageView!
    @IBOutlet private weak var label: UILabel!
    @IBOutlet private weak var videoView: VideoView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.videoView.delegate = self
    }

    // MARK: - Handlers

    private func didUpdate(isActiveSpeaker: Bool) {
        self.activeSpeakerImageView.isHidden = !isActiveSpeaker
    }

    private func didUpdate(participant: Participant?) {
        let cameraTrack = participant?.media?.camera.track
        let screenTrack = participant?.media?.screenVideo.track
        let videoTrack = screenTrack ?? cameraTrack
        let username = participant?.info.username

        let isScreenTrack = screenTrack != nil
        let hasVideo = videoTrack != nil

        // Assign name to label:
        self.label.text = username ?? "Guest"

        // Hide label if there's video to play:
        self.label.isHidden = hasVideo

        // Assign track to video view:
        self.videoView.track = videoTrack

        // Hide video view if there's no video to play:
        self.videoView.isHidden = !hasVideo

        // Change video's scale mode based on track type:
        self.videoView.videoScaleMode = isScreenTrack ? .fit : .fill

        // Don't change subscriptions for local view controller otherwise
        // it conflicts with the changes from the remote one.
        if let participant = participant, !participant.info.isLocal {
            self.updateSubscriptions(activeParticipant: participant)
        }
    }

    private func updateSubscriptions(activeParticipant: Participant) {
        guard let callClient = self.callClient else {
            return
        }

        // Reduce video quality of remote participants not currently displayed:
        //
        // This is done by moving participants from one pre-defined profile to another,
        // rather than changing each participant's settings individually:
        callClient.updateSubscriptions(
            forParticipants: .set([
                // Move the now-shown participant to the `.activeRemote` profile:
                activeParticipant.id: .set(
                    profile: .set(.activeRemote)
                ),
            ]),
            participantsWithProfiles: .set([
                // Move all previous "active remote" participants into "base" profile:
                .activeRemote: .set(
                    profile: .set(.base)
                ),
            ]),
            completion: nil
        )
    }
}

extension ParticipantViewController: VideoViewDelegate {
    func videoView(_ videoView: VideoView, didChangeVideoSize size: CGSize) {
        self.videoSizeSubject.send(size)
    }
}
