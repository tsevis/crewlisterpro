import Foundation

/// A one-sheet `.xlsx` of text cells, written without a spreadsheet library.
///
/// Every cell is an inline string, and every column carries the Text number
/// format (`@`), so a row the operator adds in Excel afterwards stays text as
/// well — not only the rows written here.
enum XLSXWriter {
    static func workbook(sheetName: String, rows: [[String]], columnWidths: [Double] = []) -> Data {
        ZipArchive.stored([
            ("[Content_Types].xml", contentTypes),
            ("_rels/.rels", rootRelationships),
            ("xl/workbook.xml", workbookXML(sheetName: sheetName)),
            ("xl/_rels/workbook.xml.rels", workbookRelationships),
            ("xl/styles.xml", styles),
            ("xl/worksheets/sheet1.xml", sheetXML(rows: rows, columnWidths: columnWidths)),
        ].map { ($0.0, Data($0.1.utf8)) })
    }

    // MARK: - Sheet

    /// Style 1 is text; style 2 is text in bold, for the header row.
    private static func sheetXML(rows: [[String]], columnWidths: [Double]) -> String {
        let columns = columnWidths.enumerated().map { index, width in
            "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(width)\" style=\"1\" customWidth=\"1\"/>"
        }.joined()
        let body = rows.enumerated().map { index, cells in
            let style = index == 0 ? 2 : 1
            let row = index + 1
            let values = cells.enumerated().map { column, value in
                "<c r=\"\(columnName(column))\(row)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escaped(value))</t></is></c>"
            }.joined()
            return "<row r=\"\(row)\">\(values)</row>"
        }.joined()
        return header + """
        <worksheet xmlns="\(mainNamespace)">\
        <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>\
        \(columns.isEmpty ? "" : "<cols>\(columns)</cols>")\
        <sheetData>\(body)</sheetData></worksheet>
        """
    }

    /// A, B, … Z, AA — the column letters a cell reference is written in.
    static func columnName(_ index: Int) -> String {
        var name = ""
        var remaining = index + 1
        while remaining > 0 {
            let digit = (remaining - 1) % 26
            name = String(UnicodeScalar(UInt8(65 + digit))) + name
            remaining = (remaining - 1) / 26
        }
        return name
    }

    /// XML-escaped, with the control characters XML 1.0 forbids dropped: one
    /// stray byte from an OCR'd field would otherwise make Excel refuse the
    /// whole file.
    private static func escaped(_ value: String) -> String {
        let allowed = value.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        return String(String.UnicodeScalarView(allowed))
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - Package parts

    private static let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    private static let mainNamespace = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    private static let relationshipNamespace = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let packageRelationships = "http://schemas.openxmlformats.org/package/2006/relationships"

    private static func workbookXML(sheetName: String) -> String {
        header + """
        <workbook xmlns="\(mainNamespace)" xmlns:r="\(relationshipNamespace)">\
        <sheets><sheet name="\(escaped(sheetName))" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
    }

    private static let contentTypes = header + """
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
    </Types>
    """

    private static let rootRelationships = header + """
    <Relationships xmlns="\(packageRelationships)">\
    <Relationship Id="rId1" Type="\(relationshipNamespace)/officeDocument" Target="xl/workbook.xml"/>\
    </Relationships>
    """

    private static let workbookRelationships = header + """
    <Relationships xmlns="\(packageRelationships)">\
    <Relationship Id="rId1" Type="\(relationshipNamespace)/worksheet" Target="worksheets/sheet1.xml"/>\
    <Relationship Id="rId2" Type="\(relationshipNamespace)/styles" Target="styles.xml"/>\
    </Relationships>
    """

    /// numFmtId 49 is Excel's built-in Text format, `@`.
    private static let styles = header + """
    <styleSheet xmlns="\(mainNamespace)">\
    <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>\
    <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
    <cellXfs count="3">\
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
    <xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="49" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>\
    </cellXfs>\
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
    </styleSheet>
    """
}
