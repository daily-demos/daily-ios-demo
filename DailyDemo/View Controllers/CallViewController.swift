import AVFoundation
import ReplayKit
import Combine
import Daily
import Logging
import UIKit
import UserNotifications

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
    @IBOutlet private weak var cameraFlipViewButton: UIButton!
    @IBOutlet private weak var adaptiveHEVCButton: UIButton!

    
    @IBOutlet private weak var joinOrLeaveButton: UIButton!
    @IBOutlet private weak var tokenField: UITextField!
    @IBOutlet private weak var roomURLField: UITextField!
    
    @IBOutlet private weak var localViewToggleButton: UIButton!

    @IBOutlet private weak var localParticipantContainerView: UIView!
    @IBOutlet private weak var remoteParticipantContainerView: UIView!
    @IBOutlet private weak var systemBroadcastPickerView: RPSystemBroadcastPickerView!

    @IBOutlet private weak var buttonStackView: UIStackView!

    @IBOutlet private weak var aspectRatioConstraint: NSLayoutConstraint!
    @IBOutlet private weak var bottomConstraint: NSLayoutConstraint!
    
    // TODO refactor
    @IBOutlet private weak var pickerViewButton: UIButton!
    
    private weak var localParticipantViewController: LocalParticipantViewController! {
        didSet {
            self.localParticipantViewControllerDidChange(
                self.localParticipantViewController
            )
        }
    }
    
    private weak var remoteParticipantViewController: ParticipantViewController!
    
    private lazy var callClient: CallClient = { [weak self] in
        let callClient = CallClient()
        callClient.delegate = self
        return callClient
    }()
    
    // MARK: - Call state

    private var adaptiveHEVCEnabled: Bool = false

    private let userDefaults: UserDefaults = .standard
    
    private var localVideoSizeObserver: AnyCancellable? = nil

    // MARK: - Date coding

    // Cached customized ISO8601 date formatter:
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        // The default `.iso8601` dateEncodingStrategy/dateDecodingStrategy
        // doesn't support fractional seconds (aka milliseconds).
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // The default `.iso8601` dateEncodingStrategy/dateDecodingStrategy
    // doesn't support fractional seconds (aka milliseconds).
    private var dateEncodingStrategy: JSONEncoder.DateEncodingStrategy {
        .custom { (date, encoder) in
            self.dateFormatter.string(from: date)
        }
    }

    // The default `.iso8601` dateEncodingStrategy/dateDecodingStrategy
    // doesn't support fractional seconds (aka milliseconds).
    private var dateDecodingStrategy: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let formattedDate = try String(from: decoder)

            guard let date = self.dateFormatter.date(from: formattedDate) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected date string to be ISO8601-formatted."
                    )
                )
            }

            return date
        }
    }

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
    
    private var screenIsEnabled: Bool {
        self.callClient.inputs.screenVideo.isEnabled
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
        self.roomURLField.accessibilityIdentifier = "robots-room-url-field"
        self.cameraInputButton.accessibilityIdentifier = "robots-camera-input"
        self.microphoneInputButton.accessibilityIdentifier = "robots-mic-input"
        self.cameraPublishingButton.accessibilityIdentifier = "robots-camera-publish"
        self.microphonePublishingButton.accessibilityIdentifier = "robots-mic-publish"

        self.setupViews()
        self.setupNotificationObservers()
        self.setupCallClient()
        self.setupAuthorizations()
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
        self.callClient.setInputsEnabled([
            .camera: true,
            .microphone: true
        ], completion: nil)
        
        // Update publishing to enable/disable publishing of inputs prior to joining:
        self.callClient.setIsPublishing([
            .camera: self.cameraIsPublishing,
            .microphone: self.microphoneIsPublishing
        ], completion: nil)
        
        self.refreshSelectedAudioDevice()
    }
    
    private func refreshSelectedAudioDevice() {
        let audioDeviceID = self.callClient.audioDevice.deviceID
        
        let selectedDevice = self.callClient.availableDevices.audio.first {
            $0.deviceID == audioDeviceID
        }
        
        self.pickerViewButton.setTitle(selectedDevice?.label, for: .normal)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
        case "embedLocalContainerView":
            guard let destination = segue.destination as? LocalParticipantViewController else {
                fatalError()
            }
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

    private func setupAuthorizations() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }
    
    // Perform some minimal programmatic view setup:
    private func setupViews() {
        let localViewLayer = self.localParticipantViewController.view.layer
        localViewLayer.cornerRadius = 20.0
        localViewLayer.cornerCurve = .continuous
        localViewLayer.masksToBounds = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        self.remoteParticipantContainerView.addGestureRecognizer(tap)
        
        self.systemBroadcastPickerView.preferredExtension = "co.daily.DailyDemo.DailyDemoScreenCaptureExtension"
        self.systemBroadcastPickerView.showsMicrophoneButton = false
    }

    /// Setup notification observers for:
    ///
    /// - Responding to keyboard frame changes
    /// - Managing `isIdleTimerDisabled`
    private func setupNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(adjustForKeyboard(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
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

        notificationCenter.addObserver(
            self,
            selector: #selector(callClientDidJoinFirstCall),
            name: CallClient.NotificationName.didJoinFirstCall,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(callClientDidLeaveLastCall),
            name: CallClient.NotificationName.didLeaveLastCall,
            object: nil
        )
    }
    
    private func setupCallClient() {
        self.callClient.updatePublishing(.set(
            camera: .set(
                isPublishing: .set(self.cameraIsPublishing),
                sendSettings: .fromDefaults
            )
        ), completion: nil)
        self.callClient.updateSubscriptionProfiles(.set([
            .base: .set(
                camera: .set(
                    receiveSettings: .set(
                        maxQuality: .set(.low)
                    )
                )
            ),
            .activeRemote: .set(
                camera: .set(
                    receiveSettings: .set(
                        maxQuality: .set(.high)
                    )
                )
            )
        ]), completion: nil)
    }
    
    // MARK: Device picker
    
    private func selectedDevicePickerRow() -> Int {
        let selectedDeviceID = self.callClient.audioDevice.deviceID
        return self.callClient.availableDevices.audio.firstIndex {
            $0.deviceID == selectedDeviceID
        } ?? 0
    }
    
    // MARK: - Button actions
    
    @IBAction private func flipCamera(_ sender: UIButton) {
        let isUsingFrontFacingCamera = self.callClient.inputs.camera.settings.facingMode == .user
        let newFacingMode: MediaTrackFacingMode = isUsingFrontFacingCamera ? .environment : .user

        self.callClient.updateInputs(.set(
            camera: .set(
                settings: .set(facingMode: .set(newFacingMode))
            )
        ), completion: nil)
    }

    @IBAction private func toggleAdaptiveHEVC(_ sender: UIButton) {
        self.adaptiveHEVCEnabled = !self.adaptiveHEVCEnabled
        if self.adaptiveHEVCEnabled {
            self.callClient.updatePublishing(.set(
                camera: .set(
                    isPublishing: .set(self.cameraIsPublishing),
                    sendSettings: .set(
                        maxQuality: .set(.high),
                        encodings: .set(.mode(.adaptiveHEVC))
                    )
                )
            ), completion: nil)
        } else {
            self.callClient.updatePublishing(.set(
                camera: .set(
                    isPublishing: .set(self.cameraIsPublishing),
                    sendSettings: .fromDefaults
                )
            ), completion: nil)
        }
    }
    
    @IBAction private func showAudioDevicePicker(_ sender: Any) {
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
            let preferredAudioDevice = AudioDeviceType(deviceID: selectedDevice.deviceID)
            self.callClient.set(preferredAudioDevice: preferredAudioDevice, completion: nil)
        })

        self.present(alert, animated: true, completion: nil)
    }
    
    @IBAction private func toggleLocalView(_ sender: UIButton) {
        sender.isSelected.toggle()
        
        self.localParticipantViewController.isViewHidden = sender.isSelected
    }
    
    @IBAction private func joinOrLeave(_ sender: UIButton) {
        let callState = self.callClient.callState
        switch callState {
        case .initialized, .left:
            let roomURLString = self.roomURLField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let roomURL = URL(string: roomURLString) else {
                return
            }
            let tokenString = self.tokenField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let roomToken = tokenString.map { MeetingToken(stringValue: $0) }
            
            self.callClient.join(url: roomURL, token: roomToken) { result in
                switch result {
                case .success(_):
                    logger.info("Joined room: '\(roomURLString)'")
                    self.roomURLString = roomURLString
                case .failure(let error):
                    logger.error("\(error)")
                }
            }
        case .joined:
            self.callClient.leave(completion: nil)
        case .joining, .leaving:
            break
        @unknown case _:
            fatalError()
        }
    }
    
    @IBAction private func toggleCameraInput(_ sender: UIButton) {
        let isEnabled = !self.callClient.inputs.camera.isEnabled
        self.callClient.setInputEnabled(.camera, isEnabled, completion: nil)
    }
    
    @IBAction private func toggleMicrophoneInput(_ sender: UIButton) {
        let isEnabled = !self.callClient.inputs.microphone.isEnabled
        self.callClient.setInputEnabled(.microphone, isEnabled, completion: nil)
    }
    
    @IBAction private func toggleCameraPublishing(_ sender: UIButton) {
        let isPublishing = !self.callClient.publishing.camera.isPublishing
        self.callClient.setIsPublishing(.camera, isPublishing, completion: nil)
    }
    
    @IBAction private func toggleMicrophonePublishing(_ sender: UIButton) {
        let isPublishing = !self.callClient.publishing.microphone.isPublishing
        self.callClient.setIsPublishing(.microphone, isPublishing, completion: nil)
    }
    
    // MARK: - Video size handling
    
    func localParticipantViewControllerDidChange(_ controller: LocalParticipantViewController) {
        self.localVideoSizeObserver = controller.videoSizePublisher.sink { [weak self] size in
            guard let self = self else { return }

            self.localVideoSizeDidChange(size)
        }
    }
    
    private func localVideoSizeDidChange(_ videoSize: CGSize) {
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

    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        UIView.animate(withDuration: 0.25) {
            self.buttonStackView.alpha = self.buttonStackView.alpha.isZero ? 1 : 0
        }
    }

    private func updateViews() {
        // Update views based on current state:
        
        self.roomURLField.isEnabled = !self.isJoined
        
        self.joinOrLeaveButton.isEnabled = self.canJoinOrLeave
        self.joinOrLeaveButton.isSelected = self.isJoined
        if (self.joinOrLeaveButton.isSelected) {
            self.joinOrLeaveButton.accessibilityIdentifier = "robots-leave-button"
        } else {
            self.joinOrLeaveButton.accessibilityIdentifier = "robots-join-button"
        }
        
        self.cameraInputButton.isSelected = !self.cameraIsEnabled
        self.cameraInputButton.accessibilityIdentifier = "robots-camera-input-\(!self.cameraIsEnabled)"
        self.microphoneInputButton.isSelected = !self.microphoneIsEnabled
        self.microphoneInputButton.accessibilityIdentifier = "robots-mic-input-\(!self.microphoneIsEnabled)"

        self.cameraPublishingButton.isSelected = !self.cameraIsPublishing
        self.cameraPublishingButton.accessibilityIdentifier = "robots-camera-publish-\(!self.cameraIsPublishing)"
        self.microphonePublishingButton.isSelected = !self.microphoneIsPublishing
        self.microphonePublishingButton.accessibilityIdentifier = "robots-mic-publish-\(!self.microphoneIsPublishing)"

        self.adaptiveHEVCButton.isSelected = self.adaptiveHEVCEnabled
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
    
    private func update(remoteParticipants: [ParticipantID: Participant]) {
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
                remoteParticipantToDisplay = remoteParticipants[activeSpeaker.id]
            }
        }
        
        // 3. Choose whoever was previously displayed (if anyone)
        if remoteParticipantToDisplay == nil {
            if let previouslyDisplayedParticipantID = self.remoteParticipantViewController.participant?.id
            {
                remoteParticipantToDisplay = remoteParticipants[previouslyDisplayedParticipantID]
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

    fileprivate func showPrebuiltChatAppMessageNotification(
        title: String,
        body: String
    ) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 1.0,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: PrebuiltChatAppMessage.notificationIdentifier,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
    
    @objc private func adjustForKeyboard(_ notification: Notification) {
        // When the keyboard is shown/hidden make sure to move the text field up/down accordingly:

        // Obtain the animation's duration:
        let durationKey = UIResponder.keyboardAnimationDurationUserInfoKey
        let duration = notification.userInfo![durationKey] as! Double

        // Obtain the animation's curve:
        let curveKey = UIResponder.keyboardAnimationCurveUserInfoKey
        let curveValue = notification.userInfo![curveKey] as! Int
        let curve = UIView.AnimationCurve(rawValue: curveValue)!

        let offset: CGFloat
        switch notification.name {
        case UIResponder.keyboardWillShowNotification, UIResponder.keyboardWillChangeFrameNotification:
            // Obtain the keyboard's projected frame at the end of the animation:
            let frameKey = UIResponder.keyboardFrameEndUserInfoKey
            let keyboardFrameEndValue = notification.userInfo![frameKey] as! NSValue
            let keyboardViewEndFrame = self.view.convert(
                keyboardFrameEndValue.cgRectValue,
                from: self.view.window
            )

            offset = keyboardViewEndFrame.height - self.view.safeAreaInsets.bottom
        case UIResponder.keyboardWillHideNotification:
            offset = 0.0
        case _:
            offset = 0.0
        }

        // Move UI up by height of keyboard:

        let animator = UIViewPropertyAnimator(
            duration: duration,
            curve: curve
        ) {
            self.bottomConstraint.constant = 20.0 + offset

            // Required to trigger NSLayoutConstraint changes to animate:
            self.view?.layoutIfNeeded()
        }

        animator.startAnimation()
    }

    @objc private func callClientDidJoinFirstCall() {
        DispatchQueue.main.async {
            // Setting `isIdleTimerDisabled` to `true` prevents the device from sleeping once a call is joined.
            UIApplication.shared.isIdleTimerDisabled = true
            logger.debug("Updated isIdleTimerDisabled: \(UIApplication.shared.isIdleTimerDisabled)")
        }
    }

    @objc private func callClientDidLeaveLastCall() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
            logger.debug("Updated isIdleTimerDisabled: \(UIApplication.shared.isIdleTimerDisabled)")
        }
    }
}

extension CallViewController: UITextFieldDelegate {
    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.resignFirstResponder()
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Hide the keyboard when user taps on "Return":
        return textField.endEditing(false)
    }
}

extension CallViewController: CallClientDelegate {
    func callClientDidDetectStartOfSystemBroadcast(
        _ callClient: CallClient
    ) {
        logger.debug("System broadcast started")

        callClient.updateInputs(
            .set(screenVideo: .set(isEnabled: .set(true))),
            completion: nil
        )
    }

    public func callClientDidDetectEndOfSystemBroadcast(
        _ callClient: CallClient
    ) {
        logger.debug("System broadcast ended")

        callClient.updateInputs(
            .set(screenVideo: .set(isEnabled: .set(false))),
            completion: nil
        )
    }

    func callClient(
        _ callClient: CallClient,
        callStateUpdated callState: CallState
    ) {
        logger.debug("Call state updated: \(callState)")
        
        assert(callClient.callState == callState)
        
        updateViews()
        
        if case .left = callClient.callState {
            self.localParticipantViewController.participant = nil
            self.remoteParticipantViewController.participant = nil
        } else if case .joined = callClient.callState {
            if let callConfiguration = callClient.callConfiguration {
                logger.info("callConfiguration: \(callConfiguration)")
            } else {
                logger.info("No callConfiguration when we joined the call")
            }
        }
    }

    func callClient(
        _ callClient: CallClient,
        inputsUpdated inputs: InputSettings
    ) {
        logger.debug("Inputs updated:")
        logger.debug("\(dumped(inputs))")
        
        assert(callClient.inputs == inputs)
        
        updateViews()
    }
    
    func callClient(
        _ callClient: CallClient,
        publishingUpdated publishing: PublishingSettings
    ) {
        logger.debug("Publishing updated:")
        logger.debug("\(dumped(publishing))")
        
        assert(callClient.publishing == publishing)
        
        updateViews()
    }
    
    func callClient(
        _ callClient: CallClient,
        participantJoined participant: Participant
    ) {
        logger.debug("Participant joined:")
        logger.debug("\(dumped(participant))")
        
        // Check if our logic adds said participant to the collection from event...
        assert(callClient.participants.all[participant.id] != nil)
        
        updateParticipantViewControllers()
    }
    
    func callClient(
        _ callClient: CallClient,
        participantUpdated participant: Participant
    ) {
        logger.debug("Participant updated:")
        logger.debug("\(dumped(participant))")
        
        assert(callClient.participants.all[participant.id] == participant)
        
        updateParticipantViewControllers()
    }
    
    func callClient(
        _ callClient: CallClient,
        participantLeft participant: Participant,
        withReason reason: ParticipantLeftReason
    ) {
        logger.debug("Participant left:")
        logger.debug("\(dumped(participant))")
        logger.debug("\(reason)")
        
        assert(callClient.participants.all[participant.id] == nil)
        
        updateParticipantViewControllers()
    }
    
    func callClient(
        _ callClient: CallClient,
        activeSpeakerChanged activeSpeaker: Participant?
    ) {
        logger.debug("Active speaker changed:")
        logger.debug("\(dumped(activeSpeaker))")
        
        assert(callClient.activeSpeaker == activeSpeaker)
        
        updateParticipantViewControllers()
    }
    
    func callClient(
        _ callClient: CallClient,
        subscriptionsUpdated subscriptions: SubscriptionSettingsByID
    ) {
        logger.debug("Subscriptions updated:")
        logger.debug("\(dumped(subscriptions))")
        
        assert(callClient.subscriptions == subscriptions)
    }
    
    func callClient(
        _ callClient: CallClient,
        subscriptionProfilesUpdated subscriptionProfiles: SubscriptionProfileSettingsByProfile
    ) {
        logger.debug("Subscriptions profiles updated:")
        logger.debug("\(dumped(subscriptionProfiles))")
        
        assert(callClient.subscriptionProfiles == subscriptionProfiles)
    }
    
    func callClient(
        _ callClient: CallClient,
        availableDevicesUpdated availableDevices: Devices
    ) {
        refreshSelectedAudioDevice()
        
        assert(callClient.availableDevices == availableDevices)
    }
    
    func callClient(
        _ callClient: CallClient,
        appMessageAsJson jsonData: Data,
        from senderID: ParticipantID
    ) {
        let chatMessage: PrebuiltChatAppMessage

        logger.info("Got app message from \(senderID)")
        
        guard PrebuiltChatAppMessage.shouldExpectAppMessageToBePrebuiltChatMessage(jsonData) else {
            logger.info("Not a chat message")
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = dateDecodingStrategy
            chatMessage = try decoder.decode(
                PrebuiltChatAppMessage.self,
                from: jsonData
            )
        } catch {
            logger.error("Chat message decoding error: \(error)")

            return
        }

        logger.info("Got chat message \"\(chatMessage.message)\" from \"\(chatMessage.senderName)\" (\(senderID))")

        showPrebuiltChatAppMessageNotification(
            title: chatMessage.senderName,
            body: chatMessage.message
        )

        guard chatMessage.message.starts(with: "/echo") else {
            return
        }

        let messageData: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = dateEncodingStrategy
            messageData = try encoder.encode(
                PrebuiltChatAppMessage(
                    message: chatMessage.message,
                    senderName: callClient.username ?? "iOS Participant",
                    roomName: "main-room"
                )
            )
        } catch {
            logger.error("App message encoding error: \(error)")
            return
        }

        logger.info("Sending app message \"\(chatMessage.message)\"")

        callClient.sendAppMessage(json: messageData, to: .all) { result in
            if case .failure(let error) = result {
                logger.error("Failed to send app message: \(error)")
            }
        }
    }
    
    func callClient(
        _ callClient: CallClient,
        transcriptionMessage: TranscriptionMessage
    ) {
        logger.info("Got transcription message: \(transcriptionMessage)")
    }

    func callClient(
        _ callClient: CallClient,
        error: CallClientError
    ) {
        logger.error("Error: \(error)")
    }
}

extension CallViewController: UIPickerViewDelegate {
    func pickerView(
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

    func pickerView(
        _ pickerView: UIPickerView,
        rowHeightForComponent component: Int
    ) -> CGFloat {
        return 60
    }
}

extension CallViewController: UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }

    func pickerView(
        _ pickerView: UIPickerView,
        numberOfRowsInComponent component: Int
    ) -> Int {
        self.callClient.availableDevices.audio.count
    }
}
