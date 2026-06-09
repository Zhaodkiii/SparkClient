import Combine
import SwiftUI
import UIKit

enum NutritionRecognitionFlowPhase: Equatable {
    case camera
    case analyzing
    case summary(NutritionRecognitionResult)
    case failure(NutritionRecognitionError)
}

@MainActor
final class NutritionRecognitionFlowViewModel: ObservableObject {
    @Published private(set) var phase: NutritionRecognitionFlowPhase = .camera
    @Published private(set) var capturedImage: UIImage?
    @Published var showPhotoPicker = false
    @Published var showCameraPicker = false

    private let dependencies: NutritionFeatureDependencies
    private let memberID: Int
    private let mealType: NutritionMealType
    private var cancellationToken = AIRuntimeCancellationToken()

    init(dependencies: NutritionFeatureDependencies, memberID: Int, mealType: NutritionMealType) {
        self.dependencies = dependencies
        self.memberID = memberID
        self.mealType = mealType
    }

    func handlePickedImage(_ image: UIImage) {
        capturedImage = image
        phase = .analyzing
        Task { await recognize(image: image) }
    }

    func retryRecognition() {
        guard let image = capturedImage else {
            phase = .camera
            return
        }
        phase = .analyzing
        Task { await recognize(image: image) }
    }

    func cancelRecognition() {
        cancellationToken.cancel()
        cancellationToken = AIRuntimeCancellationToken()
    }

    func updateSummary(_ result: NutritionRecognitionResult) {
        phase = .summary(result)
    }

    private func recognize(image: UIImage) async {
        cancellationToken = AIRuntimeCancellationToken()
        guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
            phase = .failure(.emptyInput)
            return
        }

        do {
            let result = try await dependencies.recognitionPipeline.recognizeFromPhoto(
                input: NutritionPhotoRecognitionInput(
                    memberID: memberID,
                    mealType: mealType,
                    imageJPEGData: jpegData,
                    imageFileIDs: []
                ),
                cancellationToken: cancellationToken
            )
            phase = .summary(result)
        } catch is CancellationError {
            phase = .camera
        } catch let error as NutritionRecognitionError {
            phase = .failure(error)
        } catch {
            phase = .failure(.aiServiceFailed(messageKey: NutritionErrorMapper.messageKey(for: error)))
        }
    }
}

struct NutritionRecognitionFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NutritionRecognitionFlowViewModel

    let dependencies: NutritionFeatureDependencies
    let memberID: Int
    let date: Date
    let mealType: NutritionMealType

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int,
        date: Date,
        mealType: NutritionMealType
    ) {
        self.dependencies = dependencies
        self.memberID = memberID
        self.date = date
        self.mealType = mealType
        _viewModel = StateObject(
            wrappedValue: NutritionRecognitionFlowViewModel(
                dependencies: dependencies,
                memberID: memberID,
                mealType: mealType
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .camera:
                NutritionCameraCaptureView(
                    onCancel: { dismiss() },
                    onPickPhoto: { viewModel.showPhotoPicker = true },
                    onTakePhoto: { viewModel.showCameraPicker = true }
                )
            case .analyzing:
                NutritionRecognitionAnalyzingView(
                    image: viewModel.capturedImage,
                    onCancel: {
                        viewModel.cancelRecognition()
                        dismiss()
                    }
                )
            case .summary(let result):
                NutritionRecognitionSummaryView(
                    dependencies: dependencies,
                    memberID: memberID,
                    date: date,
                    mealType: mealType,
                    image: viewModel.capturedImage,
                    recognition: result,
                    onUpdated: { viewModel.updateSummary($0) },
                    onSaveSuccess: { dismiss() }
                )
            case .failure(let error):
                NutritionRecognitionFailureView(
                    image: viewModel.capturedImage,
                    error: error,
                    onRetry: { viewModel.retryRecognition() },
                    onCancel: { dismiss() }
                )
            }
        }
        .sheet(isPresented: $viewModel.showPhotoPicker) {
            NutritionImagePicker(source: .photoLibrary) {
                viewModel.showPhotoPicker = false
            } onImagePicked: { image in
                viewModel.showPhotoPicker = false
                viewModel.handlePickedImage(image)
            }
        }
        .fullScreenCover(isPresented: $viewModel.showCameraPicker) {
            NutritionImagePicker(source: .camera) {
                viewModel.showCameraPicker = false
            } onImagePicked: { image in
                viewModel.showCameraPicker = false
                viewModel.handlePickedImage(image)
            }
        }
    }
}

struct NutritionCameraCaptureView: View {
    let onCancel: () -> Void
    let onPickPhoto: () -> Void
    let onTakePhoto: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(L10n.text("nutrition.recognition.camera.title"))
                    .font(.headline)
                Spacer()
                Color.clear.frame(width: 24, height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(L10n.text("nutrition.recognition.camera.hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.horizontal, 24)

            Spacer()

            HStack(spacing: 48) {
                Button(L10n.text("nutrition.recognition.camera.photo_library"), action: onPickPhoto)
                    .font(.subheadline)
                Button {
                    onTakePhoto()
                } label: {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: 4)
                        .frame(width: 68, height: 68)
                        .overlay(Circle().fill(Color.primary).frame(width: 56, height: 56))
                }
                Color.clear.frame(width: 60)
            }
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

struct NutritionRecognitionAnalyzingView: View {
    let image: UIImage?
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(L10n.text("nutrition.recognition.analyzing.title"))
                    .font(.headline)
                Spacer()
                ProgressView()
            }
            .padding(.horizontal, 16)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 4).fill(Color(uiColor: .systemGray5)).frame(height: 18)
                RoundedRectangle(cornerRadius: 4).fill(Color(uiColor: .systemGray5)).frame(height: 14).frame(maxWidth: 220)
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(uiColor: .systemGray5))
                            .frame(height: 64)
                    }
                }
            }
            .padding(.horizontal, 24)
            .redacted(reason: .placeholder)

            Spacer()
        }
        .padding(.top, 8)
    }
}

struct NutritionRecognitionFailureView: View {
    let image: UIImage?
    let error: NutritionRecognitionError
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(L10n.text("nutrition.recognition.analyzing.title"))
                    .font(.headline)
                Spacer()
                Color.clear.frame(width: 24)
            }
            .padding(.horizontal, 16)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 8) {
                Text(L10n.text("nutrition.recognition.failure.title"))
                    .font(.headline)
                Text(L10n.text(error.localizationKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(L10n.text("nutrition.recognition.failure.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Button(L10n.text("nutrition.common.retry"), action: onRetry)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)

            Spacer()
        }
        .padding(.top, 8)
    }
}

struct NutritionImagePicker: UIViewControllerRepresentable {
    enum Source {
        case camera
        case photoLibrary
    }

    let source: Source
    let onCancel: () -> Void
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = source == .camera ? .camera : .photoLibrary
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: NutritionImagePicker

        init(parent: NutritionImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            } else {
                parent.onCancel()
            }
        }
    }
}
