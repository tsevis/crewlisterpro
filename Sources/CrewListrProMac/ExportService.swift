import AppKit
import Foundation

/// Writes the two deliverables a port authority accepts: a machine-readable CSV
/// and a printed crew list laid out as a boxed header plus SKIPPER and
/// PASSENGERS sections.
enum ExportService {

    // MARK: - Naming

    /// Includes the yacht so two trips departing the same day cannot overwrite
    /// each other, and stays filesystem-safe on every platform.
    static func fileNameStem(boat: Boat, trip: Trip) -> String {
        let yacht = sanitised(boat.name.isEmpty ? "yacht" : boat.name)
        return "crew-list-\(yacht)-\(CrewFieldValidator.iso8601String(trip.departureDate))"
    }

    private static func sanitised(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = value.uppercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(mapped).split(separator: "-").joined(separator: "-")
    }

    // MARK: - CSV

    static func exportCSV(to url: URL, trip: Trip, boat: Boat, rows: [CrewListRow]) throws {
        var lines = ["role,full_name,document_number,nationality,birth_date,sex,expiry_date,yacht,flag,registry_port,registration_number,departure_date,return_date"]
        for row in rows {
            lines.append([
                row.role.rawValue, row.fullName, row.documentNumber, row.nationality,
                row.birthDate, row.sex, row.expiryDate,
                boat.name, boat.flag, boat.registrationPort, boat.registrationNumber,
                CrewFieldValidator.iso8601String(trip.departureDate),
                CrewFieldValidator.iso8601String(trip.returnDate),
            ].map(csv).joined(separator: ","))
        }
        // RFC 4180 line endings, and a BOM so Excel opens UTF-8 without mangling
        // non-ASCII names.
        var content = Data([0xEF, 0xBB, 0xBF])
        content.append(Data(lines.joined(separator: "\r\n").utf8))
        try content.write(to: url, options: .atomic)
    }

    /// Quotes every value, doubles embedded quotes, and prefixes a leading
    /// formula character so a name read off a scanned document cannot execute
    /// when the crew list is opened in a spreadsheet.
    private static func csv(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if let first = escaped.first, "=+-@\t\r".contains(first) { escaped = "'" + escaped }
        return "\"\(escaped)\""
    }

    // MARK: - PDF

    private static let pageSize = CGSize(width: 595, height: 842)   // A4 portrait
    private static let margin: CGFloat = 28
    private static let rowHeight: CGFloat = 20
    private static let headerBoxHeight: CGFloat = 30

    private struct Column {
        let title: String
        let width: CGFloat
        let key: (CrewListRow) -> String
    }

    private static func columns(totalWidth: CGFloat) -> [Column] {
        let name: CGFloat = 168, number: CGFloat = 96, nationality: CGFloat = 92, birthday: CGFloat = 78
        return [
            Column(title: "FULL NAME", width: name) { $0.fullName },
            Column(title: "PASSPORT NO", width: number) { $0.documentNumber },
            Column(title: "NATIONALITY", width: nationality) { $0.nationality },
            Column(title: "BIRTHDAY", width: birthday) { $0.birthDate },
            Column(title: "SEX", width: totalWidth - name - number - nationality - birthday) { $0.sex },
        ]
    }

    static func exportPDF(to url: URL, trip: Trip, boat: Boat, rows: [CrewListRow]) throws {
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }

        let skippers = rows.filter { $0.role == .skipper }
        let passengers = rows.filter { $0.role == .passenger }

        var page = Page(context: context, trip: trip, boat: boat)
        page.begin(pageNumber: 1, pageCount: nil)
        page.drawSection(title: "SKIPPER", rows: skippers.isEmpty ? [CrewListRow.blank] : skippers)
        page.drawSection(title: "PASSENGERS", rows: passengers)
        page.finish()

        context.closePDF()
    }

    /// Owns the drawing cursor for one PDF, breaking to a new page when a
    /// section runs past the bottom margin. The old exporter drew every row at a
    /// fixed 22pt step and silently lost anyone past the 32nd.
    private struct Page {
        let context: CGContext
        let trip: Trip
        let boat: Boat
        private var y: CGFloat = 0
        private var pageNumber = 0

        init(context: CGContext, trip: Trip, boat: Boat) {
            self.context = context
            self.trip = trip
            self.boat = boat
        }

        var contentWidth: CGFloat { pageSize.width - margin * 2 }

        mutating func begin(pageNumber number: Int, pageCount: Int?) {
            pageNumber = number
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            y = pageSize.height - margin
            drawTitle()
            drawHeaderBoxes()
        }

        mutating func finish() {
            drawFooter()
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }

        private mutating func breakPage() {
            finish()
            begin(pageNumber: pageNumber + 1, pageCount: nil)
        }

        private mutating func drawTitle() {
            y -= 22
            draw("CREW LIST", at: CGPoint(x: margin, y: y), size: 17, bold: true)
            let dates = "\(CrewFieldValidator.iso8601String(trip.departureDate))  –  \(CrewFieldValidator.iso8601String(trip.returnDate))"
            draw(dates, at: CGPoint(x: margin + 130, y: y + 3), size: 10)
            y -= 14
        }

        private mutating func drawHeaderBoxes() {
            let entries = [
                ("YACHT", boat.name), ("FLAG", boat.flag),
                ("PORT OF REGISTRY", boat.registrationPort), ("REG NO", boat.registrationNumber),
            ]
            let width = contentWidth / CGFloat(entries.count)
            y -= headerBoxHeight
            for (index, entry) in entries.enumerated() {
                let rect = CGRect(x: margin + CGFloat(index) * width, y: y, width: width, height: headerBoxHeight)
                context.setStrokeColor(NSColor.black.cgColor)
                context.setLineWidth(0.7)
                context.stroke(rect)
                draw(entry.0, at: CGPoint(x: rect.minX + 4, y: rect.maxY - 11), size: 6.5, bold: true)
                draw(fitted(entry.1, width: width - 8, size: 10), at: CGPoint(x: rect.minX + 4, y: rect.minY + 6), size: 10)
            }
            y -= 18
        }

        mutating func drawSection(title: String, rows: [CrewListRow]) {
            guard !rows.isEmpty else { return }
            if y < margin + rowHeight * 3 { breakPage() }
            draw(title, at: CGPoint(x: margin, y: y), size: 9, bold: true)
            y -= 6
            drawRowLine(cells: ExportService.columns(totalWidth: contentWidth).map(\.title), bold: true)
            for row in rows {
                if y < margin + rowHeight * 2 {
                    breakPage()
                    draw("\(title) (continued)", at: CGPoint(x: margin, y: y), size: 9, bold: true)
                    y -= 6
                    drawRowLine(cells: ExportService.columns(totalWidth: contentWidth).map(\.title), bold: true)
                }
                drawRowLine(cells: ExportService.columns(totalWidth: contentWidth).map { $0.key(row) }, bold: false)
            }
            y -= 12
        }

        private mutating func drawRowLine(cells: [String], bold: Bool) {
            y -= rowHeight
            var x = margin
            for (column, value) in zip(ExportService.columns(totalWidth: contentWidth), cells) {
                let rect = CGRect(x: x, y: y, width: column.width, height: rowHeight)
                context.setStrokeColor(NSColor.black.cgColor)
                context.setLineWidth(0.5)
                context.stroke(rect)
                draw(fitted(value, width: column.width - 8, size: bold ? 7 : 9),
                     at: CGPoint(x: x + 4, y: y + 6), size: bold ? 7 : 9, bold: bold)
                x += column.width
            }
        }

        private func drawFooter() {
            let stamp = "\(AppVersion.name) \(AppVersion.short)  ·  page \(pageNumber)"
            draw(stamp, at: CGPoint(x: margin, y: margin - 12), size: 7, bold: false, gray: 0.45)
        }

        // MARK: - Text

        private func attributes(size: CGFloat, bold: Bool, gray: CGFloat) -> [NSAttributedString.Key: Any] {
            [.font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
             .foregroundColor: NSColor(white: gray, alpha: 1)]
        }

        private func draw(_ text: String, at point: CGPoint, size: CGFloat, bold: Bool = false, gray: CGFloat = 0) {
            text.draw(at: point, withAttributes: attributes(size: size, bold: bold, gray: gray))
        }

        /// Truncates with an ellipsis rather than letting a long name overrun
        /// into the next column.
        private func fitted(_ text: String, width: CGFloat, size: CGFloat) -> String {
            let attributes = attributes(size: size, bold: false, gray: 0)
            guard (text as NSString).size(withAttributes: attributes).width > width else { return text }
            var truncated = text
            while !truncated.isEmpty, ((truncated + "…") as NSString).size(withAttributes: attributes).width > width {
                truncated.removeLast()
            }
            return truncated + "…"
        }
    }
}

private extension CrewListRow {
    /// An empty skipper line, so the printed form always shows the section a
    /// port official expects to find.
    static var blank: CrewListRow {
        CrewListRow(document: CrewDocument(tripID: UUID(), personID: UUID(), originalName: "", encryptedFileName: ""), role: .skipper)
    }
}
