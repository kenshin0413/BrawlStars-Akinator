//
//  BrawlStars_AkinatorApp.swift
//  BrawlStars Akinator
//
//  Created by miyamotokenshin on R 8/09/01.
//

import SwiftUI
import FirebaseCore
import FirebaseAnalytics

@main
struct BrawlStars_AkinatorApp: App {
    init() {
        FirebaseApp.configure()
        Analytics.logEvent("app_started", parameters: nil)

        #if DEBUG
        let issues = QuestionDatabase.validationIssues()
        assert(issues.isEmpty, "Database integrity errors:\n\(issues.joined(separator: "\n"))")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
