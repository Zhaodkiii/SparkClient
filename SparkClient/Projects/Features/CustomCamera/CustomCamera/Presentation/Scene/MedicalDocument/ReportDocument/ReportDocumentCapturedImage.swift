import Foundation
import UIKit

/// 报告类医疗文档连续拍摄的单张已确认图片（按拍摄顺序编号）。
struct ReportDocumentCapturedImage: Identifiable, Equatable {
    let id: UUID
    /// 从 1 开始的展示序号，删除中间项后会重新编号。
    let index: Int
    let image: UIImage

    init(id: UUID = UUID(), index: Int, image: UIImage) {
        self.id = id
        self.index = index
        self.image = image
    }

    static func == (lhs: ReportDocumentCapturedImage, rhs: ReportDocumentCapturedImage) -> Bool {
        lhs.id == rhs.id && lhs.index == rhs.index
    }
}
