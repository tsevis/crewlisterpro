import CoreGraphics
import CoreText
import Foundation

/// Writes the two deliverables a port authority accepts: a machine-readable CSV
/// and a printed crew list laid out as a boxed header plus SKIPPER and
/// PASSENGERS sections.
enum ExportService {

    // MARK: - Naming

    /// Includes the yacht so two trips departing the same day cannot overwrite
    /// each other, and stays filesystem-safe on every platform.
    static func fileNameStem(boat: Boat, trip: Trip, prefix: String = AppSettings.defaultFileNamePrefix) -> String {
        let yacht = sanitised(boat.name.isEmpty ? "yacht" : boat.name)
        // Already made filesystem-safe by `AppSettings.normalised()`, and
        // sanitised again here because this function is also reachable with a
        // prefix that never went through the settings.
        // Case-preserving, unlike the yacht: the shipped default is
        // "crew-list" and CREW-LIST is not the same word to anyone sorting a
        // folder of these.
        let stem = sanitised(prefix, uppercased: false)
        // ISO here and nowhere else on the printed form: a file name is sorted,
        // not read aloud, and `2026-08-29` sorts and `29 AUG 2026` does not.
        return "\(stem.isEmpty ? AppSettings.defaultFileNamePrefix : stem)-\(yacht)-\(VoyageDate.iso(trip.departureDate))"
    }

    private static func sanitised(_ value: String, uppercased: Bool = true) -> String {
        fileSafe(value, uppercased: uppercased)
    }

    /// The one rule for what may appear in a file name this app writes:
    /// letters, digits, dash and underscore, with everything else collapsed to
    /// a single dash.
    ///
    /// `AppSettings` validates the operator's file-name prefix through this
    /// rather than keeping its own copy. Two implementations of "what is safe
    /// in a file name" is two answers, and they drift.
    static func fileSafe(_ value: String, uppercased: Bool = false) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let source = uppercased ? value.uppercased() : value
        let mapped = source.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(mapped).split(separator: "-").joined(separator: "-")
    }

    // MARK: - CSV

    /// Every date here stays ISO-8601, including the voyage dates the PDF prints
    /// as `29 AUG 2026`. This file is read by software — a spreadsheet, a port
    /// authority's import — and a three-letter month is a string to it, not a
    /// date. The printed form is where a person reads them.
    ///
    /// New columns are appended, never inserted. Something out there is already
    /// reading this file by column position, and moving `full_name` from the
    /// second field to the third would silently feed it a role where it expects
    /// a name. `skipper_email` and `is_client` are therefore at the end, in the
    /// order they were added, and anything added later goes after them.
    static func exportCSV(to url: URL, trip: Trip, boat: Boat, rows: [CrewListRow], skipperEmail: String = "") throws {
        var lines = ["role,full_name,document_number,nationality,birth_date,sex,expiry_date,yacht,flag,registry_port,registration_number,departure_date,return_date,skipper_email,is_client"]
        for row in rows {
            lines.append([
                row.role.rawValue,
                row.fullName, row.documentNumber, row.nationality,
                row.birthDate, row.sex, row.expiryDate,
                boat.name, boat.flag, boat.registrationPort, boat.registrationNumber,
                VoyageDate.iso(trip.departureDate),
                VoyageDate.iso(trip.returnDate),
                skipperEmail,
                row.isClient ? "yes" : "no",
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
            // As the passport prints it. The CSV beside this file keeps the ISO
            // form, so nothing machine-readable is lost by making this legible.
            Column(title: "BIRTHDAY", width: birthday) { $0.printedBirthDate },
            Column(title: "SEX", width: totalWidth - name - number - nationality - birthday) { $0.sex },
        ]
    }

    static func exportPDF(to url: URL, trip: Trip, boat: Boat, rows: [CrewListRow], skipperEmail: String = "") throws {
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }

        let skippers = rows.filter { $0.role == .skipper }
        let passengers = rows.filter { $0.role == .passenger }

        var page = Page(context: context, trip: trip, boat: boat, skipperEmail: skipperEmail)
        page.begin(pageNumber: 1, pageCount: nil)
        page.drawSection(title: "SKIPPER", rows: skippers.isEmpty ? [CrewListRow.blank] : skippers)
        page.drawSection(title: "PASSENGERS", rows: passengers)
        page.drawClientSignature(client: rows.first(where: \.isClient))
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
        let skipperEmail: String
        private var y: CGFloat = 0
        private var pageNumber = 0

        init(context: CGContext, trip: Trip, boat: Boat, skipperEmail: String = "") {
            self.context = context
            self.trip = trip
            self.boat = boat
            self.skipperEmail = skipperEmail
        }

        var contentWidth: CGFloat { pageSize.width - margin * 2 }

        mutating func begin(pageNumber number: Int, pageCount: Int?) {
            pageNumber = number
            context.beginPDFPage(nil)
            // Core Text writes along this matrix, and a PDF context does not
            // reset it between pages.
            context.textMatrix = .identity
            y = pageSize.height - margin
            drawTitle()
            drawHeaderBoxes()
        }

        mutating func finish() {
            drawFooter()
            context.endPDFPage()
        }

        private mutating func breakPage() {
            finish()
            begin(pageNumber: pageNumber + 1, pageCount: nil)
        }

        private mutating func drawTitle() {
            y -= 22
            draw("CREW LIST", at: CGPoint(x: margin, y: y), size: 17, bold: true)
            let dates = "\(VoyageDate.printed(trip.departureDate))  –  \(VoyageDate.printed(trip.returnDate))"
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
                context.setStrokeColor(Page.rule)
                context.setLineWidth(0.7)
                context.stroke(rect)
                draw(entry.0, at: CGPoint(x: rect.minX + 4, y: rect.maxY - 11), size: 6.5, bold: true)
                draw(fitted(entry.1, width: width - 8, size: 10), at: CGPoint(x: rect.minX + 4, y: rect.minY + 6), size: 10)
            }
            // Under the boxes rather than in one: it is how to reach a person,
            // not a property of the vessel, and a port authority reads the four
            // registration facts as a set. The gap below the boxes is the same
            // either way, so a trip with no address on it is not a form with a
            // hole in it.
            guard !skipperEmail.isEmpty else { y -= 18; return }
            y -= 14
            draw("SKIPPER EMAIL  \(skipperEmail)", at: CGPoint(x: margin, y: y), size: 8, gray: 0.25)
            y -= 16
        }

        mutating func drawSection(title: String, rows: [CrewListRow]) {
            guard !rows.isEmpty else { return }
            if y < margin + rowHeight * 3 { breakPage() }
            draw(title, at: CGPoint(x: margin, y: y), size: 9, bold: true)
            y -= 6
            drawRowLine(cells: ExportService.columns(totalWidth: contentWidth).map(\.title), style: .heading)
            for row in rows {
                if y < margin + rowHeight * 2 {
                    breakPage()
                    draw("\(title) (continued)", at: CGPoint(x: margin, y: y), size: 9, bold: true)
                    y -= 6
                    drawRowLine(cells: ExportService.columns(totalWidth: contentWidth).map(\.title), style: .heading)
                }
                // The client's row is set in bold rather than tagged with a
                // word: the name column is already the one that truncates, and
                // a "(CLIENT)" suffix would be the first thing cut off a long
                // name. Who they are is spelled out under CLIENT below anyway.
                drawRowLine(cells: ExportService.columns(totalWidth: contentWidth).map { $0.key(row) },
                            style: row.isClient ? .client : .crew)
            }
            y -= 12
        }

        /// The line the client signs.
        ///
        /// Printed whether or not anyone has been named, for the same reason
        /// the SKIPPER section is: a port official expects the block to be on
        /// the form, and a form that grows a new section only sometimes is a
        /// form nobody trusts they have all of.
        mutating func drawClientSignature(client: CrewListRow?) {
            if y < margin + rowHeight * 3 { breakPage() }
            draw("CLIENT — SIGNS FOR THIS CHARTER", at: CGPoint(x: margin, y: y), size: 9, bold: true)
            y -= 22

            let nameWidth: CGFloat = 200
            draw(fitted(client?.fullName ?? "", width: nameWidth, size: 10),
                 at: CGPoint(x: margin, y: y + 4), size: 10)

            // A ruled line to sign on, not an empty box: it says where the pen
            // goes without claiming the signature is a field this app holds.
            let lineStart = margin + nameWidth + 20
            context.setStrokeColor(Page.rule)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: lineStart, y: y))
            context.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
            context.strokePath()

            draw("NAME", at: CGPoint(x: margin, y: y - 10), size: 6.5, bold: true, gray: 0.45)
            draw("SIGNATURE", at: CGPoint(x: lineStart, y: y - 10), size: 6.5, bold: true, gray: 0.45)
            y -= 22
        }

        /// How one line of the table is set. The client's row is emphasised at
        /// the body size rather than at the heading's, so bold never means two
        /// different things on the same page.
        private enum RowStyle {
            case heading, crew, client

            var size: CGFloat { self == .heading ? 7 : 9 }
            var bold: Bool { self != .crew }
        }

        private mutating func drawRowLine(cells: [String], style: RowStyle) {
            y -= rowHeight
            var x = margin
            for (column, value) in zip(ExportService.columns(totalWidth: contentWidth), cells) {
                let rect = CGRect(x: x, y: y, width: column.width, height: rowHeight)
                context.setStrokeColor(Page.rule)
                context.setLineWidth(0.5)
                context.stroke(rect)
                draw(fitted(value, width: column.width - 8, size: style.size, bold: style.bold),
                     at: CGPoint(x: x + 4, y: y + 6), size: style.size, bold: style.bold)
                x += column.width
            }
        }

        private func drawFooter() {
            let stamp = "\(AppVersion.name) \(AppVersion.short)  ·  page \(pageNumber)"
            draw(stamp, at: CGPoint(x: margin, y: margin - 12), size: 7, bold: false, gray: 0.45)
        }

        // MARK: - Text
        //
        // Core Text, not `NSString.draw(at:)`. The AppKit and UIKit text stacks
        // disagree about which way up a graphics context is — AppKit's origin
        // is the bottom-left corner and UIKit's is the top-left — so the one
        // call that drew every string on this page printed the whole crew list
        // upside down when the same code was asked to run on a phone. Core Text
        // is the layer under both of them and has no opinion about the page: it
        // draws a line at the baseline the caller sets, on either platform.

        /// Black, for the boxes and the ruled lines.
        private static let rule = CGColor(gray: 0, alpha: 1)

        /// The system face, at a weight. `NSFont` and `UIFont` are both toll-free
        /// bridged to `CTFont`, so this stays the typeface the Mac build has
        /// always printed rather than a named substitute.
        private func font(size: CGFloat, bold: Bool) -> CTFont {
            (bold ? PlatformFont.boldSystemFont(ofSize: size) : PlatformFont.systemFont(ofSize: size)) as CTFont
        }

        /// The Core Text keys deliberately, not `NSAttributedString.Key`: the
        /// AppKit and UIKit colour keys carry a platform colour object that
        /// `CTLineCreateWithAttributedString` does not read, and the text would
        /// come out black whatever `gray` said.
        private func line(_ text: String, size: CGFloat, bold: Bool, gray: CGFloat) -> CTLine {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font(size: size, bold: bold),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1),
            ]
            return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        }

        /// `point` is the bottom-left of the line's own box, which is where
        /// every measurement on this page was written against — so the baseline
        /// sits one descent above it.
        private func draw(_ text: String, at point: CGPoint, size: CGFloat, bold: Bool = false, gray: CGFloat = 0) {
            guard !text.isEmpty else { return }
            let drawn = line(text, size: size, bold: bold, gray: gray)
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(drawn, nil, &descent, nil)
            context.textPosition = CGPoint(x: point.x, y: point.y + descent)
            CTLineDraw(drawn, context)
        }

        private func width(of text: String, size: CGFloat, bold: Bool) -> CGFloat {
            CTLineGetTypographicBounds(line(text, size: size, bold: bold, gray: 0), nil, nil, nil)
        }

        /// Truncates with an ellipsis rather than letting a long name overrun
        /// into the next column.
        ///
        /// Measured at the weight it will be *set* in. Measuring the bold client
        /// row against the regular face let it overrun the column it was fitted
        /// to, which is the one row on the page a reader is meant to find.
        private func fitted(_ text: String, width columnWidth: CGFloat, size: CGFloat, bold: Bool = false) -> String {
            guard width(of: text, size: size, bold: bold) > columnWidth else { return text }
            var truncated = text
            while !truncated.isEmpty, width(of: truncated + "…", size: size, bold: bold) > columnWidth {
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
