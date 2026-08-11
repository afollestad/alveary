extension Skill {
    var autocompleteScopeLabel: String {
        if let repo, !repo.isEmpty {
            return repo
        }
        if let owner, !owner.isEmpty {
            return owner
        }
        return "Personal"
    }
}
