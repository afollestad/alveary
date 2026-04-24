import Foundation
import SwiftData

extension DefaultClaudeHookServer {
    func recordSessionApproval(_ approval: AgentSessionApprovalGrant) -> SessionApprovalRecordResult {
        guard let context = sessionApprovalContext() else {
            return SessionApprovalRecordResult(isEffective: false, wasInserted: false)
        }

        let providerId = approval.providerId
        let conversationId = approval.conversationId
        let sessionId = approval.sessionId
        let matchKind = approval.matchKind.rawValue
        let matchValue = approval.matchValue
        let existingRules = (try? context.fetch(
            FetchDescriptor<AgentSessionApprovalRule>(
                predicate: #Predicate {
                    $0.providerId == providerId &&
                        $0.conversationId == conversationId &&
                        $0.sessionId == sessionId &&
                        $0.matchKind == matchKind &&
                        $0.matchValue == matchValue
                }
            )
        )) ?? []
        guard existingRules.isEmpty else {
            return SessionApprovalRecordResult(isEffective: true, wasInserted: false)
        }

        let rule = AgentSessionApprovalRule(
            providerId: approval.providerId,
            conversationId: approval.conversationId,
            sessionId: approval.sessionId,
            matchKind: approval.matchKind.rawValue,
            matchValue: approval.matchValue
        )
        context.insert(rule)
        do {
            try context.save()
            return SessionApprovalRecordResult(isEffective: true, wasInserted: true)
        } catch {
            context.delete(rule)
            return SessionApprovalRecordResult(isEffective: false, wasInserted: false)
        }
    }

    func discardSessionApproval(_ approval: AgentSessionApprovalGrant) {
        guard let context = sessionApprovalContext() else {
            return
        }

        let providerId = approval.providerId
        let conversationId = approval.conversationId
        let sessionId = approval.sessionId
        let matchKind = approval.matchKind.rawValue
        let matchValue = approval.matchValue
        let matchingRules = (try? context.fetch(
            FetchDescriptor<AgentSessionApprovalRule>(
                predicate: #Predicate {
                    $0.providerId == providerId &&
                        $0.conversationId == conversationId &&
                        $0.sessionId == sessionId &&
                        $0.matchKind == matchKind &&
                        $0.matchValue == matchValue
                }
            )
        )) ?? []
        guard !matchingRules.isEmpty else {
            return
        }

        for rule in matchingRules {
            context.delete(rule)
        }
        try? context.save()
    }

    func toolApprovalSelection(
        providerId: String,
        conversationId: String,
        sessionId: String
    ) -> ToolApprovalSelection? {
        guard let context = sessionApprovalContext() else {
            return nil
        }

        let records = (try? context.fetch(
            FetchDescriptor<AgentSessionApprovalSelection>(
                predicate: #Predicate {
                    $0.providerId == providerId &&
                        $0.conversationId == conversationId &&
                        $0.sessionId == sessionId
                },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        )) ?? []
        guard let record = records.first else {
            return nil
        }
        return ToolApprovalSelection(rawValue: record.selection)
    }

    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        providerId: String,
        conversationId: String,
        sessionId: String
    ) {
        guard let context = sessionApprovalContext() else {
            return
        }

        let existingRecords = (try? context.fetch(
            FetchDescriptor<AgentSessionApprovalSelection>(
                predicate: #Predicate {
                    $0.providerId == providerId &&
                        $0.conversationId == conversationId &&
                        $0.sessionId == sessionId
                }
            )
        )) ?? []
        if let record = existingRecords.first {
            record.selection = selection.rawValue
            record.updatedAt = Date()
            for duplicate in existingRecords.dropFirst() {
                context.delete(duplicate)
            }
        } else {
            context.insert(
                AgentSessionApprovalSelection(
                    providerId: providerId,
                    conversationId: conversationId,
                    sessionId: sessionId,
                    selection: selection.rawValue
                )
            )
        }
        try? context.save()
    }

    func removeSessionApprovals(conversationId: String, sessionId: String) {
        transientApprovalDecisions = transientApprovalDecisions.filter {
            $0.key.conversationId != conversationId || $0.key.sessionId != sessionId
        }

        guard let context = sessionApprovalContext() else {
            return
        }

        let providerId = "claude"
        let existingRules = (try? context.fetch(
            FetchDescriptor<AgentSessionApprovalRule>(
                predicate: #Predicate {
                    $0.providerId == providerId &&
                        $0.conversationId == conversationId &&
                        $0.sessionId == sessionId
                }
            )
        )) ?? []
        for rule in existingRules {
            context.delete(rule)
        }

        let existingSelections = (try? context.fetch(
            FetchDescriptor<AgentSessionApprovalSelection>(
                predicate: #Predicate {
                    $0.providerId == providerId &&
                        $0.conversationId == conversationId &&
                        $0.sessionId == sessionId
                }
            )
        )) ?? []
        for selection in existingSelections {
            context.delete(selection)
        }

        guard !existingRules.isEmpty || !existingSelections.isEmpty else {
            return
        }
        try? context.save()
    }
}
