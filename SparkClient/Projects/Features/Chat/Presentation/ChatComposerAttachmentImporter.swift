import Foundation
import UniformTypeIdentifiers

enum ChatComposerAttachmentImporter {
    static func importFiles(urls: [URL]) async -> [ChatComposerAttachmentPreview] {
        var previews: [ChatComposerAttachmentPreview] = []
        for url in urls {
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gotAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let data = try? Data(contentsOf: url), data.isEmpty == false else { continue }
            let inferredType = UTType(filenameExtension: url.pathExtension)
            let kind: ChatComposerAttachmentKind
            if inferredType?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
                kind = .pdf
            } else if inferredType?.conforms(to: .image) == true {
                kind = .image
            } else {
                kind = .file
            }
            previews.append(
                ChatComposerAttachmentPreview(
                    source: .document,
                    kind: kind,
                    data: data,
                    displayName: url.lastPathComponent,
                    mimeType: inferredType?.preferredMIMEType,
                    utTypeIdentifier: inferredType?.identifier
                )
            )
        }
        return previews
    }
}
