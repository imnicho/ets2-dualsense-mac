import Foundation
import IOKit
import IOKit.hid

public struct DeviceInfo: Equatable, Sendable {
    public var name: String
    public var transport: Transport
    public var serial: String
    public var productID: Int
    public var isEdge: Bool { productID == 0x0DF2 }
}

public struct TransportStats: Sendable {
    public var reportsSent: UInt64 = 0
    public var sendFailures: UInt64 = 0
    public var lastResult: Int32 = 0
    public var lastSendMicros: Double = 0
    public var maxSendMicros: Double = 0
    public var inputReports: UInt64 = 0
    public init() {}
}

/// Finds DualSense controllers and exchanges raw HID reports with one of them.
/// The device is opened non-exclusively, so games keep receiving its input.
public final class DualSenseManager: @unchecked Sendable {
    public static let vendorID = 0x054C
    public static let productIDs = [0x0CE6, 0x0DF2]

    public var onConnectionChange: (@Sendable (DeviceInfo?) -> Void)?
    public var onLog: (@Sendable (String) -> Void)?

    private let lock = NSLock()
    private var manager: IOHIDManager?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var devices: [(IOHIDDevice, DeviceInfo)] = []
    private var buffers: [UnsafeMutablePointer<UInt8>] = []
    private var _input = InputState()
    private var _stats = TransportStats()
    private var sequence: UInt8 = 0
    private var lastSent: [UInt8] = []
    private var lastSentAt: UInt64 = 0
    private static let inputBufferSize = 128

    public init() {}

    public var device: DeviceInfo? { lock.withLock { devices.first?.1 } }
    public var input: InputState { lock.withLock { _input } }
    public var stats: TransportStats { lock.withLock { _stats } }

    public func start() {
        guard thread == nil else { return }
        let t = Thread { [self] in
            let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let matches = Self.productIDs.map {
                [kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: $0] as CFDictionary
            }
            IOHIDManagerSetDeviceMatchingMultiple(m, matches as CFArray)
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, dev in
                Unmanaged<DualSenseManager>.fromOpaque(ctx!).takeUnretainedValue().attached(dev)
            }, ctx)
            IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, dev in
                Unmanaged<DualSenseManager>.fromOpaque(ctx!).takeUnretainedValue().detached(dev)
            }, ctx)
            IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
            if r != kIOReturnSuccess { onLog?("IOHIDManagerOpen failed: \(Self.describe(r))") }
            lock.withLock { manager = m; runLoop = CFRunLoopGetCurrent() }
            CFRunLoopRun()
        }
        t.name = "DualSense HID"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    public func stop() {
        lock.withLock {
            if let rl = runLoop { CFRunLoopStop(rl) }
            if let m = manager { IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone)) }
            manager = nil; runLoop = nil; devices = []
        }
        thread = nil
    }

    private func attached(_ dev: IOHIDDevice) {
        // A controller exposes one gamepad interface; ignore anything else with the same IDs.
        let usagePage = IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        guard usagePage == kHIDPage_GenericDesktop, usage == kHIDUsage_GD_GamePad || usage == kHIDUsage_GD_Joystick else { return }
        let transportName = IOHIDDeviceGetProperty(dev, kIOHIDTransportKey as CFString) as? String ?? ""
        let transport: Transport = transportName.lowercased().contains("bluetooth") ? .bluetooth : .usb
        let info = DeviceInfo(
            name: IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "DualSense",
            transport: transport,
            serial: IOHIDDeviceGetProperty(dev, kIOHIDSerialNumberKey as CFString) as? String ?? "",
            productID: IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? 0)

        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.inputBufferSize)
        IOHIDDeviceRegisterInputReportCallback(dev, buf, Self.inputBufferSize, { ctx, _, _, _, _, report, length in
            Unmanaged<DualSenseManager>.fromOpaque(ctx!).takeUnretainedValue()
                .received(UnsafeBufferPointer(start: report, count: length))
        }, Unmanaged.passUnretained(self).toOpaque())

        let first = lock.withLock { () -> Bool in
            devices.removeAll { $0.0 === dev }
            devices.append((dev, info))
            buffers.append(buf)
            return devices.count == 1
        }
        onLog?("Connected: \(info.name) via \(info.transport.rawValue)")
        if transport == .bluetooth {
            // Reading the calibration feature report switches the controller to full 0x31 reports.
            var data = [UInt8](repeating: 0, count: 41)
            var len = data.count
            let r = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 0x05, &data, &len)
            if r != kIOReturnSuccess { onLog?("Feature report 0x05 read failed: \(Self.describe(r))") }
        }
        if first {
            lock.withLock { lastSent = []; _input = InputState() }
            onConnectionChange?(info)
        }
    }

    private func detached(_ dev: IOHIDDevice) {
        let (wasPrimary, next) = lock.withLock { () -> (Bool, DeviceInfo?) in
            let wasPrimary = devices.first.map { $0.0 === dev } ?? false
            devices.removeAll { $0.0 === dev }
            if wasPrimary { lastSent = []; _input = InputState() }
            return (wasPrimary, devices.first?.1)
        }
        if wasPrimary {
            onLog?("Controller disconnected")
            onConnectionChange?(next)
        }
    }

    private func received(_ report: UnsafeBufferPointer<UInt8>) {
        guard let s = InputState.parse(report) else { return }
        lock.withLock { _input = s; _stats.inputReports &+= 1 }
    }

    /// Sends `state` to the active controller. Identical consecutive states are skipped unless
    /// `force` is set or the last write is older than `keepAlive` seconds.
    @discardableResult
    public func send(_ state: OutputState, force: Bool = false, keepAlive: Double = 1.0, releaseLEDs: Bool = false) -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        let target: (IOHIDDevice, Transport, UInt8)? = lock.withLock {
            guard let (dev, info) = devices.first else { return nil }
            sequence = (sequence &+ 1) & 0x0f
            return (dev, info.transport, sequence)
        }
        guard let (dev, transport, seq) = target else { return false }
        let payload = OutputReport.encode(state, transport: .usb, releaseLEDs: releaseLEDs)
        let unchanged = lock.withLock { payload == lastSent && Double(now - lastSentAt) / 1e9 < keepAlive }
        if unchanged && !force { return true }

        let report = OutputReport.encode(state, transport: transport, sequence: seq, releaseLEDs: releaseLEDs)
        let r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
        let micros = Double(DispatchTime.now().uptimeNanoseconds - now) / 1000
        lock.withLock {
            _stats.reportsSent &+= 1
            _stats.lastResult = r
            _stats.lastSendMicros = micros
            _stats.maxSendMicros = max(_stats.maxSendMicros, micros)
            if r == kIOReturnSuccess { lastSent = payload; lastSentAt = now } else { _stats.sendFailures &+= 1 }
        }
        return r == kIOReturnSuccess
    }

    /// Triggers off, motors off, LEDs handed back to the controller.
    @discardableResult
    public func reset() -> Bool {
        send(OutputState(), force: true, releaseLEDs: true)
    }

    public static func describe(_ r: IOReturn) -> String {
        switch r {
        case kIOReturnSuccess: return "success"
        case kIOReturnNotPermitted: return "not permitted"
        case kIOReturnNotPrivileged: return "not privileged"
        case kIOReturnExclusiveAccess: return "device is opened exclusively by another process"
        case kIOReturnNotOpen: return "device not open"
        case kIOReturnTimeout: return "timeout"
        case kIOReturnNoDevice: return "no device"
        case kIOReturnNotResponding: return "not responding"
        default: return String(format: "IOReturn 0x%08x", UInt32(bitPattern: r))
        }
    }
}
