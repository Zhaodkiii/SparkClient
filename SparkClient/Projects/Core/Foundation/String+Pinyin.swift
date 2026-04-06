import Foundation

extension String {
    /// 将文本转为无声调拉丁拼音（用于搜索匹配），与 Health 端 `toPinyin()` 行为一致。
    func toPinyinForSearch() -> String {
        let mutableString = NSMutableString(string: self) as CFMutableString
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        return (mutableString as String).replacingOccurrences(of: " ", with: "")
    }
}
