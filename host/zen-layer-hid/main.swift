// zen-layer-hid: read the layer reports src/layer_report.c sends over Raw HID
// and print one JSON object per line on stdout.
//
//   {"event":"connected","transport":"USB","product":"ZEN"}
//   {"event":"layer","index":2,"id":2,"state":5,"name":""}
//   {"event":"disconnected","transport":"USB","product":"ZEN"}
//
// Usage: zen-layer-hid [product-name]   (default "ZEN", "" matches any)
// Exits when stdin reaches EOF, so it dies with the process that started it.

import Foundation
import IOKit.hid

let usagePage = 0xFF60
let usage = 0x61
let reportSize = 32
let magic: UInt8 = 0x4C  // 'L'
let product = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ZEN"

setvbuf(stdout, nil, _IOLBF, 0)

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let line = String(data: data, encoding: .utf8) else { return }
    print(line)
}

func warn(_ message: String) {
    FileHandle.standardError.write(("zen-layer-hid: " + message + "\n").data(using: .utf8)!)
}

func describe(_ device: IOHIDDevice) -> [String: Any] {
    let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
    return ["transport": transport, "product": name]
}

// Ask the keyboard for its current layer instead of waiting for a change.
func requestLayer(_ device: IOHIDDevice) {
    var report = [UInt8](repeating: 0, count: reportSize)
    report[0] = magic
    let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, &report, report.count)
    if result != kIOReturnSuccess {
        warn(String(format: "layer request failed: 0x%08x", result))
    }
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

var matching: [String: Any] = [
    kIOHIDDeviceUsagePageKey: usagePage,
    kIOHIDDeviceUsageKey: usage,
]
if !product.isEmpty {
    matching[kIOHIDProductKey] = product
}
IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
    var info = describe(device)
    info["event"] = "connected"
    emit(info)
    requestLayer(device)
    // BLE may drop a write sent right after the link comes up; ask once more.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { requestLayer(device) }
}, nil)

IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, device in
    var info = describe(device)
    info["event"] = "disconnected"
    emit(info)
}, nil)

IOHIDManagerRegisterInputReportCallback(manager, { _, _, _, _, _, report, length in
    // [0] magic, [1] version, [2] index, [3] id, [4..7] state (LE), [8..] name
    guard length >= 9, report[0] == magic, report[1] == 1 else { return }
    let state = UInt32(report[4]) | UInt32(report[5]) << 8 | UInt32(report[6]) << 16
        | UInt32(report[7]) << 24
    let nameEnd = (8..<length).first(where: { report[$0] == 0 }) ?? length
    let nameBytes = UnsafeBufferPointer(start: report + 8, count: nameEnd - 8)
    emit([
        "event": "layer",
        "index": Int(report[2]),
        "id": Int(report[3]),
        "state": Int(state),
        "name": String(decoding: nameBytes, as: UTF8.self),
    ])
}, nil)

IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if openResult != kIOReturnSuccess {
    warn(String(format: "IOHIDManagerOpen failed: 0x%08x", openResult))
    exit(1)
}

Thread.detachNewThread {
    while readLine() != nil {}
    exit(0)
}

CFRunLoopRun()
