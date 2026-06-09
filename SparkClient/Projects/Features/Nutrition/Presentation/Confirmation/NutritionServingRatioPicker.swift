import SwiftUI

struct NutritionServingRatioPicker: View {
    @Binding var selection: NutritionServingRatio

    var body: some View {
        Picker(L10n.text("nutrition.confirm.serving_ratio"), selection: $selection) {
            ForEach(NutritionServingRatio.allCases, id: \.self) { ratio in
                Text(L10n.text(ratio.localizationKey)).tag(ratio)
            }
        }
        .pickerStyle(.segmented)
    }
}
