import CoreGraphics
import IOKit
import IOKit.i2c

/// DDC/CI VCP codes
enum DDCCommand: UInt8 {
    case brightness      = 0x10
    case contrast        = 0x12
    case volume          = 0x62
    case mute            = 0x8D
    case inputSource     = 0x60
    case powerMode       = 0xD6
    case colorTemp       = 0x0C
    case redGain         = 0x16
    case greenGain       = 0x18
    case blueGain        = 0x1A
    case sharpness       = 0x87
}

enum DDCInputSource: UInt16, CaseIterable, Identifiable {
    case vga1 = 0x01, dvi1 = 0x03, dp1 = 0x0F, dp2 = 0x10
    case hdmi1 = 0x11, hdmi2 = 0x12, usbc = 0x13
    var id: UInt16 { rawValue }
    var label: String {
        switch self {
        case .vga1: "VGA"; case .dvi1: "DVI"
        case .dp1: "DP 1"; case .dp2: "DP 2"
        case .hdmi1: "HDMI 1"; case .hdmi2: "HDMI 2"
        case .usbc: "USB-C"
        }
    }
}

enum DDCPowerMode: UInt16, CaseIterable, Identifiable {
    case on = 0x01, standby = 0x02, off = 0x04
    var id: UInt16 { rawValue }
    var label: String {
        switch self { case .on: "On"; case .standby: "Standby"; case .off: "Off" }
    }
}

// MARK: - IOAVService private API (Apple Silicon DDC)

private let ioavLib: UnsafeMutableRawPointer? = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

private typealias AVCreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
private typealias AVReadFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn
private typealias AVWriteFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn

private let avCreate: AVCreateFn? = {
    guard let lib = ioavLib, let s = dlsym(lib, "IOAVServiceCreateWithService") else { return nil }
    return unsafeBitCast(s, to: AVCreateFn.self)
}()
private let avRead: AVReadFn? = {
    guard let lib = ioavLib, let s = dlsym(lib, "IOAVServiceReadI2C") else { return nil }
    return unsafeBitCast(s, to: AVReadFn.self)
}()
private let avWrite: AVWriteFn? = {
    guard let lib = ioavLib, let s = dlsym(lib, "IOAVServiceWriteI2C") else { return nil }
    return unsafeBitCast(s, to: AVWriteFn.self)
}()

struct DDCControl {
    /// Read current and max value for a VCP code
    static func read(command: DDCCommand, for displayID: CGDirectDisplayID) -> (current: Int, max: Int)? {
        if let r = readAppleSilicon(command: command, for: displayID) { return r }
        return readIntel(command: command, for: displayID)
    }

    /// Write a VCP value
    @discardableResult
    static func write(command: DDCCommand, value: UInt16, for displayID: CGDirectDisplayID) -> Bool {
        if writeAppleSilicon(command: command, value: value, for: displayID) { return true }
        return writeIntel(command: command, value: value, for: displayID)
    }

    // MARK: - Apple Silicon (IOAVService + DCPAVServiceProxy)

    private static func readAppleSilicon(command: DDCCommand, for displayID: CGDirectDisplayID) -> (current: Int, max: Int)? {
        guard let avWrite, let avRead else { return nil }

        for service in avServices() {
            // Send DDC get VCP request: [length|0x80, 0x01, vcp_code, checksum]
            var send: [UInt8] = [0x82, 0x01, command.rawValue]
            send.append(send.reduce(UInt8(0x6E ^ 0x51), ^))

            guard avWrite(service, 0x37, 0x51, &send, UInt32(send.count)) == KERN_SUCCESS else { continue }
            usleep(50000) // 50ms for monitor to process

            // Read reply: [src, length, result_code, error, vcp, type, max_hi, max_lo, cur_hi, cur_lo, chk]
            var reply = [UInt8](repeating: 0, count: 11)
            guard avRead(service, 0x37, 0x51, &reply, UInt32(reply.count)) == KERN_SUCCESS,
                  reply[2] == 0x02 else { continue }

            let maxVal = Int(reply[6]) << 8 | Int(reply[7])
            let curVal = Int(reply[8]) << 8 | Int(reply[9])
            return (curVal, maxVal)
        }
        return nil
    }

    private static func writeAppleSilicon(command: DDCCommand, value: UInt16, for displayID: CGDirectDisplayID) -> Bool {
        guard let avWrite else { return false }

        for service in avServices() {
            // DDC set VCP: [length|0x80, 0x03, vcp_code, value_hi, value_lo, checksum]
            var send: [UInt8] = [0x84, 0x03, command.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)]
            send.append(send.reduce(UInt8(0x6E ^ 0x51), ^))

            if avWrite(service, 0x37, 0x51, &send, UInt32(send.count)) == KERN_SUCCESS {
                return true
            }
        }
        return false
    }

    /// Get all IOAVService instances from DCPAVServiceProxy
    private static func avServices() -> [CFTypeRef] {
        guard let avCreate else { return [] }
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                IOServiceMatching("DCPAVServiceProxy"), &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }

        var services: [CFTypeRef] = []
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            if let av = avCreate(kCFAllocatorDefault, svc)?.takeRetainedValue() {
                services.append(av)
            }
            IOObjectRelease(svc)
            svc = IOIteratorNext(iter)
        }
        return services
    }

    // MARK: - Intel fallback (IOFramebuffer I2C)

    private static func readIntel(command: DDCCommand, for displayID: CGDirectDisplayID) -> (current: Int, max: Int)? {
        guard let fb = framebufferPort(for: displayID) else { return nil }
        defer { IOObjectRelease(fb) }

        var req = IOI2CRequest()
        req.commFlags = 0; req.sendAddress = 0x6E
        req.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
        req.replyTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
        req.replyAddress = 0x6F

        var send: [UInt8] = [0x51, 0x82, 0x01, command.rawValue, 0x00]
        send[4] = send.dropFirst().reduce(0x50, ^)
        req.sendBytes = UInt32(send.count)
        var reply = [UInt8](repeating: 0, count: 12)
        req.replyBytes = UInt32(reply.count)

        let ok = send.withUnsafeMutableBufferPointer { s in
            reply.withUnsafeMutableBufferPointer { r in
                req.sendBuffer = vm_address_t(Int(bitPattern: s.baseAddress))
                req.replyBuffer = vm_address_t(Int(bitPattern: r.baseAddress))
                return sendI2C(fb: fb, req: &req)
            }
        }
        guard ok, reply[3] == 0x02 else { return nil }
        return (Int(reply[8]) << 8 | Int(reply[9]), Int(reply[6]) << 8 | Int(reply[7]))
    }

    private static func writeIntel(command: DDCCommand, value: UInt16, for displayID: CGDirectDisplayID) -> Bool {
        guard let fb = framebufferPort(for: displayID) else { return false }
        defer { IOObjectRelease(fb) }

        var req = IOI2CRequest()
        req.commFlags = 0; req.sendAddress = 0x6E
        req.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
        req.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)

        var send: [UInt8] = [0x51, 0x84, 0x03, command.rawValue, UInt8(value >> 8), UInt8(value & 0xFF), 0x00]
        send[6] = send.dropFirst().reduce(0x50, ^)
        req.sendBytes = UInt32(send.count); req.replyBytes = 0

        return send.withUnsafeMutableBufferPointer { buf in
            req.sendBuffer = vm_address_t(Int(bitPattern: buf.baseAddress))
            return sendI2C(fb: fb, req: &req)
        }
    }

    private static func framebufferPort(for displayID: CGDirectDisplayID) -> io_service_t? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                IOServiceMatching("IOFramebuffer"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            var cnt: io_iterator_t = 0
            if IOFBGetI2CInterfaceCount(svc, &cnt) == KERN_SUCCESS, cnt > 0 { return svc }
            IOObjectRelease(svc); svc = IOIteratorNext(iter)
        }
        return nil
    }

    private static func sendI2C(fb: io_service_t, req: inout IOI2CRequest) -> Bool {
        var cnt: io_iterator_t = 0
        guard IOFBGetI2CInterfaceCount(fb, &cnt) == KERN_SUCCESS, cnt > 0 else { return false }
        var iface: io_service_t = 0
        guard IOFBCopyI2CInterfaceForBus(fb, 0, &iface) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iface) }
        var conn: IOI2CConnectRef?
        guard IOI2CInterfaceOpen(iface, 0, &conn) == KERN_SUCCESS, let c = conn else { return false }
        defer { IOI2CInterfaceClose(c, 0) }
        return IOI2CSendRequest(c, 0, &req) == KERN_SUCCESS && req.result == KERN_SUCCESS
    }
}
