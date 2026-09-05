import Combine
import Foundation
import UIKit

/// 问诊病历资料草稿：公共选择器产出本地文件后立刻上传，提交时只携带 ready 的 file_id。
struct ConsultAttachmentDraft: Identifiable, Equatable {
    enum Status: Equatable, Sendable {
        case uploading(Double)
        case ready(fileID: Int)
        case failed(String)
    }

    let file: MedicalUploadLocalFile
    var status: Status

    var id: UUID { file.id }
}

@MainActor
final class ConsultFormViewModel: ObservableObject {
    static let maxAttachments = 5
    static let orderItemOptions = ["复诊开药", "开具检查", "住院评估"]
    /// 问诊附件在文件中心登记的业务类型：与服务端 `hospital_conversation` + thread_id 对齐，
    /// 医生端附件列表按该关系读取；本人上传即可被问诊提交接口引用。
    static let attachmentBusinessType = "hospital_conversation"

    @Published var chiefComplaint = ""
    @Published var orderItems: [String] = []
    @Published var pastHistory = ""
    @Published var familyHistory = ""
    @Published var allergyHistory = ""
    @Published private(set) var drafts: [ConsultAttachmentDraft] = []
    @Published private(set) var isSubmitting = false
    @Published var actionError: String?

    /// 客户端幂等键：同一表单实例的重复提交复用，服务端返回原问诊单。
    private let draftThreadID = UUID()
    private let dependencies: HospitalCareFeatureDependencies
    private let agent: HospitalAgentCard
    private let memberContextStore: MemberContextStore
    private let sessionStore: AppSessionStore

    init(
        dependencies: HospitalCareFeatureDependencies,
        agent: HospitalAgentCard,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore
    ) {
        self.dependencies = dependencies
        self.agent = agent
        self.memberContextStore = memberContextStore
        self.sessionStore = sessionStore
    }

    var validationHint: String? {
        if chiefComplaint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先描述病情"
        }
        if drafts.contains(where: { $0.status.isReady }) == false {
            return drafts.isEmpty ? "请上传病历资料" : "病历资料尚未上传完成"
        }
        return nil
    }

    var canSubmit: Bool {
        validationHint == nil && drafts.contains(where: { $0.status.isUploading }) == false && isSubmitting == false
    }

    var previewFiles: [MedicalUploadLocalFile] {
        drafts.map(\.file)
    }

    var remainingAttachmentSlots: Int {
        max(0, Self.maxAttachments - drafts.count)
    }

    // MARK: - 附件选择与上传

    /// 公共 `MedicalDocumentFilePickerMenu` 回传本地文件后立刻 STS 上传。
    func addFiles(_ files: [MedicalUploadLocalFile]) async {
        for file in files {
            guard drafts.count < Self.maxAttachments else { return }
            let draft = ConsultAttachmentDraft(file: file, status: .uploading(0))
            drafts.append(draft)
            await upload(draftID: draft.id)
        }
    }

    func retry(draftID: UUID) async {
        await upload(draftID: draftID)
    }

    func remove(draftID: UUID) {
        drafts.removeAll { $0.id == draftID }
    }

    private func upload(draftID: UUID) async {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        let draft = drafts[index]
        guard let payload = Self.uploadPayload(for: draft.file) else {
            updateStatus(draftID: draftID, status: .failed("上传失败"))
            return
        }
        do {
            let record = try await dependencies.fileTransferService.upload(
                ManagedFileUploadPayload(
                    data: payload.data,
                    fileName: payload.fileName,
                    businessType: Self.attachmentBusinessType,
                    businessId: draftThreadID.uuidString,
                    isPublic: false,
                    onUploadProgress: { [weak self] progress in
                        Task { @MainActor in
                            self?.updateStatus(draftID: draftID, status: .uploading(progress))
                        }
                    }
                )
            )
            updateStatus(draftID: draftID, status: .ready(fileID: record.id))
        } catch {
            updateStatus(draftID: draftID, status: .failed("上传失败"))
        }
    }

    /// 图片统一压成 JPEG，保证服务端 MIME 白名单；PDF 等文档按原文件上传。
    private static func uploadPayload(for file: MedicalUploadLocalFile) -> (data: Data, fileName: String)? {
        guard let data = try? Data(contentsOf: file.url), data.isEmpty == false else { return nil }
        if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) {
            let name = file.displayName.lowercased().hasSuffix(".jpg") || file.displayName.lowercased().hasSuffix(".jpeg")
                ? file.displayName
                : "病历图片-\(file.id.uuidString.prefix(8)).jpg"
            return (jpeg, name)
        }
        return (data, file.displayName)
    }

    private func updateStatus(draftID: UUID, status: ConsultAttachmentDraft.Status) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        drafts[index].status = status
    }

    /// 提交成功后把 STS 直传登记的附件再绑定到真实问诊会话 thread_id。
    /// 绑定失败不影响已创建的问诊单；医生端按 `hospital_conversation` 读取。
    private func bindAttachments(to consultation: HospitalConsultationDTO) async {
        let fileIDs = drafts.compactMap { $0.status.fileID }
        guard fileIDs.isEmpty == false else { return }
        let threadID = consultation.threadId.uuidString
        for fileID in fileIDs {
            _ = try? await dependencies.fileTransferService.updateBusinessBinding(
                fileID: fileID,
                businessType: Self.attachmentBusinessType,
                businessID: threadID
            )
        }
    }

    // MARK: - 提交

    func toggleOrderItem(_ option: String) {
        if let index = orderItems.firstIndex(of: option) {
            orderItems.remove(at: index)
        } else {
            orderItems.append(option)
        }
    }

    func submit() async -> HospitalConsultationDTO? {
        guard canSubmit else { return nil }
        guard case .signedIn(let session) = sessionStore.state else {
            actionError = "请先登录后再提交问诊"
            return nil
        }
        guard let memberID = memberContextStore.context.selectedMemberID else {
            actionError = "请先选择就诊人"
            return nil
        }
        isSubmitting = true
        actionError = nil
        defer { isSubmitting = false }
        do {
            let consultation = try await dependencies.submitConsultation.execute(
                accountID: session.accountID,
                input: SubmitConsultationUseCase.Input(
                    agentID: agent.id,
                    memberID: memberID,
                    hospitalID: agent.hospitalID,
                    chiefComplaint: chiefComplaint.trimmingCharacters(in: .whitespacesAndNewlines),
                    attachmentFileIDs: drafts.compactMap { $0.status.fileID },
                    orderItems: orderItems,
                    pastHistory: pastHistory.trimmingCharacters(in: .whitespacesAndNewlines),
                    familyHistory: familyHistory.trimmingCharacters(in: .whitespacesAndNewlines),
                    allergyHistory: allergyHistory.trimmingCharacters(in: .whitespacesAndNewlines),
                    threadID: draftThreadID
                )
            )
            await bindAttachments(to: consultation)
            return consultation
        } catch {
            actionError = "提交失败，请稍后重试"
            return nil
        }
    }
}

private extension ConsultAttachmentDraft.Status {
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isUploading: Bool {
        if case .uploading = self { return true }
        return false
    }

    var fileID: Int? {
        if case .ready(let fileID) = self { return fileID }
        return nil
    }
}
