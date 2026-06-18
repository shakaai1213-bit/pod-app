import Foundation
@preconcurrency import LiveKit

@MainActor
final class LiveKitVoiceConnection: NSObject, ObservableObject, RoomDelegate, @unchecked Sendable {
    @Published private(set) var state: RealtimeVoiceState = .disconnected
    @Published private(set) var activeRoomName: String?
    @Published private(set) var remoteParticipantCount: Int = 0
    /// Live microphone state for the always-on-mic + mute-toggle model
    /// (Tony decision 2026-06-16; push-to-talk retired). Mirrored into the
    /// ViewModel so the room control can show mic-live vs muted.
    @Published private(set) var isMicEnabled: Bool = false

    var onTranscript: ((RealtimeTranscriptSegment) -> Void)?

    private var room: Room?
    private var participantPollTask: Task<Void, Never>?

    var isConnected: Bool {
        if case .connected = state {
            return true
        }
        return false
    }

    func connect(session: OpenClawClient.LiveKitSession) async throws {
        if let room {
            room.remove(delegate: self)
            await room.disconnect()
        }
        participantPollTask?.cancel()
        participantPollTask = nil
        remoteParticipantCount = 0

        let nextRoom = Room()
        nextRoom.add(delegate: self)
        room = nextRoom
        activeRoomName = session.roomName
        state = .connecting(session.roomName)

        do {
            try await nextRoom.connect(
                url: session.livekitUrl,
                token: session.token,
                connectOptions: ConnectOptions(enableMicrophone: true)
            )
            // Always-on mic: enable on join. Logged so a silent mic failure
            // (the P0 regression mode) is caught rather than connecting mic-dead.
            try await applyMicrophone(enabled: true, on: nextRoom)
            updateParticipantState(room: nextRoom, roomName: session.roomName)
            startParticipantPolling()
        } catch {
            nextRoom.remove(delegate: self)
            await nextRoom.disconnect()
            participantPollTask?.cancel()
            participantPollTask = nil
            room = nil
            activeRoomName = nil
            remoteParticipantCount = 0
            isMicEnabled = false
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Toggle the microphone while connected (mute/unmute). Swallows errors so a
    /// failed toggle never tears down the call — the failure is logged and the
    /// published mic state stays truthful.
    func setMicrophone(enabled: Bool) async {
        guard let room else { return }
        do {
            try await applyMicrophone(enabled: enabled, on: room)
        } catch {
            // applyMicrophone already logged; keep the call alive.
        }
    }

    /// Single point that flips the LiveKit mic and the published state, with
    /// logging on both success and failure (directive: error handling at the
    /// setMicrophone call site).
    private func applyMicrophone(enabled: Bool, on room: Room) async throws {
        do {
            try await room.localParticipant.setMicrophone(enabled: enabled)
            isMicEnabled = enabled
            print("[LiveKitVoice] microphone set enabled=\(enabled)")
        } catch {
            print("[LiveKitVoice] setMicrophone(enabled: \(enabled)) FAILED: \(error.localizedDescription)")
            throw error
        }
    }

    func disconnect() async {
        guard let room else {
            activeRoomName = nil
            remoteParticipantCount = 0
            isMicEnabled = false
            state = .disconnected
            return
        }

        room.remove(delegate: self)
        await room.disconnect()
        participantPollTask?.cancel()
        participantPollTask = nil
        self.room = nil
        activeRoomName = nil
        remoteParticipantCount = 0
        isMicEnabled = false
        state = .disconnected
    }

    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor [weak self] in
            self?.handleRoomDidDisconnect(room: room, error: error)
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor [weak self] in
            self?.handleParticipantCountDidChange(room: room)
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor [weak self] in
            self?.handleParticipantCountDidChange(room: room)
        }
    }

    nonisolated func room(
        _ room: Room,
        participant: Participant,
        trackPublication: TrackPublication,
        didReceiveTranscriptionSegments segments: [TranscriptionSegment]
    ) {
        Task { @MainActor [weak self] in
            self?.handleTranscriptionSegments(segments, from: participant)
        }
    }

    private func startParticipantPolling() {
        participantPollTask?.cancel()
        participantPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let room = self.room, let roomName = self.activeRoomName else { return }
                self.updateParticipantState(room: room, roomName: roomName)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func updateParticipantState(room: Room, roomName: String) {
        remoteParticipantCount = room.remoteParticipants.count
        state = .connected(roomName, remoteParticipantCount: remoteParticipantCount)
    }

    private func handleRoomDidDisconnect(room: Room, error: LiveKitError?) {
        guard self.room === room else { return }

        room.remove(delegate: self)
        participantPollTask?.cancel()
        participantPollTask = nil
        self.room = nil
        activeRoomName = nil
        remoteParticipantCount = 0
        isMicEnabled = false
        state = error.map { .failed($0.localizedDescription) } ?? .disconnected
    }

    private func handleParticipantCountDidChange(room: Room) {
        guard self.room === room, let roomName = activeRoomName else { return }
        updateParticipantState(room: room, roomName: roomName)
    }

    private func handleTranscriptionSegments(_ segments: [TranscriptionSegment], from participant: Participant) {
        for segment in segments where !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onTranscript?(
                RealtimeTranscriptSegment(
                    segmentID: segment.id,
                    text: segment.text,
                    isFinal: segment.isFinal,
                    isAgent: participant.isAgent,
                    timestamp: segment.lastReceivedTime
                )
            )
        }
    }
}

struct RealtimeTranscriptSegment: Sendable {
    let segmentID: String
    let text: String
    let isFinal: Bool
    let isAgent: Bool
    let timestamp: Date
}

enum RealtimeVoiceState: Equatable {
    case disconnected
    case connecting(String)
    case connected(String, remoteParticipantCount: Int)
    case failed(String)

    var displayText: String {
        switch self {
        case .disconnected:
            return "LiveKit voice disconnected"
        case .connecting(let roomName):
            return "Joining LiveKit room: \(roomName)"
        case .connected(let roomName, let remoteParticipantCount):
            if remoteParticipantCount == 0 {
                return "Connected to \(roomName). Waiting for voice worker."
            }
            return "LiveKit voice connected: \(roomName) · \(remoteParticipantCount + 1) participants"
        case .failed(let reason):
            return "LiveKit voice failed: \(reason)"
        }
    }
}
