import AppKit
import Foundation

public struct ReportExporter: Sendable {
    public init() {}

    public func markdownData(for report: Report) -> Data {
        Data(ReportGenerator().markdown(for: report).utf8)
    }

    public func csvData(for report: Report) -> Data {
        Data(ReportGenerator().csv(for: report).utf8)
    }

    public func pdfData(for report: Report) -> Data {
        let markdown = ReportGenerator().markdown(for: report)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()

        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return Data()
        }

        context.beginPDFPage([kCGPDFContextMediaBox: pageRect] as CFDictionary)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        let attributed = NSAttributedString(
            string: markdown,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        )
        attributed.draw(in: CGRect(x: 42, y: 42, width: pageRect.width - 84, height: pageRect.height - 84))

        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    public func write(_ report: Report, format: ReportExportFormat, to url: URL) throws {
        let data: Data
        switch format {
        case .markdown:
            data = markdownData(for: report)
        case .csv:
            data = csvData(for: report)
        case .pdf:
            data = pdfData(for: report)
        }
        try data.write(to: url, options: .atomic)
    }
}

public enum ReportExportFormat: String, CaseIterable, Sendable {
    case markdown
    case csv
    case pdf

    public var fileExtension: String {
        switch self {
        case .markdown:
            return "md"
        case .csv:
            return "csv"
        case .pdf:
            return "pdf"
        }
    }

    public var displayName: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .csv:
            return "CSV"
        case .pdf:
            return "PDF"
        }
    }
}
