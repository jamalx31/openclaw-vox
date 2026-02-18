import Foundation
import Carbon
import CoreGraphics

enum HotkeyEvent: String {
    case down
    case up
}

protocol HotkeyService: AnyObject {
    var sourceName: String { get }
}

// MARK: - EventTap backend (requires Input Monitoring)

final class EventTapHotkeyService: HotkeyService {
    let sourceName = "eventTap"

    private let onEvent: (HotkeyEvent, String) -> Void
    private let targetKeyCode: Int64
    private let requiredFlags: CGEventFlags
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    static func preflightAccess() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }
        return true
    }

    static func requestAccessPrompt() {
        if #available(macOS 10.15, *) {
            _ = CGRequestListenEventAccess()
        }
    }

    init?(keyCode: UInt32, modifiers: UInt32, onEvent: @escaping (HotkeyEvent, String) -> Void) {
        guard Self.preflightAccess() else {
            ocvLog("HotKey", "backend=eventTap unavailable (Input Monitoring not granted)")
            return nil
        }

        self.onEvent = onEvent
        self.targetKeyCode = Int64(keyCode)
        self.requiredFlags = Self.cgFlags(fromCarbonModifiers: modifiers)

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<EventTapHotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            ocvLog("HotKey", "backend=eventTap creation failed")
            return nil
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ocvLog("HotKey", "backend=eventTap started keyCode=\(keyCode) modifiers=\(modifiers)")
        } else {
            ocvLog("HotKey", "backend=eventTap runloop source failed")
            return nil
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable the tap if macOS disabled it (timeout, screenshot, etc.)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                ocvLog("HotKey", "eventTap re-enabled after \(type == .tapDisabledByTimeout ? "timeout" : "user-input") disable")
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == targetKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        guard flags.contains(requiredFlags) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            guard !isPressed else { return Unmanaged.passUnretained(event) }
            isPressed = true
            onEvent(.down, sourceName)
        } else {
            guard isPressed else { return Unmanaged.passUnretained(event) }
            isPressed = false
            onEvent(.up, sourceName)
        }

        return Unmanaged.passUnretained(event)
    }

    private static func cgFlags(fromCarbonModifiers modifiers: UInt32) -> CGEventFlags {
        var flags: CGEventFlags = []
        if (modifiers & UInt32(cmdKey)) != 0 { flags.insert(.maskCommand) }
        if (modifiers & UInt32(controlKey)) != 0 { flags.insert(.maskControl) }
        if (modifiers & UInt32(optionKey)) != 0 { flags.insert(.maskAlternate) }
        if (modifiers & UInt32(shiftKey)) != 0 { flags.insert(.maskShift) }
        return flags
    }

    deinit {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap = eventTap { CFMachPortInvalidate(tap) }
    }
}

// MARK: - Carbon hotkey fallback (no Input Monitoring needed)

final class CarbonHotkeyService: HotkeyService {
    let sourceName = "carbon"

    private var hotKeyRef: EventHotKeyRef?
    private static var handlerRef: EventHandlerRef?
    private static var callbacks: [UInt32: (HotkeyEvent, String) -> Void] = [:]
    private let id: UInt32

    init(keyCode: UInt32, modifiers: UInt32, onEvent: @escaping (HotkeyEvent, String) -> Void) {
        id = UInt32.random(in: 1...UInt32.max)
        Self.callbacks[id] = onEvent

        let hotKeyID = EventHotKeyID(signature: OSType(0x56585831), id: id) // "VXX1"
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        ocvLog("HotKey", "backend=carbon register status=\(registerStatus) keyCode=\(keyCode) modifiers=\(modifiers)")

        if Self.handlerRef == nil {
            var eventTypes = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
            ]

            let installStatus = InstallEventHandler(
                GetEventDispatcherTarget(),
                { _, event, _ in
                    var hk = EventHotKeyID()
                    GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hk
                    )

                    let kind = GetEventKind(event)
                    if kind == UInt32(kEventHotKeyPressed) {
                        CarbonHotkeyService.callbacks[hk.id]?(.down, "carbon")
                    } else if kind == UInt32(kEventHotKeyReleased) {
                        CarbonHotkeyService.callbacks[hk.id]?(.up, "carbon")
                    }
                    return noErr
                },
                2,
                &eventTypes,
                nil,
                &Self.handlerRef
            )
            ocvLog("HotKey", "backend=carbon handler install status=\(installStatus)")
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        Self.callbacks.removeValue(forKey: id)
    }
}
