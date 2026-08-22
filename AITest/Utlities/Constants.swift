//
//  Constants.swift
//  AITest
//
//  Created by Karthikeyan Paramasivam on 7/20/25.
//

import Foundation

struct HelpAndSupport {
    static let supportEmail = "support@vishuddhi.in"
}

/// Time window for editing/deleting sales and movements (S27).
enum EditPolicy {
    static let windowDays = 7

    static func isWithinEditWindow(createdAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(createdAt) <= Double(windowDays) * 86_400
    }
}
