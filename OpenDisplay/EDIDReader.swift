import IOKit
import CoreGraphics
import Foundation

/// Read EDID data from a display
struct EDIDReader {
    struct EDIDInfo {
        let raw: Data
        let manufacturerID: String
        let productCode: UInt16
        let serialNumber: UInt32
        let weekOfManufacture: UInt8
        let yearOfManufacture: Int
        let displayName: String?
        let maxHorizontalSize: Int
        let maxVerticalSize: Int
    }

    static func read(for displayID: CGDirectDisplayID) -> EDIDInfo? {
        // Try multiple IOKit paths — Apple Silicon uses different service trees
        if let info = readFromDisplayConnect() { return info }
        if let info = readFromDCPAV() { return info }
        return nil
    }

    /// Read all EDID infos (one per display)
    static func readAll() -> [EDIDInfo] {
        var results: [EDIDInfo] = []
        // Apple Silicon: IOPortTransportStateDisplayPort
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault,
                IOServiceMatching("IOPortTransportStateDisplayPort"), &iter) == KERN_SUCCESS {
            var svc = IOIteratorNext(iter)
            while svc != 0 {
                if let info = edidFromService(svc) { results.append(info) }
                IOObjectRelease(svc); svc = IOIteratorNext(iter)
            }
            IOObjectRelease(iter)
        }
        if !results.isEmpty { return results }

        // Intel fallback: IODisplayConnect
        if IOServiceGetMatchingServices(kIOMainPortDefault,
                IOServiceMatching("IODisplayConnect"), &iter) == KERN_SUCCESS {
            var svc = IOIteratorNext(iter)
            while svc != 0 {
                if let info = edidFromService(svc) { results.append(info) }
                IOObjectRelease(svc); svc = IOIteratorNext(iter)
            }
            IOObjectRelease(iter)
        }
        return results
    }

    // MARK: - Private

    private static func readFromDisplayConnect() -> EDIDInfo? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                IOServiceMatching("IODisplayConnect"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            defer { IOObjectRelease(svc); svc = IOIteratorNext(iter) }
            if let info = edidFromService(svc) { return info }
        }
        return nil
    }

    private static func readFromDCPAV() -> EDIDInfo? {
        // Apple Silicon: EDID is in IOPortTransportStateDisplayPort deep in the tree
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                IOServiceMatching("IOPortTransportStateDisplayPort"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            defer { IOObjectRelease(svc); svc = IOIteratorNext(iter) }
            if let info = edidFromService(svc) { return info }
        }
        return nil
    }

    private static func edidFromChildren(_ service: io_service_t) -> EDIDInfo? {
        var childIter: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(childIter) }
        var child = IOIteratorNext(childIter)
        while child != 0 {
            defer { IOObjectRelease(child); child = IOIteratorNext(childIter) }
            if let info = edidFromService(child) { return info }
            // Go one more level deep
            var grandIter: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(child, kIOServicePlane, &grandIter) == KERN_SUCCESS {
                var grand = IOIteratorNext(grandIter)
                while grand != 0 {
                    if let info = edidFromService(grand) { IOObjectRelease(grand); IOObjectRelease(grandIter); return info }
                    IOObjectRelease(grand); grand = IOIteratorNext(grandIter)
                }
                IOObjectRelease(grandIter)
            }
        }
        return nil
    }

    private static func edidFromService(_ service: io_service_t) -> EDIDInfo? {
        // Try IODisplayCreateInfoDictionary
        if let dict = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any],
           let edidData = dict[kIODisplayEDIDKey] as? Data {
            return parseEDID(edidData)
        }
        // Try direct property
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }

        // Check "EDID" key directly
        if let edidData = dict["EDID"] as? Data { return parseEDID(edidData) }
        // Check nested Metadata
        if let meta = dict["Metadata"] as? [String: Any], let edidData = meta["EDID"] as? Data {
            return parseEDID(edidData)
        }
        return nil
    }

    static func parseEDID(_ data: Data) -> EDIDInfo? {
        let bytes = [UInt8](data)
        guard bytes.count >= 128, bytes[0] == 0x00, bytes[1] == 0xFF, bytes[7] == 0x00 else { return nil }

        let mfg = decodeManufacturer(bytes[8], bytes[9])
        let product = UInt16(bytes[10]) | (UInt16(bytes[11]) << 8)
        let serial = UInt32(bytes[12]) | (UInt32(bytes[13]) << 8) | (UInt32(bytes[14]) << 16) | (UInt32(bytes[15]) << 24)
        let week = bytes[16]
        let year = Int(bytes[17]) + 1990
        let hSize = Int(bytes[21])
        let vSize = Int(bytes[22])
        let name = extractDisplayName(from: bytes)

        return EDIDInfo(raw: data, manufacturerID: mfg, productCode: product,
                        serialNumber: serial, weekOfManufacture: week,
                        yearOfManufacture: year, displayName: name,
                        maxHorizontalSize: hSize, maxVerticalSize: vSize)
    }

    private static func decodeManufacturer(_ b1: UInt8, _ b2: UInt8) -> String {
        let val = (UInt16(b1) << 8) | UInt16(b2)
        let c1 = Character(UnicodeScalar(((val >> 10) & 0x1F) + 0x40)!)
        let c2 = Character(UnicodeScalar(((val >> 5) & 0x1F) + 0x40)!)
        let c3 = Character(UnicodeScalar((val & 0x1F) + 0x40)!)
        return String([c1, c2, c3])
    }

    private static func extractDisplayName(from bytes: [UInt8]) -> String? {
        for block in stride(from: 54, through: 108, by: 18) {
            guard block + 17 < bytes.count else { continue }
            if bytes[block] == 0 && bytes[block + 1] == 0 && bytes[block + 3] == 0xFC {
                let nameBytes = bytes[(block + 5)..<min(block + 18, bytes.count)]
                let name = String(nameBytes.map { Character(UnicodeScalar($0)) })
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }
}
