import Foundation

enum OCRFusionSelector {
    static func selectBest(outputs: [OCRTextOutput], corrector: SparkMedicalTermsCorrector?, applyCorrection: Bool) -> OCRRecognition {
        let normalizedOutputs = outputs.map { output in
            let text: String
            if applyCorrection, let corrector {
                text = corrector.correct(output.text)
            } else {
                text = output.text
            }
            return OCRTextOutput(engine: output.engine, text: text, confidence: output.confidence, elapsedMs: output.elapsedMs)
        }

        let best = normalizedOutputs.max { lhs, rhs in
            score(for: lhs) < score(for: rhs)
        } ?? OCRTextOutput(engine: "none", text: "", confidence: nil, elapsedMs: nil)

        return OCRRecognition(text: best.text, selectedEngine: best.engine, outputs: normalizedOutputs)
    }

    private static func score(for output: OCRTextOutput) -> Double {
        let text = output.text
        guard !text.isEmpty else { return 0 }

        let nonWhitespaceCount = text.replacingOccurrences(of: "\\s", with: "", options: .regularExpression).count
        let numberCount = text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let medicalTermHits = ["MRI", "CT", "血常规", "mmol/L", "T1WI", "T2WI", "DWI", "AFP", "CEA"].reduce(0) { acc, term in
            acc + (text.localizedCaseInsensitiveContains(term) ? 1 : 0)
        }

        let confidencePart = (output.confidence ?? 0.6) * 40
        let textLengthPart = min(Double(nonWhitespaceCount), 1200) / 1200 * 30
        let numberDensityPart = min(Double(numberCount), 80) / 80 * 10
        let medicalPart = min(Double(medicalTermHits), 10) / 10 * 20

        return confidencePart + textLengthPart + numberDensityPart + medicalPart
    }
}
