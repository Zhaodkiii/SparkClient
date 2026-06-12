import SwiftUI

/// 药箱页面底部「拍照添加药品」固定按钮
struct MedicineBoxBottomCameraButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L10n.text("home.medical.medicine_box.camera_add"), systemImage: "camera.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color(uiColor: .systemPurple), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
