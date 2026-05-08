import SwiftUI

/// 单药卡片：与 HealthClient `MedicationCard` 保持相同信息分区，当前只做 UI 展示。
struct MedicationCard: View {
    let item: SparkMedicalSyncAPI.RemoteMedication
    var medicalCaseID: Int? = nil
    let workflowAPI: SparkMedicalWorkflowAPI
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let fileTransferService: FileTransferService
    @ObservedObject var memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient
    var onBatchMedicalCaseLinked: ((SparkMedicalSyncAPI.RemotePrescriptionBatchComplete) -> Void)? = nil
    var onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)? = nil
    var onMedicalCaseDeleted: ((Int) -> Void)? = nil

    @State private var isExpanded = false
    @State private var linkedMedicalCaseID: Int?
    @State private var medicalCaseRoute: MedicalCaseLinkRoute?
    @State private var isUpdatingMedicalCaseLink = false

    init(
        item: SparkMedicalSyncAPI.RemoteMedication,
        medicalCaseID: Int? = nil,
        workflowAPI: SparkMedicalWorkflowAPI,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        fileTransferService: FileTransferService,
        memberContextStore: MemberContextStore,
        notificationClient: any NotificationClient,
        onBatchMedicalCaseLinked: ((SparkMedicalSyncAPI.RemotePrescriptionBatchComplete) -> Void)? = nil,
        onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)? = nil,
        onMedicalCaseDeleted: ((Int) -> Void)? = nil
    ) {
        self.item = item
        self.medicalCaseID = medicalCaseID
        self.workflowAPI = workflowAPI
        self.completeData = completeData
        self.fileTransferService = fileTransferService
        self.memberContextStore = memberContextStore
        self.notificationClient = notificationClient
        self.onBatchMedicalCaseLinked = onBatchMedicalCaseLinked
        self.onMedicalCaseUpdated = onMedicalCaseUpdated
        self.onMedicalCaseDeleted = onMedicalCaseDeleted
        _linkedMedicalCaseID = State(initialValue: medicalCaseID)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private var dateText: String {
        Self.dateFormatter.string(from: item.updatedAt)
    }

    private var endDateText: String? {
        guard let durationDays = item.durationDays, durationDays > 0 else { return nil }
        let endDate = Calendar.current.date(byAdding: .day, value: durationDays, to: item.updatedAt)
        return endDate.map { Self.dateFormatter.string(from: $0) }
    }

    private var statusBadge: (text: String, color: Color) {
        if item.durationDays == 0 {
            return (L10n.text("home.medical.list.medications.status.completed"), Color(uiColor: .systemGray))
        }
        if item.reminderEnabled == false && item.reminderTimes.isEmpty {
            return (L10n.text("home.medical.list.medications.status.paused"), Color(uiColor: .systemOrange))
        }
        return (L10n.text("home.medical.list.medications.status.active"), Color(uiColor: .systemGreen))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(16)
                .background(Color(uiColor: .systemBackground))
                .overlay(alignment: .bottom) {
                    Divider()
                        .background(Color(uiColor: .separator).opacity(0.1))
                }

            quickInfoSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBlue).opacity(0.05))
                .overlay(alignment: .bottom) {
                    Divider()
                        .background(Color(uiColor: .systemBlue).opacity(0.1))
                }

            collapsibleDetailSection
            linkedMedicalCaseSection
            reminderSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground))
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.72))
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .onChange(of: medicalCaseID) { newValue in
            linkedMedicalCaseID = newValue
        }
        .fullScreenCover(item: $medicalCaseRoute) { route in
            switch route {
            case .detail(let medicalCaseID):
                CompatibleNavigationContainer {
                    LinkedMedicalCaseDetailPage(
                        medicalCaseID: medicalCaseID,
                        completeData: completeData,
                        workflowAPI: workflowAPI,
                        fileTransferService: fileTransferService,
                        memberContextStore: memberContextStore,
                        notificationClient: notificationClient,
                        onUpdated: { onMedicalCaseUpdated?($0) },
                        onDeleted: { onMedicalCaseDeleted?($0) }
                    )
                }
            case .associate:
                MedicalResourceAssociateMedicalCaseView(
                    memberID: item.member,
                    resourceKind: .prescriptionBatches,
                    resourceID: item.batch,
                    patchField: .medicalCase,
                    workflowAPI: workflowAPI
                ) { (updatedBatch: SparkMedicalSyncAPI.RemotePrescriptionBatch, selectedCase) in
                    linkedMedicalCaseID = selectedCase.id
                    onBatchMedicalCaseLinked?(SparkMedicalSyncAPI.RemotePrescriptionBatchComplete(
                        id: updatedBatch.id,
                        member: updatedBatch.member,
                        medicalCase: updatedBatch.medicalCase,
                        prescriberName: updatedBatch.prescriberName,
                        institutionName: updatedBatch.institutionName,
                        prescribedAt: updatedBatch.prescribedAt,
                        diagnosis: updatedBatch.diagnosis,
                        batchNo: updatedBatch.batchNo,
                        status: updatedBatch.status,
                        auditorName: updatedBatch.auditorName,
                        auditedAt: updatedBatch.auditedAt,
                        extra: updatedBatch.extra,
                        createdAt: nil,
                        updatedAt: updatedBatch.updatedAt,
                        medications: [item],
                        attachments: nil
                    ))
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(uiColor: .systemBlue).opacity(0.8), Color(uiColor: .systemBlue).opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

                    Image(systemName: "pills.fill")
                        .font(.title3)
                        .foregroundStyle(Color.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.drugName.nonEmpty ?? item.genericName.nonEmpty ?? "")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text(statusBadge.text)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusBadge.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(dateText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Spacer()

                NavigationLink {
                    MedicationDetailPage(item: item)
                        .hidesMainTabBarWhenPushed()
                } label: {
                    HStack(spacing: 4) {
                        Text(L10n.text("home.medical.list.medications.view_detail"))
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text(L10n.text("home.medical.list.medications.specification"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(item.strength.nonEmpty ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(L10n.text("home.medical.list.medications.dose_short"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(item.dosePerTime.nonEmpty ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Quick Info

    private var quickInfoSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(L10n.text("home.medical.list.medications.frequency_title"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.frequencyText.nonEmpty ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.instructions.isEmpty == false {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(L10n.text("home.medical.list.medications.instructions_title"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.instructions)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Detail

    private var collapsibleDetailSection: some View {
        VStack(spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Text(L10n.text("home.medical.list.medications.detail_title"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) {
                Divider()
                    .background(Color(uiColor: .separator).opacity(0.1))
            }

            if isExpanded {
                detailInfoContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .systemBackground))
                    .overlay(alignment: .bottom) {
                        Divider()
                            .background(Color(uiColor: .separator).opacity(0.1))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var detailInfoContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if item.dosageForm.nonEmpty != nil {
                detailBlock(
                    icon: "pills.circle",
                    title: L10n.text("home.medical.list.medications.form_title"),
                    value: item.dosageForm
                )
            }

            if item.route.nonEmpty != nil {
                detailBlock(
                    icon: "cross.case.fill",
                    title: L10n.text("home.medical.list.medications.route_title"),
                    value: item.route
                )
            }

            if item.durationDays != nil {
                detailBlock(
                    icon: "calendar",
                    title: L10n.text("home.medical.list.medications.duration_title"),
                    value: item.durationDays.map { String(format: L10n.text("home.medical.list.medications.duration_value"), $0) } ?? ""
                )
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("home.medical.list.medications.start_date"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dateText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let endDateText {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("home.medical.list.medications.end_date"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(endDateText)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func detailBlock(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Link

    private var linkedMedicalCaseSection: some View {
        MedicalCaseLinkRow(
            medicalCaseID: linkedMedicalCaseID,
            linkedTitle: L10n.text("home.medical.list.medications.linked_case.title"),
            linkedSubtitle: L10n.text("home.medical.list.medications.linked_case.subtitle"),
            unlinkedTitle: L10n.text("home.medical.list.medications.unlinked_case.title"),
            unlinkedSubtitle: L10n.text("home.medical.list.medications.unlinked_case.subtitle"),
            detailAction: {
                if let linkedMedicalCaseID {
                    medicalCaseRoute = .detail(linkedMedicalCaseID)
                }
            },
            switchAction: {
                if item.batch > 0 {
                    medicalCaseRoute = .associate
                }
            },
            unlinkAction: {
                Task { await unlinkMedicalCase() }
            }
        ) {
            if let linkedMedicalCaseID {
                medicalCaseRoute = .detail(linkedMedicalCaseID)
            } else if item.batch > 0 {
                medicalCaseRoute = .associate
            }
        }
    }

    @MainActor
    private func unlinkMedicalCase() async {
        guard isUpdatingMedicalCaseLink == false, item.batch > 0 else { return }
        isUpdatingMedicalCaseLink = true
        defer { isUpdatingMedicalCaseLink = false }

        do {
            let updatedBatch: SparkMedicalSyncAPI.RemotePrescriptionBatch = try await workflowAPI.update(
                SparkMedicalSyncAPI.RemotePrescriptionBatch.self,
                kind: .prescriptionBatches,
                id: item.batch,
                body: MedicalCaseLinkPatch(field: .medicalCase, medicalCaseID: nil)
            )
            linkedMedicalCaseID = nil
            onBatchMedicalCaseLinked?(SparkMedicalSyncAPI.RemotePrescriptionBatchComplete(
                id: updatedBatch.id,
                member: updatedBatch.member,
                medicalCase: updatedBatch.medicalCase,
                prescriberName: updatedBatch.prescriberName,
                institutionName: updatedBatch.institutionName,
                prescribedAt: updatedBatch.prescribedAt,
                diagnosis: updatedBatch.diagnosis,
                batchNo: updatedBatch.batchNo,
                status: updatedBatch.status,
                auditorName: updatedBatch.auditorName,
                auditedAt: updatedBatch.auditedAt,
                extra: updatedBatch.extra,
                createdAt: nil,
                updatedAt: updatedBatch.updatedAt,
                medications: [item],
                attachments: nil
            ))
        } catch {
            notificationClient.error(error.localizedDescription, title: L10n.text("medical.case_link.unlink.failed", fallback: "取消关联失败"), source: "medical.case.link")
        }
    }

    // MARK: - Reminder

    private var reminderSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(L10n.text("home.medical.list.medications.reminder"))
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Toggle("", isOn: .constant(item.reminderEnabled))
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: Color(uiColor: .systemGreen)))
                    .disabled(true)
            }

            if item.reminderEnabled, item.reminderTimes.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("home.medical.list.medications.reminder_times"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(item.reminderTimes, id: \.self) { time in
                            Text(time)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color(uiColor: .systemBlue))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Color(uiColor: .systemBlue).opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
