import Foundation

/// Editable values are separate from SwiftData so Cancel cannot leak changes into autosave.
struct ProjectConfiguration: Equatable {
    var name: String = ""
    var folders: [SourceFolderSnapshot] = []
    var primaryFolderPath: String?

    init(name: String = "", folders: [SourceFolderSnapshot] = [], primaryFolderPath: String? = nil) {
        self.name = name
        self.folders = folders
        self.primaryFolderPath = primaryFolderPath ?? folders.first?.path
    }

    @MainActor
    init(project: Project) {
        name = project.name
        folders = project.orderedFolders.map(\.snapshot)
        primaryFolderPath = project.primaryFolder?.path
    }

    mutating func add(_ folder: SourceFolderSnapshot) throws {
        guard !folders.contains(where: { $0.path == folder.path }) else { throw ProjectConfigurationError.duplicateFolder(folder.path) }
        folders.append(folder)
        if primaryFolderPath == nil { primaryFolderPath = folder.path }
    }

    mutating func remove(path: String) {
        folders.removeAll { $0.path == path }
        if primaryFolderPath == path { primaryFolderPath = folders.first?.path }
    }

    func validated() throws -> Self {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty else { throw ProjectConfigurationError.nameRequired }
        var seen = Set<String>()
        for folder in folders {
            guard folder.path.hasPrefix("/"), URL(fileURLWithPath: folder.path).standardizedFileURL.path == folder.path else {
                throw ProjectConfigurationError.invalidFolder(folder.path)
            }
            guard seen.insert(folder.path).inserted else { throw ProjectConfigurationError.duplicateFolder(folder.path) }
        }
        if folders.isEmpty {
            result.primaryFolderPath = nil
        } else if let primaryFolderPath, !seen.contains(primaryFolderPath) {
            throw ProjectConfigurationError.invalidFolder(primaryFolderPath)
        } else {
            result.primaryFolderPath = primaryFolderPath ?? folders.first?.path
        }
        return result
    }
}

enum ProjectConfigurationError: LocalizedError {
    case nameRequired
    case duplicateFolder(String)
    case invalidFolder(String)

    var errorDescription: String? {
        switch self {
        case .nameRequired: "Enter a project name."
        case .duplicateFolder(let path): "This folder is already included: \(path)"
        case .invalidFolder(let path): "Choose a valid source folder: \(path)"
        }
    }
}
