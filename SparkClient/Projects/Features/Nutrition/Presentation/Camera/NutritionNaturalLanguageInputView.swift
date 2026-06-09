import SwiftUI

struct NutritionNaturalLanguageInputView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var userText = ""
    @State private var isAnalyzing = false
    @State private var errorMessageKey: String?
    @State private var recognitionResult: NutritionRecognitionResult?

    let dependencies: NutritionFeatureDependencies
    let memberID: Int
    let date: Date
    let mealType: NutritionMealType

    var body: some View {
        NavigationView {
            Group {
                if let recognitionResult {
                    NutritionRecognitionSummaryView(
                        dependencies: dependencies,
                        memberID: memberID,
                        date: date,
                        mealType: mealType,
                        image: nil,
                        recognition: recognitionResult,
                        onUpdated: { self.recognitionResult = $0 },
                        onSaveSuccess: { dismiss() }
                    )
                } else if isAnalyzing {
                    NutritionRecognitionAnalyzingView(image: nil) {
                        dismiss()
                    }
                } else {
                    inputContent
                }
            }
            .navigationBarHidden(recognitionResult != nil)
        }
        .navigationViewStyle(.stack)
        .alert(
            L10n.text("nutrition.confirm.save_failed.title"),
            isPresented: errorAlertBinding
        ) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            if let key = errorMessageKey {
                Text(L10n.text(key))
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessageKey != nil },
            set: { if $0 == false { errorMessageKey = nil } }
        )
    }

    private var inputContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(L10n.text("common.cancel")) { dismiss() }
                Spacer()
                Text(L10n.text("nutrition.recognition.input.title"))
                    .font(.headline)
                Spacer()
                Button(L10n.text("nutrition.recognition.input.analyze")) {
                    Task { await analyze() }
                }
                .disabled(userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Text(L10n.text("nutrition.recognition.input.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            TextEditor(text: $userText)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .padding(.horizontal, 16)

            Spacer()
        }
    }

    private func analyze() async {
        isAnalyzing = true
        errorMessageKey = nil
        defer { isAnalyzing = false }

        do {
            recognitionResult = try await dependencies.recognitionPipeline.recognizeFromText(
                input: NutritionTextRecognitionInput(
                    memberID: memberID,
                    mealType: mealType,
                    userText: userText
                ),
                cancellationToken: nil
            )
        } catch let error as NutritionRecognitionError {
            errorMessageKey = error.localizationKey
        } catch {
            errorMessageKey = NutritionErrorMapper.messageKey(for: error)
        }
    }
}

struct NutritionRecognitionEditDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var editedText: String
    @State private var isAnalyzing = false
    @State private var errorMessageKey: String?

    let dependencies: NutritionFeatureDependencies
    let memberID: Int
    let mealType: NutritionMealType
    let onUpdated: (NutritionRecognitionResult) -> Void

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int,
        mealType: NutritionMealType,
        initialText: String,
        onUpdated: @escaping (NutritionRecognitionResult) -> Void
    ) {
        self.dependencies = dependencies
        self.memberID = memberID
        self.mealType = mealType
        self.onUpdated = onUpdated
        _editedText = State(initialValue: initialText)
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("nutrition.recognition.edit.title"))
                    .font(.title3.weight(.semibold))
                Text(L10n.text("nutrition.recognition.edit.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $editedText)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .frame(minHeight: 180)

                Button {
                    Task { await reextract() }
                } label: {
                    Group {
                        if isAnalyzing {
                            ProgressView().tint(.white)
                        } else {
                            Text(L10n.text("nutrition.recognition.edit.reanalyze"))
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.black))
                }
                .disabled(isAnalyzing || editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding(16)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("common.cancel")) { dismiss() }
                }
            }
        }
        .alert(
            L10n.text("nutrition.confirm.save_failed.title"),
            isPresented: errorAlertBinding
        ) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            if let key = errorMessageKey {
                Text(L10n.text(key))
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessageKey != nil },
            set: { if $0 == false { errorMessageKey = nil } }
        )
    }

    private func reextract() async {
        isAnalyzing = true
        errorMessageKey = nil
        defer { isAnalyzing = false }

        do {
            let updated = try await dependencies.recognitionPipeline.recognizeFromText(
                input: NutritionTextRecognitionInput(
                    memberID: memberID,
                    mealType: mealType,
                    userText: editedText
                ),
                cancellationToken: nil
            )
            onUpdated(updated)
            dismiss()
        } catch let error as NutritionRecognitionError {
            errorMessageKey = error.localizationKey
        } catch {
            errorMessageKey = NutritionErrorMapper.messageKey(for: error)
        }
    }
}
