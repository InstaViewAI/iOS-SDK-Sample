//
//  Logger.swift
//  Sandbox
//

import Foundation

/// Timestamped console logging, compiled out of release builds.
enum Logger {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static let formatterQueue = DispatchQueue(label: "sandbox.logger")

    static func debugLog(_ items: Any..., separator: String = " ") {
//        #if DEBUG
        let timestamp = formatterQueue.sync { dateFormatter.string(from: Date()) }
        let output = items.map { "\($0)" }.joined(separator: separator)
        print("[\(timestamp)] \(output)")
//        #endif
        
    }
}
