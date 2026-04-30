import Foundation

@MainActor
extension DiffWorkspaceStore {
    func applySelection(
        _ file: FileStatus,
        behavior: DiffViewerFileSelectionBehavior
    ) -> FileStatus? {
        let key = DiffViewerFileSelectionKey(file)
        let clickedIndex = files.firstIndex { DiffViewerFileSelectionKey($0) == key }

        switch behavior {
        case .single:
            selectedFileKeys = [key]
            selectionAnchorKey = key
            return file

        case .toggle:
            if selectedFileKeys.contains(key) {
                selectedFileKeys.remove(key)
                selectionAnchorKey = key

                guard selectedFile.map(DiffViewerFileSelectionKey.init) == key else {
                    return selectedFile
                }
                return nearestSelectedFile(to: clickedIndex)
            } else {
                selectedFileKeys.insert(key)
                selectionAnchorKey = key
                return file
            }

        case .range:
            selectedFileKeys = selectionRangeKeys(to: key)
            return file

        case .rangeUnion:
            selectedFileKeys.formUnion(selectionRangeKeys(to: key))
            return file
        }
    }

    func selectAdjacentFile(
        forward: Bool,
        in directory: String
    ) async -> Bool {
        guard let target = activeTarget, target.directory == directory,
              let nextFile = adjacentFile(forward: forward, in: directory) else {
            return false
        }

        guard let preparedSelection = selectFileImmediately(nextFile, in: target.directory, behavior: .single) else {
            return false
        }

        await loadSelectedFileDiff(preparedSelection)
        return true
    }

    func adjacentFile(
        forward: Bool,
        in directory: String
    ) -> FileStatus? {
        guard let target = activeTarget, target.directory == directory else {
            return nil
        }

        let currentIndex = keyboardNavigationAnchorIndex()
        guard let nextIndex = diffViewerAdjacentIndex(in: files.indices, from: currentIndex, forward: forward) else {
            return nil
        }

        return files[nextIndex]
    }

    func reconcileSelectionAfterStatusRefresh(previousSelectedFiles: [FileStatus]) {
        let availableKeys = Set(files.map(DiffViewerFileSelectionKey.init))
        // Prefer exact row keys, then fall back through path/original-path matching so
        // refreshes and Git mutations preserve selection through renames and staging moves.
        let reconciledKeys = previousSelectedFiles.reduce(into: Set<DiffViewerFileSelectionKey>()) { keys, selectedFile in
            let selectedKey = DiffViewerFileSelectionKey(selectedFile)
            if availableKeys.contains(selectedKey) {
                keys.insert(selectedKey)
            } else if let updatedSelection = updatedSelection(matching: selectedFile) {
                keys.insert(DiffViewerFileSelectionKey(updatedSelection))
            }
        }
        selectedFileKeys = reconciledKeys

        if let selectionAnchorKey,
           !availableKeys.contains(selectionAnchorKey) {
            self.selectionAnchorKey = selectionAnchor(previousSelectedFiles: previousSelectedFiles)
        }
    }

    func updatedSelection(matching selectedFile: FileStatus) -> FileStatus? {
        let selectedAnchor = selectedFile.originalPath ?? selectedFile.path
        return files.first {
            $0.path == selectedFile.path && $0.isStaged == selectedFile.isStaged
        } ?? files.first {
            $0.path == selectedFile.path
        } ?? files.first {
            ($0.originalPath ?? $0.path) == selectedAnchor && $0.isStaged == selectedFile.isStaged
        } ?? files.first {
            ($0.originalPath ?? $0.path) == selectedAnchor
        }
    }

    func updateSelectionKey(from oldSelection: FileStatus, to updatedSelection: FileStatus) {
        selectedFileKeys.remove(DiffViewerFileSelectionKey(oldSelection))
        selectedFileKeys.insert(DiffViewerFileSelectionKey(updatedSelection))
    }

    func shouldReloadDiffPreview(
        from selectedFile: FileStatus,
        to updatedSelection: FileStatus,
        reason: DiffViewerRefreshReason
    ) -> Bool {
        let selectionChanged = updatedSelection.path != selectedFile.path
            || updatedSelection.originalPath != selectedFile.originalPath
            || updatedSelection.isStaged != selectedFile.isStaged
            || updatedSelection.status != selectedFile.status

        switch reason {
        case .manual, .appBecameActive, .localGitMutation:
            return true
        case .threadSwitch, .agentTurnCompleted, .idlePoll:
            return selectionChanged
        case .fsEvent(let changedPaths):
            let selectedPaths = Set([updatedSelection.path, updatedSelection.originalPath].compactMap { $0 })
            return selectionChanged || !changedPaths.isDisjoint(with: selectedPaths)
        }
    }
}

private extension DiffWorkspaceStore {
    func keyboardNavigationAnchorIndex() -> Int? {
        if let selectedFile {
            let selectedKey = DiffViewerFileSelectionKey(selectedFile)
            if selectedFileKeys.contains(selectedKey),
               let index = files.firstIndex(where: { DiffViewerFileSelectionKey($0) == selectedKey }) {
                return index
            }
        }

        guard selectedFileKeys.count == 1,
              let selectedKey = selectedFileKeys.first else {
            return nil
        }

        return files.firstIndex { DiffViewerFileSelectionKey($0) == selectedKey }
    }

    func selectionAnchor(previousSelectedFiles: [FileStatus]) -> DiffViewerFileSelectionKey? {
        let previousAnchorFile = previousSelectedFiles.first { DiffViewerFileSelectionKey($0) == selectionAnchorKey }
        if let previousAnchorFile,
           let updatedAnchor = updatedSelection(matching: previousAnchorFile) {
            return DiffViewerFileSelectionKey(updatedAnchor)
        }
        return selectedFiles.first.map(DiffViewerFileSelectionKey.init)
    }

    func selectionRangeKeys(to key: DiffViewerFileSelectionKey) -> Set<DiffViewerFileSelectionKey> {
        let anchorKey = selectionAnchorKey ?? key
        if selectionAnchorKey == nil {
            selectionAnchorKey = anchorKey
        }
        // If refreshes removed the anchor row, reset to the clicked row instead of
        // guessing across a potentially reordered file list.
        guard let anchorIndex = files.firstIndex(where: { DiffViewerFileSelectionKey($0) == anchorKey }),
              let clickedIndex = files.firstIndex(where: { DiffViewerFileSelectionKey($0) == key }) else {
            selectionAnchorKey = key
            return [key]
        }

        let range = min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)
        return Set(files[range].map(DiffViewerFileSelectionKey.init))
    }

    func nearestSelectedFile(to index: Int?) -> FileStatus? {
        let selectedKeys = selectedFileKeys
        guard !selectedKeys.isEmpty else {
            return nil
        }
        guard let index else {
            return files.first { selectedKeys.contains(DiffViewerFileSelectionKey($0)) }
        }

        // When toggling off the preview row, keep the lower pane anchored to the
        // closest remaining selected row to match standard list behavior.
        let orderedDistances = files.indices
            .filter { selectedKeys.contains(DiffViewerFileSelectionKey(files[$0])) }
            .map { (index: $0, distance: abs($0 - index)) }
            .sorted {
                if $0.distance == $1.distance {
                    return $0.index < $1.index
                }
                return $0.distance < $1.distance
            }

        guard let nearestIndex = orderedDistances.first?.index else {
            return nil
        }
        return files[nearestIndex]
    }
}

func diffViewerAdjacentIndex(
    in indices: Range<Int>,
    from currentIndex: Int?,
    forward: Bool
) -> Int? {
    guard !indices.isEmpty else {
        return nil
    }

    let nextIndex: Int
    if forward {
        nextIndex = (currentIndex ?? indices.lowerBound - 1) + 1
    } else {
        guard let currentIndex else {
            return nil
        }
        nextIndex = currentIndex - 1
    }

    guard indices.contains(nextIndex) else {
        return nil
    }
    return nextIndex
}
