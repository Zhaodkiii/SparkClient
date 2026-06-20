import SwiftUI

struct MemberNameBirthStepView: View {
    @Binding var draft: MemberSetupDraft
    let canAdvance: Bool
    let onNext: () -> Void

    @State private var showDatePicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MemberSetupStepHeaderView(
                    title: L10n.text("home.members.add.title"),
                    subtitle: L10n.text("home.members.add.subtitle", fallback: "先填写成员的基础信息"),
                    step: 1,
                    total: 3
                )

                MemberSetupSection(title: L10n.text("home.members.field.basic_info", fallback: "基本信息")) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("home.members.field.name"))
                                .font(.subheadline.weight(.semibold))
                            TextField(L10n.text("home.members.field.name_placeholder"), text: $draft.name)
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .systemBackground)))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("home.members.field.birth_date"))
                                .font(.subheadline.weight(.semibold))
                            Button {
                                showDatePicker = true
                                triggerHaptic(style: .light)
                            } label: {
                                HStack {
                                    Text(formattedBirthDate)
                                        .foregroundStyle(draft.birthDate == nil ? .secondary : .primary)
                                    Spacer()
                                    Image(systemName: "calendar")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .systemBackground)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.members.add.title"))
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: L10n.text("common.next", fallback: "下一步"),
            primaryEnabled: canAdvance,
            onPrimary: onNext
        )
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(
                selectedDate: Binding(
                    get: { draft.birthDate },
                    set: { draft.birthDate = $0 }
                ),
                datePickerSheetHeight: 300
            )
        }
    }

    private var formattedBirthDate: String {
        guard let birthDate = draft.birthDate else {
            return L10n.text("home.members.field.birth_date_placeholder")
        }
        return birthDate.formatted(date: .long, time: .omitted)
    }

    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }
}

private struct DatePickerSheet: View {
    @Binding var selectedDate: Date?
    let datePickerSheetHeight: CGFloat

    @State private var tempDate: Date

    init(selectedDate: Binding<Date?>, datePickerSheetHeight: CGFloat) {
        self._selectedDate = selectedDate
        self.datePickerSheetHeight = datePickerSheetHeight
        self._tempDate = State(initialValue: selectedDate.wrappedValue ?? Calendar.current.date(byAdding: .year, value: -24, to: Date()) ?? Date())
    }

    var body: some View {
        AdaptiveSheetContainer.fixed(
            height: datePickerSheetHeight,
            cancelTitle: L10n.text("common.cancel"),
            confirmTitle: L10n.text("common.done"),
            cancelColor: .secondary,
            confirmColor: .accentColor,
            onCancel: {},
            onConfirm: {
                selectedDate = tempDate
            }
        ) {
            DatePicker(
                L10n.text("home.members.field.birth_date"),
                selection: $tempDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
