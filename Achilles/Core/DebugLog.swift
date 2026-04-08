// DebugLog.swift
//
// Drop-in replacement for print() that only emits output in DEBUG builds.
// Usage: debugLog("📸 Photo loaded") instead of print("📸 Photo loaded")

import Foundation

/// Prints only in DEBUG builds. Optimised away entirely in Release.
@inline(__always)
func debugLog(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let output = items.map { "\($0)" }.joined(separator: separator)
    print(output, terminator: terminator)
    #endif
}
