import SwiftUI
import UIKit

struct ChatKnowledgeCardListView: View {
    let cards: [ChatKnowledgeCard]
    let knowledgeDependencies: KnowledgeFeatureDependencies
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    let onSave: (ChatKnowledgeCard) -> Void
    let onSaved: (ChatKnowledgeCard) -> Void
    let isSaving: (ChatKnowledgeCard) -> Bool
    let isSaved: (ChatKnowledgeCard) -> Bool

    @State private var copiedCardID: UUID?
    @State private var pendingOpen: PendingKnowledgeOpen?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(cards) { card in
                cardContent(card)
            }
        }
        .navigationDestination(item: $pendingOpen) { pending in
            KnowledgeDocumentDetailView(
                dependencies: knowledgeDependencies,
                viewModel: knowledgeViewModel,
                documentID: pending.documentID,
                initialEditMode: pending.initialEditMode,
                onSaved: {
                    if let card = pending.sourceCard {
                        onSaved(card)
                    }
                }
            )
            .hidesMainTabBarWhenPushed()
        }
    }

    private func cardContent(_ card: ChatKnowledgeCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(card.title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Image(systemName: "text.document")
                }
                .foregroundStyle(Color.accentColor)
                Spacer(minLength: 0)

                if card.showsSaveAndCopy {
                    Button {
                        UIPasteboard.general.string = plainText(from: card.content)
                        copiedCardID = card.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedCardID == card.id {
                                copiedCardID = nil
                            }
                        }
                    } label: {
                        Image(systemName: copiedCardID == card.id ? "checkmark" : "square.on.square")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                    .padding(6)
                    .background(Color.accentColor)
                    .clipShape(Capsule())

                    Button {
                        onSave(card)
                    } label: {
                        saveButtonLabel(card)
                    }
                    .disabled(isSaving(card) || isSaved(card))
                }
            }

            Divider()

            Text(plainText(from: card.content))
                .textSelection(.enabled)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)

            HStack{
                Spacer(minLength: 0)
                
                if canOpenDetail(card) {
                    Button {
                        Task { await open(card) }
                    } label: {
                        Label(L10n.text("chat.bubble.knowledge.open_detail"), systemImage: "arrow.forward.circle")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving(card))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.accentColor.opacity(0.2), radius: 1)
    }

    @ViewBuilder
    private func saveButtonLabel(_ card: ChatKnowledgeCard) -> some View {
        if isSaving(card) {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.75)
                Text(L10n.text("chat.bubble.knowledge.saving"))
            }
            .font(.caption)
            .padding(6)
            .background(Color(uiColor: .systemGray5))
            .foregroundStyle(.gray)
            .clipShape(Capsule())
        } else {
            HStack(spacing: 4) {
                Image(systemName: isSaved(card) ? "checkmark.circle.fill" : "backpack")
                Text(
                    isSaved(card)
                    ? L10n.text("chat.bubble.knowledge.saved_to_bag")
                    : L10n.text("chat.bubble.knowledge.save_to_bag")
                )
            }
            .font(.caption)
            .padding(6)
            .background(isSaved(card) ? Color(uiColor: .systemGray5) : Color.accentColor)
            .foregroundStyle(isSaved(card) ? .gray : .white)
            .clipShape(Capsule())
        }
    }

    private func open(_ card: ChatKnowledgeCard) async {
        if let documentID = card.documentID {
            pendingOpen = PendingKnowledgeOpen(documentID: documentID, initialEditMode: false, sourceCard: nil)
            return
        }
        guard card.showsSaveAndCopy else {
            return
        }
        guard let document = await knowledgeViewModel.saveDocument(
            id: nil,
            title: card.title,
            content: card.content,
            source: KnowledgeDocumentSource.tool
        ) else {
            return
        }
        pendingOpen = PendingKnowledgeOpen(documentID: document.id, initialEditMode: true, sourceCard: card)
    }

    private func canOpenDetail(_ card: ChatKnowledgeCard) -> Bool {
        card.documentID != nil || card.showsSaveAndCopy
    }

    private func plainText(from markdown: String) -> String {
        markdown
            .replacingOccurrences(of: #"\!\[[^\]]*\]\([^\)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[#>*`_~\-]{1,}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct PendingKnowledgeOpen: Identifiable, Equatable, Hashable {
    let documentID: UUID
    let initialEditMode: Bool
    let sourceCard: ChatKnowledgeCard?

    var id: UUID { documentID }

    static func == (lhs: PendingKnowledgeOpen, rhs: PendingKnowledgeOpen) -> Bool {
        lhs.documentID == rhs.documentID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(documentID)
    }
}
