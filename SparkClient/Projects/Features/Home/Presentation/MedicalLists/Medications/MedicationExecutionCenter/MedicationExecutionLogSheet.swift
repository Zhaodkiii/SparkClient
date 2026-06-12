import SwiftUI

struct MedicationExecutionLogSheet: View {
    let context: MedicationExecutionLogSheetContext
    let isSaving: Bool
    let fileTransferService: FileTransferService
    let onCancel: () -> Void
    let onDone: ([MedicationExecutionDose.ID: MedicationDoseLogStatus]) -> Void

    @State private var selections: [MedicationExecutionDose.ID: MedicationDoseLogStatus] = [:]

    private var canSubmit: Bool {
        selections.isEmpty == false && isSaving == false
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(spacing: 16) {
                        ForEach(context.doses) { dose in
                            MedicationExecutionLogDoseCard(
                                dose: dose,
                                fileTransferService: fileTransferService,
                                selection: selections[dose.id],
                                onSelect: { status in
                                    selections[dose.id] = status
                                    MedicationExecutionSupport.impact(style: .light)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .imageScale(.large)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    onDone(selections)
                } label: {
                    Text("完成")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .background(
                            canSubmit ? Color(uiColor: .systemBlue) : Color(uiColor: .systemGray3),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(canSubmit == false)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(.regularMaterial)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selections)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(MedicationExecutionSupport.logSheetDateTitle(context.date))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(context.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text("\(context.doses.count)种用药")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MedicationExecutionLogDoseCard: View {
    let dose: MedicationExecutionDose
    let fileTransferService: FileTransferService
    let selection: MedicationDoseLogStatus?
    let onSelect: (MedicationDoseLogStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                MedicationImageGlyph(
                    seed: dose.plan.id,
                    attachment: dose.imageAttachment,
                    fileTransferService: fileTransferService
                )
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(dose.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(dose.specificationText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Label {
                        Text(dose.instructionText)
                    } icon: {
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                    }
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBlue))
                    .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                statusButton(.skipped)
                statusButton(.taken)
            }
        }
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func statusButton(_ status: MedicationDoseLogStatus) -> some View {
        Button {
            onSelect(status)
        } label: {
            Label(status.title, systemImage: selection == status ? status.symbolName : "")
                .font(.headline.weight(.semibold))
                .foregroundStyle(selection == status ? .white : Color(uiColor: .systemBlue))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(
                    selection == status ? Color(uiColor: .systemBlue) : Color(uiColor: .systemBlue).opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}
