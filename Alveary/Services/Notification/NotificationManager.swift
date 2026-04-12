@MainActor
protocol NotificationManager: AnyObject, Sendable {
    func handleEvent(_ event: ConversationEvent, providerName: String, threadName: String?)
}
