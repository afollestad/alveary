@MainActor
protocol NotificationManager: AnyObject {
    func handleEvent(_ event: ConversationEvent, providerName: String, threadName: String?)
}
