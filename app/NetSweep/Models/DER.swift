import Foundation

// MARK: - Minimal DER / ASN.1 reader
// Just enough to pull the Validity (notBefore / notAfter) out of an X.509 cert
// on iOS, where the macOS-only SecCertificateCopyValues API is unavailable.

enum DER {

    private struct TLV {
        let tag: UInt8
        let valueStart: Int
        let valueLength: Int
        var valueEnd: Int { valueStart + valueLength }
        var contentEnd: Int { valueEnd }
    }

    /// Parse one TLV at `idx`. Returns the element and the index just past it.
    private static func parse(_ b: [UInt8], _ idx: Int) -> (TLV, Int)? {
        guard idx < b.count else { return nil }
        let tag = b[idx]
        var p = idx + 1
        guard p < b.count else { return nil }
        var length = 0
        let first = b[p]; p += 1
        if first & 0x80 == 0 {
            length = Int(first)                       // short form
        } else {
            let n = Int(first & 0x7F)                 // long form: n length bytes
            guard n > 0, n <= 4, p + n <= b.count else { return nil }
            for _ in 0..<n { length = (length << 8) | Int(b[p]); p += 1 }
        }
        guard p + length <= b.count else { return nil }
        return (TLV(tag: tag, valueStart: p, valueLength: length), p + length)
    }

    private static let SEQUENCE: UInt8 = 0x30
    private static let UTCTIME: UInt8 = 0x17
    private static let GENTIME: UInt8 = 0x18

    /// Walk the cert to locate the Validity SEQUENCE and decode its two times.
    static func findValidity(_ b: [UInt8]) -> (Date?, Date?) {
        // outer Certificate SEQUENCE
        guard let (cert, _) = parse(b, 0), cert.tag == SEQUENCE else { return (nil, nil) }
        // first child = tbsCertificate SEQUENCE
        guard let (tbs, _) = parse(b, cert.valueStart), tbs.tag == SEQUENCE else { return (nil, nil) }

        // Scan tbsCertificate's children for a SEQUENCE that holds exactly two
        // time values — that's Validity.
        var i = tbs.valueStart
        while i < tbs.valueEnd {
            guard let (el, next) = parse(b, i) else { break }
            if el.tag == SEQUENCE {
                if let pair = timesInside(b, el.valueStart, el.valueEnd) {
                    return pair
                }
            }
            i = next
        }
        return (nil, nil)
    }

    /// If the SEQUENCE body is [Time, Time], decode and return them.
    private static func timesInside(_ b: [UInt8], _ start: Int, _ end: Int) -> (Date?, Date?)? {
        guard let (t1, n1) = parse(b, start),
              t1.tag == UTCTIME || t1.tag == GENTIME,
              let (t2, _) = parse(b, n1),
              t2.tag == UTCTIME || t2.tag == GENTIME else { return nil }
        let d1 = decodeTime(b, t1.tag, t1.valueStart, t1.valueLength)
        let d2 = decodeTime(b, t2.tag, t2.valueStart, t2.valueLength)
        return (d1, d2)
    }

    private static func decodeTime(_ b: [UInt8], _ tag: UInt8, _ start: Int, _ len: Int) -> Date? {
        let bytes = Array(b[start..<start+len])
        guard let s = String(bytes: bytes, encoding: .ascii) else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        // UTCTime: YYMMDDHHMMSSZ  ·  GeneralizedTime: YYYYMMDDHHMMSSZ
        fmt.dateFormat = (tag == UTCTIME) ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
        return fmt.date(from: s)
    }
}
