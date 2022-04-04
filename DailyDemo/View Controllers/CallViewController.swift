import UIKit

import AVFoundation
import Combine

import Logging

import Daily

func dumped<T>(_ value: T) -> String {
    var string = ""
    Swift.dump(value, to: &string)
    return string
}

class CallViewController: UIViewController {
    @IBOutlet private weak var cameraInputButton: UIButton!
    @IBOutlet private weak var microphoneInputButton: UIButton!
    @IBOutlet private weak var cameraPublishingButton: UIButton!
    @IBOutlet private weak var microphonePublishingButton: UIButton!

    @IBOutlet private weak var joinOrLeaveButton: UIButton!
    @IBOutlet private weak var roomURLField: UITextField!

    @IBOutlet private weak var localLabel: UILabel!
    @IBOutlet private weak var remoteLabel: UILabel!

    @IBOutlet private weak var localVideoView: VideoView!
    @IBOutlet private weak var remoteVideoView: VideoView!

    @IBOutlet private weak var localVideoContainerView: UIView!

    @IBOutlet private weak var aspectRatioConstraint: NSLayoutConstraint!
    @IBOutlet private weak var bottomConstraint: NSLayoutConstraint!

    private let callClient: CallClient = .init()

    // MARK: - Call state

    private var callState: CallState = .new
    private lazy var inputs: InputSettings? = self.callClient.inputs()
    private lazy var publishing: PublishingSettings? = self.callClient.publishing()
    private let userDefaults: UserDefaults = .standard

    // MARK: - Convenience getters

    private var roomURLString: String {
        get {
            self.userDefaults.string(forKey: "roomURL") ?? ""
        }
        set {
            self.userDefaults.set(newValue, forKey: "roomURL")
        }
    }

    private var canJoinOrLeave: Bool {
        (self.callState != .joining) && (self.callState != .leaving)
    }

    private var isJoined: Bool {
        self.callState == .joined
    }

    private var cameraIsEnabled: Bool {
        self.inputs?.camera?.isEnabled ?? true
    }

    private var microphoneIsEnabled: Bool {
        self.inputs?.microphone?.isEnabled ?? true
    }

    private var cameraIsPublishing: Bool {
        self.publishing?.camera?.isPublishing ?? true
    }

    private var microphoneIsPublishing: Bool {
        self.publishing?.microphone?.isPublishing ?? true
    }

    private var eventSubscriptions: Set<AnyCancellable> = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.localVideoView.delegate = self
        self.roomURLField.delegate = self

        self.setupViews()
        self.setupNotificationObservers()
        self.setupEventListeners()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.updateViews()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.roomURLField.text = self.roomURLString

        // Update inputs to enable video local view prior to joining:
        self.inputs = try! self.callClient.updateInputs(
            .set(
                .init(camera: .set(.isEnabled(true)))
            ))
    }

    // Perform some minimal programmatic view setup:
    private func setupViews() {
        let viewLayer = self.localVideoContainerView.layer
        viewLayer.cornerRadius = 20.0
        viewLayer.cornerCurve = .continuous
        viewLayer.masksToBounds = true
    }

    // Setup notification observers for responding to keyboard frame changes:
    private func setupNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(adjustForKeyboard(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(adjustForKeyboard(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    private func setupEventListeners() {
        // In a scenario where we were just interested in a few types of events we *could*
        // alternatively choose to register to individual event publishers, such as:
        //
        // ```
        // callClient.events.callStateUpdated.sink { event in
        //     print("Call state changed to \(event.state)")
        // }
        // ```
        //
        // In our case here we're actually interested in all events, so a simple switch is best:

        self.callClient.events.all.receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let strongSelf = self else {
                    return
                }

                logger.info("Event: \(event.action)")

                switch event {
                case .callStateUpdated(let event):
                    strongSelf.callStateDidUpdate(event.state)
                case .inputsUpdated(let event):
                    strongSelf.inputsDidUpdate(event.inputs)
                case .publishingUpdated(let event):
                    strongSelf.publishingDidUpdate(event.publishing)
                case .participantJoined(let event):
                    strongSelf.participantDidJoin(event.participant)
                case .participantUpdated(let event):
                    strongSelf.participantDidUpdate(event.participant)
                case .participantLeft(let event):
                    strongSelf.participantDidLeave(event.participant)
                case .error(let event):
                    strongSelf.errorDidOccur(event.message)
                @unknown case _:
                    fatalError()
                }
            }
            .store(in: &eventSubscriptions)
    }

    // MARK: - Button actions

    @IBAction private func didTapLeaveOrJoinButton(_ sender: UIButton) {
        let callState = self.callState
        switch callState {
        case .new, .left:
            let roomURLString = self.roomURLField.text ?? ""
            guard let roomURL = URL(string: roomURLString) else {
                return
            }
            DispatchQueue.global().async {
                do {
                    try self.callClient.join(url: roomURL)
                    logger.info("Joined room: '\(roomURLString)'")
                    self.roomURLString = roomURLString
                } catch let error {
                    logger.error("Error: \(error)")
                    self.callClient.leave()
                    DispatchQueue.main.async {
                        let alert = UIAlertController(
                            title: "Failed to join room",
                            message: roomURLString,
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            }
        case .joined:
            DispatchQueue.global().async {
                self.callClient.leave()
            }
        case .joining, .leaving:
            break
        @unknown case _:
            fatalError()
        }
    }

    @IBAction private func didTapCameraInputButton(_ sender: UIButton) {
        let isEnabled = sender.isSelected

        DispatchQueue.global().async {
            self.inputs = try! self.callClient.updateInputs(
                .set(
                    .init(camera: .set(.isEnabled(isEnabled)))
                ))
        }
    }

    @IBAction private func didTapMicrophoneInputButton(_ sender: UIButton) {
        let isEnabled = sender.isSelected

        DispatchQueue.global().async {
            self.inputs = try! self.callClient.updateInputs(
                .set(
                    .init(microphone: .set(.isEnabled(isEnabled)))
                ))
        }
    }

    @IBAction private func didTapCameraPublishingButton(_ sender: UIButton) {
        let isEnabled = sender.isSelected

        DispatchQueue.global().async {
            self.publishing = try! self.callClient.updatePublishing(
                .set(
                    .init(camera: .set(.isPublishing(isEnabled)))
                ))
        }
    }

    @IBAction private func didTapMicrophonePublishingButton(_ sender: UIButton) {
        let isEnabled = sender.isSelected

        DispatchQueue.global().async {
            self.publishing = try! self.callClient.updatePublishing(
                .set(
                    .init(microphone: .set(.isPublishing(isEnabled)))
                ))
        }
    }

    // MARK: - Event handling

    private func callStateDidUpdate(_ callState: CallState) {
        logger.debug("Call state updated: \(callState)")

        self.callState = callState
        self.updateViews()
    }

    private func inputsDidUpdate(_ inputs: InputSettings) {
        logger.debug("Inputs updated:")
        logger.debug("\(dumped(inputs))")

        self.inputs = inputs
        self.updateViews()
    }

    private func publishingDidUpdate(_ publishing: PublishingSettings) {
        logger.debug("Publishing updated:")
        logger.debug("\(dumped(publishing))")

        self.publishing = publishing
        self.updateViews()
    }

    private func participantDidJoin(_ participant: Participant) {
        logger.debug("Participant joined:")
        logger.debug("\(dumped(participant))")

        self.updateParticipant(participant)
    }

    private func participantDidUpdate(_ participant: Participant) {
        logger.debug("Participant updated:")
        logger.debug("\(dumped(participant))")

        self.updateParticipant(participant)
    }

    private func participantDidLeave(_ participant: Participant) {
        logger.debug("Participant left:")
        logger.debug("\(dumped(participant))")

        self.updateParticipant(participant, whoHasLeft: true)
    }

    private func errorDidOccur(_ message: String) {
        logger.error("Error: \(message)")
    }

    // MARK: - View management

    private func updateViews() {
        // Update views based on current state:

        self.roomURLField.isEnabled = !self.isJoined

        self.joinOrLeaveButton.isEnabled = self.canJoinOrLeave
        self.joinOrLeaveButton.isSelected = self.isJoined

        self.cameraInputButton.isSelected = self.cameraIsEnabled
        self.microphoneInputButton.isSelected = self.microphoneIsEnabled

        self.cameraPublishingButton.isSelected = self.cameraIsPublishing
        self.microphonePublishingButton.isSelected = self.microphoneIsPublishing

        if (!self.isJoined) {
            self.remoteLabel.text = ""
            self.remoteVideoView.isHidden = true
            // Note that if we *have* joined, we don't set isHidden = false
            // quite yet (we wait for the remote participant's video)
        }
    }

    private func updateParticipant(_ participant: Participant, whoHasLeft hasLeft: Bool = false) {
        let videoTrack = participant.media?.camera.track
        let isLocal = participant.info.isLocal
        let locality = isLocal ? "local" : "remote"
        let trackDescription = String(describing: videoTrack)

        let username = participant.info.username ?? "Guest"

        // Assign name to label, hiding it if it's a remote participant who left:
        let label: UILabel = isLocal ? self.localLabel : self.remoteLabel
        label.text = (!isLocal && hasLeft) ? "" : username

        // Assign track to video view:
        let videoView: VideoView = isLocal ? self.localVideoView : self.remoteVideoView
        videoView.track = videoTrack

        // Hide video view if there's no video to play
        // TODO(kompfner): Let's switch to using participant.media?.camera.state soon to show
        // better video state UI (loading, interrupted, off, etc.). There are
        // still issues, though, preventing us from using the state field today.
        videoView.isHidden = videoTrack == nil

        logger.debug("Updated \(locality) video view with optional track: \(trackDescription)")
    }

    @objc func adjustForKeyboard(_ notification: Notification) {
        // When the keyboard is shown/hidden make sure to move the text field up/down accordingly:
        let userInfoKey = UIResponder.keyboardFrameEndUserInfoKey
        guard let keyboardFrameEndValue = notification.userInfo?[userInfoKey] as? NSValue else {
            return
        }

        let keyboardScreenEndFrame = keyboardFrameEndValue.cgRectValue
        let keyboardViewEndFrame = self.view.convert(keyboardScreenEndFrame, from: self.view.window)

        // Move UI up by height of keyboard:
        let offset = keyboardViewEndFrame.height - self.view.safeAreaInsets.bottom
        self.bottomConstraint.constant = 20.0 + offset
    }
}

extension CallViewController: UITextFieldDelegate {
    func textFieldDidEndEditing(_ textField: UITextField) {
        // Move UI back down when editing has ended:
        self.bottomConstraint.constant = 20.0
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Hide the keyboard when user taps on "Return":
        return textField.endEditing(false)
    }
}

extension CallViewController: VideoViewDelegate {
    func videoView(_ videoView: VideoView, didChangeVideoSize size: CGSize) {
        // When the video size changes we update the video-view's
        // aspect-ratio layout constraint accordingly:

        let aspectRatio: CGFloat = size.width / size.height

        let view: UIView = self.localVideoContainerView
        self.aspectRatioConstraint.isActive = false
        self.aspectRatioConstraint = view.widthAnchor.constraint(
            equalTo: view.heightAnchor,
            multiplier: aspectRatio
        )
        self.aspectRatioConstraint.isActive = true

        UIView.animate(withDuration: 0.25) {
            self.view.setNeedsLayout()
        }
    }
}
