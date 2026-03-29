import Foundation
import UserNotifications
import UIKit

@Observable
final class PushNotificationService {
    static let shared = PushNotificationService()

    var isAuthorized: Bool = false
    var deviceToken: String?
    var pendingNotifications: [PendingNotification] = []

    #if targetEnvironment(simulator)
    private let baseURL = URL(string: "http://127.0.0.1:19002")!
    #else
    private let baseURL = URL(string: "http://shakas-mac-mini.tail82d30d.ts.net:8000")!
    #endif
    private let authToken = "ebe9a0fdfaf9b7674f4e2b9d0149f881d46111730b780d9e508ad94023c03051"

    private init() {
        Task { await checkAuthorizationStatus() }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run { isAuthorized = granted }
            return granted
        } catch {
            return false
        }
    }

    func checkAuthorizationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        await MainActor.run { isAuthorized = settings.authorizationStatus == .authorized }
    }

    // MARK: - Registration

    func registerForRemoteNotifications() {
        guard isAuthorized else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = token
        Task { await sendTokenToServer(token) }
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("[PushNotificationService] Failed to register: \(error.localizedDescription)")
    }

    // MARK: - Server Communication

    private func sendTokenToServer(_ token: String) async {
        let url = baseURL.appendingPathComponent("api/v1/push/register")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let payload: [String: String] = [
            "device_token": token,
            "platform": "apns"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 || http.statusCode == 201 {
                    print("[PushNotificationService] Token registered successfully")
                } else {
                    print("[PushNotificationService] Token registration failed: \(http.statusCode)")
                }
            }
        } catch {
            print("[PushNotificationService] Token registration error: \(error.localizedDescription)")
        }
    }

    func unregisterToken() async {
        guard let token = deviceToken else { return }

        let url = baseURL.appendingPathComponent("api/v1/push/unregister")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let payload: [String: String] = [
            "device_token": token,
            "platform": "apns"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                await MainActor.run { self.deviceToken = nil }
                print("[PushNotificationService] Token unregistered")
            }
        } catch {
            print("[PushNotificationService] Token unregister error: \(error.localizedDescription)")
        }
    }

    // MARK: - Notification Handling

    func handleNotification(userInfo: [AnyHashable: Any]) -> NotificationAction? {
        guard let type = userInfo["type"] as? String else {
            return nil
        }

        switch type {
        case "message.new":
            guard let channelIdString = userInfo["channel_id"] as? String,
                  let channelId = UUID(uuidString: channelIdString) else {
                return .unknown
            }
            let preview = userInfo["body"] as? String ?? userInfo["title"] as? String ?? ""
            return .newMessage(channelId: channelId, preview: preview)

        case "task.assigned":
            guard let taskIdString = userInfo["task_id"] as? String,
                  let taskId = UUID(uuidString: taskIdString) else {
                return .unknown
            }
            let title = userInfo["title"] as? String ?? ""
            return .taskAssigned(taskId: taskId, title: title)

        case "approval.requested":
            guard let approvalIdString = userInfo["approval_id"] as? String,
                  let approvalId = UUID(uuidString: approvalIdString) else {
                return .unknown
            }
            let message = userInfo["message"] as? String ?? ""
            return .approvalRequested(approvalId: approvalId, message: message)

        case "agent.error":
            guard let agentIdString = userInfo["agent_id"] as? String,
                  let agentId = UUID(uuidString: agentIdString) else {
                return .unknown
            }
            let error = userInfo["error"] as? String ?? ""
            return .agentError(agentId: agentId, error: error)

        default:
            return .unknown
        }
    }

    // MARK: - Foreground Presentation

    func handleNotificationForForeground(userInfo: [AnyHashable: Any]) async -> NotificationAction? {
        guard let action = handleNotification(userInfo: userInfo) else { return nil }

        if case .unknown = action {
            return action
        }

        let pending = PendingNotification(
            id: UUID(),
            action: action,
            receivedAt: Date(),
            isRead: false
        )

        await MainActor.run {
            pendingNotifications.append(pending)
            // Keep only last 50 pending
            if pendingNotifications.count > 50 {
                pendingNotifications.removeFirst(pendingNotifications.count - 50)
            }
        }

        return action
    }

    func markPendingAsRead(_ id: UUID) {
        if let index = pendingNotifications.firstIndex(where: { $0.id == id }) {
            pendingNotifications[index].isRead = true
        }
    }

    func clearPendingNotifications() {
        pendingNotifications.removeAll()
    }

    // MARK: - Badge Management

    func updateBadgeCount(_ count: Int) async {
        if #available(iOS 17.0, *) {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        } else {
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
        }
    }

    func clearBadges() async {
        await updateBadgeCount(0)
    }

    func syncBadgeCount() async {
        let unreadCount = pendingNotifications.filter { !$0.isRead }.count
        await updateBadgeCount(unreadCount)
    }

    // MARK: - Notification Categories (Rich Actions)

    func registerNotificationCategories() {
        let center = UNUserNotificationCenter.current()

        let markReadAction = UNNotificationAction(
            identifier: "MARK_READ",
            title: "Mark as Read",
            options: []
        )

        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Reply..."
        )

        let messageCategory = UNNotificationCategory(
            identifier: "MESSAGE",
            actions: [markReadAction, replyAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        let taskCategory = UNNotificationCategory(
            identifier: "TASK",
            actions: [markReadAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        let approvalCategory = UNNotificationCategory(
            identifier: "APPROVAL",
            actions: [markReadAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        let agentCategory = UNNotificationCategory(
            identifier: "AGENT_ERROR",
            actions: [markReadAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        center.setNotificationCategories([messageCategory, taskCategory, approvalCategory, agentCategory])
    }
}
