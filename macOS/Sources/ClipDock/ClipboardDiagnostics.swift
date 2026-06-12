import AppKit
import ClipboardPanelApp
import Foundation

enum ClipboardDiagnosticsLatestItem {
    case item(RustClipboardItemSummary)
    case unavailable(reason: String)
}

@MainActor
struct ClipboardDiagnosticsReport {
    private enum Limits {
        static let maxPasteboardTypes = 64
    }

    static func make(
        pasteboard: NSPasteboard = .general,
        payloadReader: ClipboardContentReading = ClipboardPayloadReader(),
        latestItem: ClipboardDiagnosticsLatestItem,
        appVersion: String,
        appBuild: String,
        generatedAt: Date = Date()
    ) -> String {
        var lines: [String] = []
        lines.append("ClipDock Clipboard Diagnostics")
        lines.append("generated_at=\(isoTimestamp(from: generatedAt))")
        lines.append("app_version=\(quoted(appVersion)) app_build=\(quoted(appBuild))")
        lines.append("pasteboard_name=\(quoted(pasteboard.name.rawValue)) change_count=\(pasteboard.changeCount)")

        let types = pasteboard.types ?? []
        lines.append("types_count=\(types.count)")
        lines.append("pasteboard_types:")
        if types.isEmpty {
            lines.append("- none")
        } else {
            for (index, pasteboardType) in types.prefix(Limits.maxPasteboardTypes).enumerated() {
                lines.append(typeLine(index: index, type: pasteboardType, pasteboard: pasteboard))
            }
            let omittedCount = types.count - Limits.maxPasteboardTypes
            if omittedCount > 0 {
                lines.append("- omitted_types=\(omittedCount)")
            }
        }

        lines.append("reader:")
        lines.append(readerDecisionLine(payloadReader.readContent(from: pasteboard)))
        lines.append("latest_item:")
        lines.append(latestItemLine(latestItem))
        return lines.joined(separator: "\n")
    }

    private static func typeLine(
        index: Int,
        type: NSPasteboard.PasteboardType,
        pasteboard: NSPasteboard
    ) -> String {
        let dataBytes = pasteboard.data(forType: type)?.count
        let string = pasteboard.string(forType: type)
        let normalizedString = normalizedText(string)

        var fields = [
            "- index=\(index)",
            "type=\(quoted(type.rawValue))",
            "data_bytes=\(optionalInt(dataBytes))",
            "string_chars=\(optionalInt(string?.count))",
            "normalized_chars=\(optionalInt(normalizedString?.count))"
        ]
        if let normalizedString {
            fields.append("pure_link=\(ClipboardLinkDetector().detectPureLink(in: normalizedString) != nil)")
        }
        return fields.joined(separator: " ")
    }

    private static func readerDecisionLine(_ snapshot: ClipboardPayloadSnapshot?) -> String {
        guard let snapshot else {
            return "decision=none"
        }

        switch snapshot {
        case .text(let text, let displayRichText):
            return [
                "decision=text",
                "text_chars=\(text.count)",
                "pure_link=\(ClipboardLinkDetector().detectPureLink(in: text) != nil)",
                "display_rich_text=\(displayRichText != nil)",
                "display_rich_text_rtf_bytes=\(optionalInt(displayRichText?.rtfData.count))"
            ].joined(separator: " ")

        case .richText(let richText):
            return [
                "decision=rich_text",
                "text_chars=\(richText.text.count)",
                "rtf_bytes=\(richText.rtfData.count)"
            ].joined(separator: " ")

        case .image(let image):
            return "decision=image \(imageLine(image))"

        case .files(let files):
            let extensions = Set(files.urls.map { normalizedFileExtension($0.pathExtension) }).sorted()
            return [
                "decision=files",
                "file_count=\(files.urls.count)",
                "file_extensions=\(quoted(extensions.joined(separator: ",")))"
            ].joined(separator: " ")
        }
    }

    private static func imageLine(_ image: CapturedClipboardImage) -> String {
        switch image.source {
        case .encodedData(let data, let typeIdentifier):
            return [
                "image_source=encoded_data",
                "type_identifier=\(quoted(typeIdentifier))",
                "data_bytes=\(data.count)"
            ].joined(separator: " ")

        case .cgImage(let snapshot):
            return [
                "image_source=cg_image",
                "width=\(snapshot.image.width)",
                "height=\(snapshot.image.height)"
            ].joined(separator: " ")
        }
    }

    private static func latestItemLine(_ latestItem: ClipboardDiagnosticsLatestItem) -> String {
        switch latestItem {
        case .item(let item):
            return [
                "status=available",
                "item_type=\(quoted(item.itemType))",
                "source_app_name=\(quoted(item.sourceAppName))",
                "source_app_id_present=\(item.sourceAppId != nil)",
                "summary_chars=\(item.summary.count)",
                "primary_text_chars=\(optionalInt(item.primaryText?.count))",
                "preview_asset_present=\(item.previewAssetPath != nil)",
                "payload_asset_present=\(item.payloadAssetPath != nil)",
                "preview_state=\(quoted(item.previewState))",
                "payload_state=\(quoted(item.payloadState))",
                "size_bytes=\(item.sizeBytes)",
                "file_count=\(item.fileItems.count)",
                "link_metadata_present=\(item.linkMetadata != nil)"
            ].joined(separator: " ")

        case .unavailable(let reason):
            return "status=unavailable reason=\(quoted(reason))"
        }
    }

    private static func optionalInt(_ value: Int?) -> String {
        value.map(String.init) ?? "nil"
    }

    private static func quoted(_ value: String?) -> String {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "nil" }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func normalizedText(_ text: String?) -> String? {
        let normalized = text?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedFileExtension(_ fileExtension: String) -> String {
        let normalized = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? "none" : normalized
    }

    private static func isoTimestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
