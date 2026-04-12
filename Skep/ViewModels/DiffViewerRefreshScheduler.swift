import Foundation

@MainActor
final class DiffViewerRefreshScheduler<Request> {
    private var inFlightRequest: (id: UUID, task: Task<Void, Never>)?
    private var pendingRequest: Request?

    private let merge: (Request, Request) -> Request
    private let perform: @MainActor (Request) async -> Void

    init(
        merge: @escaping (Request, Request) -> Request,
        perform: @escaping @MainActor (Request) async -> Void
    ) {
        self.merge = merge
        self.perform = perform
    }

    func enqueue(_ request: Request) async {
        if let pendingRequest {
            self.pendingRequest = merge(pendingRequest, request)
        } else {
            pendingRequest = request
        }

        while true {
            if inFlightRequest == nil, let nextRequest = pendingRequest {
                pendingRequest = nil
                let requestID = UUID()
                let task = Task { @MainActor in
                    await perform(nextRequest)
                }
                inFlightRequest = (id: requestID, task: task)
            }

            guard let inFlightRequest else {
                return
            }

            let requestID = inFlightRequest.id
            let task = inFlightRequest.task
            await task.value

            if self.inFlightRequest?.id == requestID {
                self.inFlightRequest = nil
            }

            if pendingRequest == nil {
                return
            }
        }
    }

    func clearPending() {
        pendingRequest = nil
    }
}
