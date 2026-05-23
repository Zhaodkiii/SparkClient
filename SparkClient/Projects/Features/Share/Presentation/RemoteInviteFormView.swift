import SwiftUI

struct RemoteInviteFormView: View {
    let memberID: Int
    let inviteUseCase: MemberInviteUseCase
    var selectedPermission: MemberSharePermission = .edit

    @State private var contact = ""
    @State private var phoneModel = PhoneNumberInputModel()
    @State private var channel: InviteChannel = .phone
    @State private var sendState: SendState = .idle
    @FocusState private var emailFocused: Bool

    enum InviteChannel: String, CaseIterable, Identifiable {
        case phone
        case email

        var id: String { rawValue }

        var title: String {
            switch self {
            case .phone:
                return L10n.text("home.members.invite.channel.phone")
            case .email:
                return L10n.text("home.members.invite.channel.email")
            }
        }
    }

    enum SendState: Equatable {
        case idle
        case sending
        case sent(displayMessage: String, channel: String)
        case partialSuccess(String)
        case failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if case .sent = sendState {
                EmptyView()
            } else if case .partialSuccess = sendState {
                EmptyView()
            } else {
                Picker(L10n.text("home.members.invite.channel.title"), selection: $channel) {
                    ForEach(InviteChannel.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if channel == .phone {
                    PhoneNumberInputView(model: $phoneModel)
                } else {
                    TextField(L10n.text("home.members.invite.contact_placeholder"), text: $contact)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($emailFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                }
            }

            feedbackView

            if case .idle = sendState {
                sendButton
            } else if case .failed = sendState {
                sendButton
            } else if case .sending = sendState {
                sendButton
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.text("common.done")) {
                    emailFocused = false
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackView: some View {
        switch sendState {
        case .idle:
            EmptyView()
        case .sending:
            HStack(spacing: 8) {
                ProgressView()
                Text(L10n.text("home.members.invite.remote.sending"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .sent(let message, _):
            Text(message.isEmpty ? L10n.text("home.members.invite.sent") : message)
                .font(.footnote)
                .foregroundStyle(.green)
        case .partialSuccess(let message):
            Text(message.isEmpty ? L10n.text("home.members.invite.remote.notify_failed") : message)
                .font(.footnote)
                .foregroundStyle(.orange)
        case .failed:
            Text(L10n.text("home.members.permission_denied"))
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private var sendButton: some View {
        Button {
            Task { await sendInvite() }
        } label: {
            HStack {
                Spacer()
                if case .sending = sendState {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(L10n.text("home.members.invite.remote.send"))
                        .font(.headline.weight(.semibold))
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .background(canSend ? Color.accentColor : Color(uiColor: .systemGray3))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSend || sendState == .sending)
    }

    private var canSend: Bool {
        switch channel {
        case .phone:
            return phoneModel.isValid
        case .email:
            return !contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func sendInvite() async {
        guard canSend else { return }
        sendState = .sending

        let contactValue: String
        let phone: String?
        let countryCode: String?
        switch channel {
        case .phone:
            contactValue = phoneModel.e164
            phone = phoneModel.nationalNumber
            countryCode = phoneModel.countryCode
        case .email:
            contactValue = contact.trimmingCharacters(in: .whitespacesAndNewlines)
            phone = nil
            countryCode = nil
        }

        do {
            let response = try await inviteUseCase.invite(
                memberID: memberID,
                channel: channel.rawValue,
                contact: contactValue,
                permission: selectedPermission.rawValue,
                phone: phone,
                countryCode: countryCode
            )
            let ch = response.deliveryChannel ?? "none"
            if ch == "none" {
                sendState = .partialSuccess(response.displayMessage ?? L10n.text("home.members.invite.remote.notify_failed"))
            } else {
                sendState = .sent(
                    displayMessage: response.displayMessage ?? L10n.text("home.members.invite.sent"),
                    channel: ch
                )
            }
        } catch {
            let message = String(describing: error)
            if message.contains("permission_denied") {
                sendState = .failed
            } else if message.contains("already_bound") {
                sendState = .sent(displayMessage: L10n.text("home.members.bind.already_bound"), channel: "")
            } else if message.contains("user_not_found") {
                sendState = .partialSuccess(L10n.text("home.members.invite.user_not_found"))
            } else {
                sendState = .failed
            }
        }
    }
}
