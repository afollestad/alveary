import Foundation

struct MCPServer: Identifiable, Sendable, Equatable {
    enum Transport: String, Sendable, Equatable, CaseIterable {
        case stdio
        case http
    }

    var id: String { name }

    let name: String
    let transport: Transport
    let command: String?
    let args: [String]?
    let url: String?
    let headers: [String: String]?
    let env: [String: String]?
    var providers: [String]
}
