/// Which branch a Git-modal action targets. Shared by the commit modal and the
/// create-pull-request modal, which render the same branch menu.
enum DiffBranchSelection: Equatable {
    case base
    /// Act on the branch already checked out, when that is not the base branch.
    /// This is the default off-base choice: the checkout is already where the
    /// user wants to work, so no branch name is needed.
    case current
    case new
}
