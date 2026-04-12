import AVFoundation
import Speech
import Combine

enum SpeechRecorderError: Error {
    case notAuthorized
    case audioSessionFailed
    case recognizerFailed
    case noResult
}

@MainActor
final class SpeechRecorder: ObservableObject {
    @Published private(set) var partialTranscript: String = ""
    @Published private(set) var isRecording: Bool = false
    @Published var error: SpeechRecorderError?

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init(locale: Locale = .current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startRecording() throws {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechRecorderError.recognizerFailed
        }

        // Cancel any existing task
        stopRecording()

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request (on-device for faster results)
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            throw SpeechRecorderError.recognizerFailed
        }

        request.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request.requiresOnDeviceRecognition = true
        }

        // Set up audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    self.partialTranscript = result.bestTranscription.formattedString
                }

                if error != nil || (result?.isFinal ?? false) {
                    // Recognition completed (button released)
                }
            }
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        partialTranscript = ""
    }

    @discardableResult
    func stopRecording() -> String {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false

        let transcript = partialTranscript
        partialTranscript = ""
        return transcript
    }

    func cancel() {
        stopRecording()
        partialTranscript = ""
    }
}
