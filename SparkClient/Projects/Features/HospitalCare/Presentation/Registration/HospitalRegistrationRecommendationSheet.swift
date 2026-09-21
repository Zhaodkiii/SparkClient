import SwiftUI

struct HospitalRegistrationRecommendationSheet: View {
    let payload: ChatRegistrationRecommendationCardPayload
    let dependencies: HospitalCareFeatureDependencies
    @ObservedObject var memberContextStore: MemberContextStore
    let sessionStore: AppSessionStore
    let onFinish: () -> Void
    @StateObject private var viewModel: HospitalRegistrationDemoViewModel

    init(
        payload: ChatRegistrationRecommendationCardPayload,
        dependencies: HospitalCareFeatureDependencies,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore,
        onFinish: @escaping () -> Void
    ) {
        self.payload = payload
        self.dependencies = dependencies
        self.memberContextStore = memberContextStore
        self.sessionStore = sessionStore
        self.onFinish = onFinish
        _viewModel = StateObject(wrappedValue: HospitalRegistrationDemoViewModel(
            dependencies: dependencies,
            memberContextStore: memberContextStore,
            sessionStore: sessionStore
        ))
    }

    var body: some View {
        Group {
            if viewModel.isLoadingEntry {
                ProgressView("正在校验挂号目录…")
            } else if let error = viewModel.entryError {
                ContentUnavailableView("挂号推荐已失效", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if viewModel.hospital?.id != payload.hospitalID {
                ContentUnavailableView(
                    "医院已切换",
                    systemImage: "building.2",
                    description: Text("请回到当前对话，为当前医院重新获取推荐。")
                )
            } else if let department = viewModel.departments.first(where: { $0.id == payload.departmentID }) {
                NavigationStack {
                    if payload.isDoctorSpecific,
                       let doctor = viewModel.doctors.first(where: { $0.id == payload.agentID }) {
                        HospitalRegistrationScheduleView(
                            selection: RegistrationSelection(department: department, type: .expert, doctor: doctor),
                            viewModel: viewModel,
                            onFinish: onFinish
                        )
                    } else if payload.isDoctorSpecific {
                        ContentUnavailableView("医生信息已更新", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("请重新获取推荐。"))
                    } else {
                        HospitalRegistrationServiceView(
                            department: department,
                            viewModel: viewModel,
                            onFinish: onFinish
                        )
                    }
                }
            } else {
                ContentUnavailableView("科室信息已更新", systemImage: "cross.case", description: Text("请重新获取推荐。"))
            }
        }
        .task {
            await viewModel.loadEntry()
            if let department = viewModel.departments.first(where: { $0.id == payload.departmentID }), payload.isDoctorSpecific {
                await viewModel.loadDoctors(for: department)
            }
        }
    }
}
