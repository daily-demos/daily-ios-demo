import AVFoundation
import Combine
import Daily
import Logging
import UIKit

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
    @IBOutlet private weak var tokenField: UITextField!
    @IBOutlet private weak var roomURLField: UITextField!

    @IBOutlet private weak var localViewToggleButton: UIButton!

    @IBOutlet private weak var localParticipantContainerView: UIView!

    @IBOutlet private weak var aspectRatioConstraint: NSLayoutConstraint!
    @IBOutlet private weak var bottomConstraint: NSLayoutConstraint!
    
    // TODO refactor
    @IBOutlet weak var pickerViewButton: UIButton!

    private weak var localParticipantViewController: ParticipantViewController! {
        didSet {
            self.localParticipantViewControllerDidChange(
                self.localParticipantViewController
            )
        }
    }

    private weak var remoteParticipantViewController: ParticipantViewController!
    
    private lazy var callClient: CallClient = {
        let callClient = CallClient()
        callClient.delegate = self
        return callClient
    }()

    // MARK: - Call state

    private let userDefaults: UserDefaults = .standard

    private var localVideoSizeObserver: AnyCancellable? = nil

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
        let callState = self.callClient.callState
        return (callState != .joining) && (callState != .leaving)
    }

    private var isJoined: Bool {
        self.callClient.callState == .joined
    }

    private var cameraIsEnabled: Bool {
        self.callClient.inputs.camera.isEnabled
    }

    private var microphoneIsEnabled: Bool {
        self.callClient.inputs.microphone.isEnabled
    }

    private var cameraIsPublishing: Bool {
        self.callClient.publishing.camera.isPublishing
    }

    private var microphoneIsPublishing: Bool {
        self.callClient.publishing.microphone.isPublishing
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.roomURLField.delegate = self

        self.setupViews()
        self.setupNotificationObservers()
        self.setupCallClient()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.updateViews()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.roomURLField.text = self.roomURLString

        // Update inputs to enable/disable inputs prior to joining:
        // By default, we are always starting the demo app with the mic and camera on
        let _ = try! self.callClient.updateInputs { inputs in
            inputs(\.camera) { camera in
                camera(\.isEnabled, self.cameraIsEnabled)
                camera(\.isEnabled, true)
            }
            inputs(\.microphone) { microphone in
                microphone(\.isEnabled, self.microphoneIsEnabled)
                microphone(\.isEnabled, true)
            }
        }

        // Update publishing to enable/disable publishing of inputs prior to joining:
        let _ = try! self.callClient.updatePublishing { publishing in
            publishing(\.camera) { camera in
                camera(\.isPublishing, self.cameraIsPublishing)
            }
            publishing(\.microphone) { microphone in
                microphone(\.isPublishing, self.microphoneIsPublishing)
            }
        }
        self.refreshSelectedAudioDevice()
    }
    
    private func refreshSelectedAudioDevice() {
        let audioDeviceId = self.callClient.audioDevice.deviceId

        let selectedDevice = self.callClient.availableDevices.audio.first {
            $0.deviceId == audioDeviceId
        }

        self.pickerViewButton.setTitle(selectedDevice?.label, for: .normal)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
        case "embedLocalContainerView":
            guard let destination = segue.destination as? ParticipantViewController else {
                fatalError()
            }
            destination.callClient = self.callClient
            self.localParticipantViewController = destination
        case "embedRemoteContainerView":
            guard let destination = segue.destination as? ParticipantViewController else {
                fatalError()
            }
            destination.callClient = self.callClient
            self.remoteParticipantViewController = destination
        case _:
            fatalError()
        }
    }

    // Perform some minimal programmatic view setup:
    private func setupViews() {
        let localViewLayer = self.localParticipantViewController.view.layer
        localViewLayer.cornerRadius = 20.0
        localViewLayer.cornerCurve = .continuous
        localViewLayer.masksToBounds = true
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

    private func setupCallClient() {
        let _ = try! self.callClient.updateSubscriptionProfiles { profiles in
            profiles(.base) { base in
                base(\.camera) { camera in
                    camera(\.receiveSettings) { receiveSettings in
                        receiveSettings(\.maxQuality, .low)
                    }
                }
            }
            profiles(.activeRemote) { activeRemote in
                activeRemote(\.camera) { camera in
                    camera(\.receiveSettings) { receiveSettings in
                        receiveSettings(\.maxQuality, .high)
                    }
                }
            }
        }
    }

    // MARK: Device picker

    private func showAudioDevicePicker() {
        let controller = UIViewController()

        let screenBounds = UIScreen.main.bounds
        let pickerWidth = screenBounds.width - 10.0
        let pickerHeight = screenBounds.height / 2.0

        let pickerSize = CGSize(
            width: pickerWidth,
            height: pickerHeight
        )
        controller.preferredContentSize = pickerSize

        let pickerFrame = CGRect(
            origin: .zero,
            size: pickerSize
        )

        let pickerView = UIPickerView(frame: pickerFrame)
        pickerView.dataSource = self
        pickerView.delegate = self
        let selectedRow = self.selectedDevicePickerRow()
        pickerView.selectRow(selectedRow, inComponent: 0, animated: false)

        controller.view.addSubview(pickerView)
        pickerView.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor).isActive = true
        pickerView.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor).isActive = true

        let alert = UIAlertController(title: "Select audio route", message: "", preferredStyle: .actionSheet)

        alert.popoverPresentationController?.sourceView = pickerViewButton
        alert.popoverPresentationController?.sourceRect = pickerViewButton.bounds

        alert.setValue(controller, forKey: "contentViewController")
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Select", style: .default) { action in
            let selectedRow = pickerView.selectedRow(inComponent: 0)
            let selectedDevice = self.callClient.availableDevices.audio[selectedRow]
            self.pickerViewButton.setTitle(selectedDevice.label, for: .normal)
            self.callClient.preferredAudioDevice = AudioDeviceType(deviceId: selectedDevice.deviceId)
        })

        self.present(alert, animated: true, completion: nil)
    }

    private func selectedDevicePickerRow() -> Int {
        let selectedDeviceId = self.callClient.audioDevice.deviceId
        return self.callClient.availableDevices.audio.firstIndex {
            $0.deviceId == selectedDeviceId
        } ?? 0
    }

    // MARK: - Button actions

    @IBAction private func didTapAudioDevicePicker(_ sender: Any) {
        self.showAudioDevicePicker()
    }

    @IBAction private func didTapLocalViewToggleButton(_ sender: UIButton) {
        self.localParticipantViewController.isViewHidden = sender.isSelected
    }

    @IBAction private func didTapLeaveOrJoinButton(_ sender: UIButton) {
        let callState = self.callClient.callState
        switch callState {
        case .initialized, .left:
            let roomURLString = self.roomURLField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let roomURL = URL(string: roomURLString) else {
                return
            }
            let tokenString = self.tokenField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let roomToken = tokenString.map { MeetingToken(stringValue: $0) }

            DispatchQueue.global().async {
                do {
                    try self.callClient.join(url: roomURL, token: roomToken)
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
        let isEnabled = !self.callClient.inputs.camera.isEnabled

        DispatchQueue.global().async {
            let _ = try! self.callClient.updateInputs { inputs in
                inputs(\.camera) { camera in
                    camera(\.isEnabled, isEnabled)
                }
            }
        }
    }

    @IBAction private func didTapMicrophoneInputButton(_ sender: UIButton) {
        let isEnabled = !self.callClient.inputs.microphone.isEnabled

        DispatchQueue.global().async {
            let _ = try! self.callClient.updateInputs { inputs in
                inputs(\.microphone) { microphone in
                    microphone(\.isEnabled, isEnabled)
                }
            }
        }
    }

    @IBAction private func didTapCameraPublishingButton(_ sender: UIButton) {
        let isPublishing = !self.callClient.publishing.camera.isPublishing

        DispatchQueue.global().async {
            let _ = try! self.callClient.updatePublishing { publishing in
                publishing(\.camera) { camera in
                    camera(\.isPublishing, isPublishing)
                }
            }
        }
    }

    @IBAction private func didTapMicrophonePublishingButton(_ sender: UIButton) {
        let isPublishing = !self.callClient.publishing.microphone.isPublishing

        DispatchQueue.global().async {
            let _ = try! self.callClient.updatePublishing { publishing in
                publishing(\.microphone) { microphone in
                    microphone(\.isPublishing, isPublishing)
                }
            }
        }
    }

    // MARK: - Video size handling

    func localParticipantViewControllerDidChange(_ controller: ParticipantViewController) {
        self.localVideoSizeObserver = controller.videoSizePublisher.sink(
            receiveValue: localVideoSizeDidChange(_:)
        )
    }

    func localVideoSizeDidChange(_ videoSize: CGSize) {
        // When the local video size changes we update its view's
        // aspect-ratio layout constraint accordingly:

        guard videoSize != .zero else {
            // Make sure we don't divide by zero!
            return
        }

        let aspectRatio: CGFloat = videoSize.width / videoSize.height

        let containerView: UIView = self.localParticipantContainerView

        // Setting a constraint's `isActive` to `false` also removes it:
        self.aspectRatioConstraint.isActive = false

        // So now we need to replace it with an updated constraint:
        self.aspectRatioConstraint = containerView.widthAnchor.constraint(
            equalTo: containerView.heightAnchor,
            multiplier: aspectRatio
        )
        self.aspectRatioConstraint.priority = .required
        self.aspectRatioConstraint.isActive = true

        UIView.animate(withDuration: 0.25) {
            self.view.setNeedsLayout()
        }
    }

    // MARK: - View management

    private func updateViews() {
        // Update views based on current state:

        self.roomURLField.isEnabled = !self.isJoined

        self.joinOrLeaveButton.isEnabled = self.canJoinOrLeave
        self.joinOrLeaveButton.isSelected = self.isJoined

        self.cameraInputButton.isSelected = !self.cameraIsEnabled
        self.microphoneInputButton.isSelected = !self.microphoneIsEnabled

        self.cameraPublishingButton.isSelected = !self.cameraIsPublishing
        self.microphonePublishingButton.isSelected = !self.microphoneIsPublishing
    }

    private func updateParticipantViewControllers() {
        // Update participant views based on current callClient state.
        // We play it safe and update both local and remote views since active
        // speaker status may have passed from one to the other.
        let participants = self.callClient.participants
        self.update(localParticipant: participants.local)
        self.update(remoteParticipants: participants.remote)
    }

    private func update(localParticipant: Participant) {
        self.localParticipantViewController.participant = localParticipant
        self.localParticipantViewController.isActiveSpeaker = self.isActiveSpeaker(localParticipant)
    }

    private func update(remoteParticipants: [ParticipantId: Participant]) {
        var remoteParticipantToDisplay: Participant?

        // Choose a remote participant to display by going down the priority list:
        // 1. A screen sharer
        // 2. The active speaker
        // 3. Whoever was previously displayed (if anyone)
        // 4. Anyone else

        // 1. If a remote participant is sharing their screen, choose them
        remoteParticipantToDisplay = remoteParticipants.values.first { participant in
            participant.media?.screenVideo.track != nil
        }

        // 2. If a remote participant is the active speaker, choose them
        if remoteParticipantToDisplay == nil {
            if let activeSpeaker = self.callClient.activeSpeaker, !activeSpeaker.info.isLocal {
                remoteParticipantToDisplay = activeSpeaker
            }
        }

        // 3. Choose whoever was previously displayed (if anyone)
        if remoteParticipantToDisplay == nil {
            if let previouslyDisplayedParticipantId = self.remoteParticipantViewController.participant?.id
            {
                remoteParticipantToDisplay = remoteParticipants[previouslyDisplayedParticipantId]
            }
        }

        // 4. Choose anyone else (let's just go with the first remote participant)
        if remoteParticipantToDisplay == nil {
            remoteParticipantToDisplay = remoteParticipants.first?.value
        }

        // Display the chosen remote participant (can be nil)
        self.remoteParticipantViewController.participant = remoteParticipantToDisplay
        if let remoteParticipantToDisplay = remoteParticipantToDisplay {
            self.remoteParticipantViewController.isActiveSpeaker = self.isActiveSpeaker(
                remoteParticipantToDisplay)
        } else {
            self.remoteParticipantViewController.isActiveSpeaker = false
        }
    }

    private func isActiveSpeaker(_ participant: Participant) -> Bool {
        let activeSpeaker = self.callClient.activeSpeaker
        return activeSpeaker == participant
    }

    @objc private func adjustForKeyboard(_ notification: Notification) {
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

extension CallViewController: CallClientDelegate {
    func callClient(
        _ callClient: CallClient,
        callStateUpdated callState: CallState
    ) {
        logger.debug("Call state updated: \(callState)")

        assert(self.callClient.callState == callState)

        self.updateViews()

        if case .left = self.callClient.callState {
            self.localParticipantViewController.participant = nil
            self.remoteParticipantViewController.participant = nil
        }
    }

    func callClient(
        _ callClient: CallClient,
        inputsUpdated inputs: InputSettings
    ) {
        logger.debug("Inputs updated:")
        logger.debug("\(dumped(inputs))")

        assert(self.callClient.inputs == inputs)

        self.updateViews()
    }

    func callClient(
        _ callClient: CallClient,
        publishingUpdated publishing: PublishingSettings
    ) {
        logger.debug("Publishing updated:")
        logger.debug("\(dumped(publishing))")

        assert(self.callClient.publishing == publishing)

        self.updateViews()
    }

    func callClient(
        _ callClient: CallClient,
        participantJoined participant: Participant
    ) {
        logger.debug("Participant joined:")
        logger.debug("\(dumped(participant))")

        assert(self.callClient.participants.all[participant.id] == participant)

        self.updateParticipantViewControllers()
    }

    func callClient(
        _ callClient: CallClient,
        participantUpdated participant: Participant
    ) {
        logger.debug("Participant updated:")
        logger.debug("\(dumped(participant))")

        assert(self.callClient.participants.all[participant.id] == participant)

        self.updateParticipantViewControllers()
    }

    func callClient(
        _ callClient: CallClient,
        participantLeft participant: Participant,
        withReason reason: ParticipantLeftReason
    ) {
        logger.debug("Participant left:")
        logger.debug("\(dumped(participant))")
        logger.debug("\(reason)")

        assert(self.callClient.participants.all[participant.id] == nil)

        self.updateParticipantViewControllers()
    }

    func callClient(
        _ callClient: CallClient,
        activeSpeakerChanged activeSpeaker: Participant?
    ) {
        logger.debug("Active speaker changed:")
        logger.debug("\(dumped(activeSpeaker))")

        assert(self.callClient.activeSpeaker == activeSpeaker)

        self.updateParticipantViewControllers()
    }

    func callClient(
        _ callClient: CallClient,
        subscriptionsUpdated subscriptions: SubscriptionSettingsById
    ) {
        logger.debug("Subscriptions updated:")
        logger.debug("\(dumped(subscriptions))")

        assert(self.callClient.subscriptions == subscriptions)
    }

    func callClient(
        _ callClient: CallClient,
        subscriptionProfilesUpdated subscriptionProfiles: SubscriptionProfileSettingsByProfile
    ) {
        logger.debug("Subscriptions profiles updated:")
        logger.debug("\(dumped(subscriptionProfiles))")

        assert(self.callClient.subscriptionProfiles == subscriptionProfiles)
    }

    func callClient(
        _ callClient: CallClient,
        availableDevicesUpdated availableDevices: Devices
    ) {
        self.refreshSelectedAudioDevice()

        assert(self.callClient.availableDevices == availableDevices)
    }

    func callClient(
        _ callClient: CallClient,
        error: CallClientError
    ) {
        logger.error("Error: \(error)")
    }
}

extension CallViewController: UIPickerViewDelegate {
    internal func pickerView(
        _ pickerView: UIPickerView,
        viewForRow row: Int,
        forComponent component: Int,
        reusing view: UIView?
    ) -> UIView {
        let label = UILabel()
        label.text = self.callClient.availableDevices.audio[row].label
        label.sizeToFit()
        return label
    }

    internal func pickerView(
        _ pickerView: UIPickerView,
        rowHeightForComponent component: Int
    ) -> CGFloat {
        return 60
    }
}

extension CallViewController: UIPickerViewDataSource {
    internal func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }

    internal func pickerView(
        _ pickerView: UIPickerView,
        numberOfRowsInComponent component: Int
    ) -> Int {
        self.callClient.availableDevices.audio.count
    }
}
