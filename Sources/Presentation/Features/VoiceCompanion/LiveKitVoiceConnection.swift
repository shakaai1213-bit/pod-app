import Foundation
@preconcurrency import LiveKit

@MainActor
final class LiveKitVoiceConnection: ObservableObject {
    @Published private(set) var state: RealtimeVoiceState = .disconnected
    @Published private(set) var activeRoomName: String?
    @Published private(set) var remoteParticipantCount: Int = 0

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
            await room.disconnect()
        }
        participantPollTask?.cancel()
        participantPollTask = nil
        remoteParticipantCount = 0

        let nextRoom = Room()
        room = nextRoom
        activeRoomName = session.roomName
        state = .connecting(session.roomName)

        do {
            try await nextRoom.connect(
                url: session.livekitUrl,
                token: session.token,
                connectOptions: ConnectOptions(enableMicrophone: true)
            )
            try await nextRoom.localParticipant.setMicrophone(enabled: true)
            updateParticipantState(room: nextRoom, roomName: session.roomName)
            startParticipantPolling()
        } catch {
            participantPollTask?.cancel()
            participantPollTask = nil
            room = nil
            activeRoomName = nil
            remoteParticipantCount = 0
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func disconnect() async {
        guard let room else {
            activeRoomName = nil
            state = .disconnected
            return
        }

        await room.disconnect()
        participantPollTask?.cancel()
        participantPollTask = nil
        self.room = nil
        activeRoomName = nil
        remoteParticipantCount = 0
        state = .disconnected
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
                return "Connected to \(roomName). Waiting for Aloha worker."
            }
            return "LiveKit voice connected: \(roomName) · \(remoteParticipantCount + 1) participants"
        case .failed(let reason):
            return "LiveKit voice failed: \(reason)"
        }
    }
}
