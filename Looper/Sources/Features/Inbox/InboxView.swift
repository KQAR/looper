import ComposableArchitecture
import SwiftUI

/// The default landing surface: a cross-pipeline queue of pending decisions.
/// Resolution happens on the card itself — any "open detail then act" flow
/// is a design failure (INTERACTION.md card rule 1).
@MainActor
struct InboxView: View {
    @Bindable var store: StoreOf<AppFeature>

    @State private var selectedCardID: InboxCard.ID?
    @State private var sendBackCardID: InboxCard.ID?
    @State private var sendBackReason = ""
    @FocusState private var isReasonFieldFocused: Bool

    private let lang = AppLanguageManager.shared

    var body: some View {
        Group {
            if store.inboxCards.isEmpty {
                emptyState
            } else {
                cardList
            }
        }
        .onChange(of: store.inboxCards.ids) {
            // Self-healing cards: drop interaction state whose card vanished.
            if let selectedCardID, store.inboxCards[id: selectedCardID] == nil {
                self.selectedCardID = nil
            }
            if selectedCardID == nil {
                selectedCardID = store.inboxCards.first?.id
            }
            if let sendBackCardID, store.inboxCards[id: sendBackCardID] == nil {
                self.sendBackCardID = nil
                sendBackReason = ""
            }
        }
        .onAppear {
            selectedCardID = store.inboxCards.first?.id
        }
    }

    // MARK: - Card list

    private var cardList: some View {
        List(selection: $selectedCardID) {
            Section {
                ForEach(store.inboxCards) { card in
                    cardRow(card)
                        .tag(card.id)
                }
            } header: {
                Text("inbox.section.needsYou", bundle: lang.bundle)
                    .font(.subheadline)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }

            Section {
                quietSummaryRow
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .onKeyPress(.return) {
            guard sendBackCardID == nil else { return .ignored }
            triggerPrimaryResolution()
            return .handled
        }
    }

    @ViewBuilder
    private func cardRow(_ card: InboxCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: statusSymbol(for: card))
                    .foregroundStyle(statusColor(for: card))

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let pipelineName = card.pipelineName {
                            Text(pipelineName)
                            Text(verbatim: "·")
                        }
                        Text(card.detail)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            if sendBackCardID == card.id {
                sendBackEditor(card)
            } else {
                actionRow(card)
            }
        }
        .padding(.vertical, 6)
    }

    private var quietSummaryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(
                String(
                    format: String(localized: "inbox.quietSummary", bundle: lang.bundle),
                    store.inboxQuietRunCount,
                    store.inboxBacklogCount
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .selectionDisabled()
    }

    // MARK: - Card anatomy

    private func statusSymbol(for card: InboxCard) -> String {
        switch card.kind {
        case .system: "wrench.and.screwdriver.fill"
        case .reviewRequest: "eye.circle.fill"
        case .failureEscalation: "xmark.circle.fill"
        }
    }

    private func statusColor(for card: InboxCard) -> Color {
        switch card.kind {
        case .system, .failureEscalation: .red
        case .reviewRequest: .orange
        }
    }

    @ViewBuilder
    private func actionRow(_ card: InboxCard) -> some View {
        HStack(spacing: 8) {
            switch card.kind {
            case .system:
                Button {
                    store.send(.runEnvironmentCheckButtonTapped)
                } label: {
                    Text("inbox.action.recheck", bundle: lang.bundle)
                }
                .buttonStyle(.glassProminent)

            case let .reviewRequest(taskID):
                Button {
                    store.send(.inboxApproveTapped(taskID))
                } label: {
                    Text("inbox.action.approve", bundle: lang.bundle)
                }
                .buttonStyle(.glassProminent)

                Button {
                    sendBackCardID = card.id
                    sendBackReason = ""
                    isReasonFieldFocused = true
                } label: {
                    Text("inbox.action.sendBack", bundle: lang.bundle)
                }
                .buttonStyle(.glass)

            case let .failureEscalation(taskID, _, worktreePath):
                Button {
                    store.send(.inboxRetryTapped(taskID))
                } label: {
                    Text("inbox.action.retry", bundle: lang.bundle)
                }
                .buttonStyle(.glassProminent)

                if let worktreePath {
                    Button {
                        store.send(.inboxRevealWorktreeTapped(path: worktreePath))
                    } label: {
                        Text("inbox.action.revealWorktree", bundle: lang.bundle)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .controlSize(.small)
    }

    /// Send-back requires a reason; it is delivered to the retry run as a
    /// steering note — never a bare rejection (INTERACTION.md review cards).
    @ViewBuilder
    private func sendBackEditor(_ card: InboxCard) -> some View {
        let trimmedReason = sendBackReason.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 8) {
            TextField(
                String(localized: "inbox.sendBack.placeholder", bundle: lang.bundle),
                text: $sendBackReason,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1 ... 3)
            .focused($isReasonFieldFocused)
            .onSubmit {
                confirmSendBack(card)
            }

            HStack(spacing: 8) {
                Button {
                    confirmSendBack(card)
                } label: {
                    Text("inbox.sendBack.confirm", bundle: lang.bundle)
                }
                .buttonStyle(.glassProminent)
                .disabled(trimmedReason.isEmpty)

                Button {
                    sendBackCardID = nil
                    sendBackReason = ""
                } label: {
                    Text("inbox.sendBack.cancel", bundle: lang.bundle)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.small)
        }
    }

    // MARK: - Resolutions

    private func confirmSendBack(_ card: InboxCard) {
        let reason = sendBackReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty, let taskID = card.taskID else { return }
        sendBackCardID = nil
        sendBackReason = ""
        store.send(.inboxSendBackConfirmed(taskID: taskID, reason: reason))
    }

    private func triggerPrimaryResolution() {
        guard let selectedCardID,
              let card = store.inboxCards[id: selectedCardID]
        else { return }
        switch card.kind {
        case .system:
            store.send(.runEnvironmentCheckButtonTapped)
        case let .reviewRequest(taskID):
            store.send(.inboxApproveTapped(taskID))
        case let .failureEscalation(taskID, _, _):
            store.send(.inboxRetryTapped(taskID))
        }
    }

    // MARK: - Empty states (three distinct meanings — INTERACTION.md)

    @ViewBuilder
    private var emptyState: some View {
        switch store.inboxEmptyContext {
        case .unconfigured:
            ContentUnavailableView {
                Label {
                    Text("inbox.empty.unconfigured.title", bundle: lang.bundle)
                } icon: {
                    Image(systemName: "square.stack.3d.up")
                }
            } description: {
                Text("inbox.empty.unconfigured.message", bundle: lang.bundle)
            } actions: {
                Button {
                    store.send(.newPipelineButtonTapped)
                } label: {
                    Text("inbox.empty.unconfigured.action", bundle: lang.bundle)
                }
                .buttonStyle(.glassProminent)
            }

        case .idle:
            ContentUnavailableView {
                Label {
                    Text("inbox.empty.idle.title", bundle: lang.bundle)
                } icon: {
                    Image(systemName: "tray")
                }
            } description: {
                Text("inbox.empty.idle.message", bundle: lang.bundle)
            } actions: {
                Button {
                    store.send(.openLocalTaskComposerButtonTapped)
                } label: {
                    Text("inbox.empty.idle.action", bundle: lang.bundle)
                }
                .buttonStyle(.glassProminent)
            }

        case .healthy:
            ContentUnavailableView {
                Label {
                    Text("inbox.empty.healthy.title", bundle: lang.bundle)
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            } description: {
                Text(
                    String(
                        format: String(localized: "inbox.empty.healthy.message", bundle: lang.bundle),
                        store.inboxQuietRunCount
                    )
                )
            }
        }
    }
}
