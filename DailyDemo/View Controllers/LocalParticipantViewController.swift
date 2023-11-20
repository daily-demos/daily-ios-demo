import UIKit

import Combine

import Daily

class LocalParticipantViewController: UIViewController {
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

    private(set) var videoSize: CGSize = .zero

    var videoSizePublisher: AnyPublisher<CGSize, Never> {
        self.videoSizeSubject.eraseToAnyPublisher()
    }

    private let videoSizeSubject: CurrentValueSubject<CGSize, Never> = .init(
        .zero
    )

    @IBOutlet private weak var activeSpeakerImageView: UIImageView!
    @IBOutlet private weak var label: UILabel!
    @IBOutlet private weak var cameraPreviewView: CameraPreviewView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.cameraPreviewView.delegate = self
    }

    // MARK: - Handlers

    private func didUpdate(isActiveSpeaker: Bool) {
        self.activeSpeakerImageView.isHidden = !isActiveSpeaker
    }

    private func didUpdate(participant: Participant?) {
        let cameraTrack = participant?.media?.camera.track
        let username = participant?.info.username

        let hasVideo = cameraTrack != nil

        // Assign name to label:
        self.label.text = username ?? "Guest"

        // Hide label if there's video to play:
        self.label.isHidden = hasVideo

        // Hide video view if there's no video to play:
        self.cameraPreviewView.isHidden = !hasVideo
    }
}

extension LocalParticipantViewController: CameraPreviewViewDelegate {
    func cameraPreviewView(_ cameraPreviewView: CameraPreviewView, didChangeVideoSize size: CGSize) {
        self.videoSizeSubject.send(size)
    }
}
