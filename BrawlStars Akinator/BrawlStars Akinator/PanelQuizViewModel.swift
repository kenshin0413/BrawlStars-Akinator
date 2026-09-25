import Foundation
import Observation
import FirebaseAnalytics

@MainActor @Observable
final class PanelQuizViewModel {
    enum Phase: Equatable { case idle, playing, choosing, correctFeedback, finished }
    enum EndReason: Equatable { case wrong, timeout, completed }

    private(set) var phase: Phase = .idle
    private(set) var queue: [Brawler] = []
    private(set) var current: Brawler?
    private(set) var correctCount = 0
    private(set) var passedCount = 0
    private(set) var remainingSeconds = 90
    private(set) var openPanels: Set<Int> = []
    private(set) var passAvailable = true
    private(set) var extraPanelAvailable = true
    private(set) var rarityHintAvailable = true
    private(set) var rarityRevealed = false
    private(set) var endReason: EndReason?
    private(set) var submittedAnswer: Brawler?
    private(set) var feedbackBrawler: Brawler?
    private(set) var imageReady = false
    private(set) var roundInteractive = false
    private(set) var initialOpenPanelIndex = 0
    var selectingExtraPanel = false
    var selectedAnswer: Brawler?

    private static let extraPanelBlockedIndices: Set<Int> = [5, 6, 9, 10]

    private var timerTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var paused = false

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTestPanelExtraSelection") {
            start()
            Task { @MainActor [weak self] in
                guard let self else { return }
                while !self.roundInteractive {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                self.requestExtraPanel()
            }
        } else if arguments.contains("-uiTestPanelUrgent") {
            start()
            remainingSeconds = 10
        } else if arguments.contains("-uiTestPanelAnswerPicker") {
            start()
            Task { @MainActor [weak self] in
                guard let self else { return }
                while !self.roundInteractive {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                self.beginChoosing()
            }
        } else if arguments.contains("-uiTestPanelCorrectFeedback") {
            start()
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, let current = self.current else { return }
                self.phase = .choosing
                self.submit(current)
            }
        } else if arguments.contains("-uiTestPanelResultWrong") {
            start()
            endReason = .wrong
            phase = .finished
        } else if arguments.contains("-uiTestPanelQuiz") {
            start()
        }
        #endif
    }

    var progressText: String { "\(correctCount + passedCount + 1) / \(BrawlerDatabase.brawlers.count)" }
    var nextProgressText: String { "次は \(min(correctCount + passedCount + 1, BrawlerDatabase.brawlers.count)) / \(BrawlerDatabase.brawlers.count)" }
    var bestScore: Int { UserDefaults.standard.integer(forKey: "panelQuizBestScore") }

    func start() {
        timerTask?.cancel()
        feedbackTask?.cancel()
        revealTask?.cancel()
        queue = BrawlerDatabase.brawlers.shuffled()
        correctCount = 0; passedCount = 0
        passAvailable = true; extraPanelAvailable = true; rarityHintAvailable = true
        endReason = nil; submittedAnswer = nil; feedbackBrawler = nil; paused = false
        phase = .playing
        Analytics.logEvent("mode_selected", parameters: ["mode": "panel_quiz"])
        Analytics.logEvent("panel_quiz_started", parameters: nil)
        advance()
    }

    func imageDidLoad() {
        guard phase == .playing || phase == .choosing, !imageReady else { return }
        imageReady = true
        let expectedBrawlerID = current?.id
        revealTask?.cancel()
        revealTask = Task { [weak self] in
            // Keep every panel closed for a few rendered frames after the image
            // reports success. This prevents cached images from appearing naked.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled,
                  let self,
                  self.phase == .playing,
                  self.current?.id == expectedBrawlerID else { return }
            self.openPanels = [self.initialOpenPanelIndex]
            self.roundInteractive = true
            self.startTimer()
        }
    }

    func beginChoosing() { guard phase == .playing, roundInteractive else { return }; phase = .choosing }
    func cancelChoosing() { guard phase == .choosing else { return }; phase = .playing }

    func select(_ brawler: Brawler) { guard phase == .choosing else { return }; selectedAnswer = brawler }
    func submitSelected() { guard let selectedAnswer else { return }; submit(selectedAnswer) }

    private func submit(_ brawler: Brawler) {
        guard phase == .choosing, let current else { return }
        submittedAnswer = brawler
        let isCorrect = brawler.id == current.id
        Analytics.logEvent("panel_quiz_answered", parameters: [
            "result": isCorrect ? "correct" : "wrong",
            "panels_opened": openPanels.count,
            "seconds_remaining": remainingSeconds,
            "streak_before_answer": correctCount,
            "target_id": current.id
        ])
        if isCorrect {
            correctCount += 1
            saveBest()
            showCorrectFeedback(for: current)
        } else {
            finish(.wrong)
        }
    }

    func usePass() {
        guard passAvailable, phase == .playing, roundInteractive else { return }
        Analytics.logEvent("panel_quiz_hint_used", parameters: ["hint": "pass", "streak": correctCount])
        passAvailable = false; passedCount += 1
        if queue.isEmpty { finish(.completed) } else { advance() }
    }

    func requestExtraPanel() {
        guard extraPanelAvailable, phase == .playing, roundInteractive else { return }
        selectingExtraPanel.toggle()
    }

    func openExtraPanel(_ index: Int) {
        guard selectingExtraPanel,
              extraPanelAvailable,
              canOpenExtraPanel(index) else { return }
        openPanels.insert(index); extraPanelAvailable = false; selectingExtraPanel = false
        Analytics.logEvent("panel_quiz_hint_used", parameters: [
            "hint": "extra_panel",
            "panel_index": index,
            "streak": correctCount
        ])
    }

    func canOpenExtraPanel(_ index: Int) -> Bool {
        !Self.extraPanelBlockedIndices.contains(index) && !openPanels.contains(index)
    }

    func revealRarity() {
        guard rarityHintAvailable, phase == .playing, roundInteractive else { return }
        rarityHintAvailable = false; rarityRevealed = true
        Analytics.logEvent("panel_quiz_hint_used", parameters: ["hint": "rarity", "streak": correctCount])
    }

    func setPaused(_ value: Bool) { paused = value }

    func returnToIdle() {
        timerTask?.cancel(); feedbackTask?.cancel(); revealTask?.cancel(); phase = .idle
    }

    private func advance() {
        timerTask?.cancel()
        revealTask?.cancel()
        current = queue.removeFirst()
        remainingSeconds = 90
        initialOpenPanelIndex = Int.random(in: 0..<16)
        openPanels = []
        rarityRevealed = false; selectingExtraPanel = false; submittedAnswer = nil; selectedAnswer = nil
        imageReady = false; roundInteractive = false
    }

    private func showCorrectFeedback(for brawler: Brawler) {
        timerTask?.cancel()
        feedbackTask?.cancel()
        feedbackBrawler = brawler
        phase = .correctFeedback
        let completedAllBrawlers = queue.isEmpty
        #if DEBUG
        let feedbackDelay: Duration = ProcessInfo.processInfo.arguments.contains("-uiTestPanelCorrectFeedback")
            ? .seconds(15)
            : .seconds(1.15)
        #else
        let feedbackDelay: Duration = .seconds(1.15)
        #endif
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: feedbackDelay)
            guard !Task.isCancelled, let self, self.phase == .correctFeedback else { return }
            if completedAllBrawlers {
                self.finish(.completed)
            } else {
                // Prepare the next character and all sixteen panel states while the
                // feedback screen is still covering the play area.
                self.advance()
                self.phase = .playing
                self.feedbackBrawler = nil
            }
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                if self.paused || (self.phase != .playing && self.phase != .choosing) { continue }
                self.remainingSeconds -= 1
                if self.remainingSeconds <= 0 {
                    if self.phase == .choosing, self.selectedAnswer != nil { self.submitSelected() }
                    else { self.finish(.timeout) }
                    return
                }
            }
        }
    }

    private func finish(_ reason: EndReason) {
        timerTask?.cancel(); feedbackTask?.cancel(); revealTask?.cancel()
        endReason = reason; phase = .finished; saveBest()
        let reasonName: String
        let includesCurrentRound: Int
        switch reason {
        case .wrong: reasonName = "wrong"; includesCurrentRound = 1
        case .timeout: reasonName = "timeout"; includesCurrentRound = 1
        case .completed: reasonName = "completed"; includesCurrentRound = 0
        }
        Analytics.logEvent("panel_quiz_ended", parameters: [
            "reason": reasonName,
            "correct_count": correctCount,
            "passed_count": passedCount,
            "rounds_played": correctCount + passedCount + includesCurrentRound
        ])
    }

    private func saveBest() {
        if correctCount > bestScore { UserDefaults.standard.set(correctCount, forKey: "panelQuizBestScore") }
    }

    #if DEBUG
    func debugExpireCurrentRound() {
        guard phase == .playing || phase == .choosing else { return }
        remainingSeconds = 0
        finish(.timeout)
    }
    #endif
}
