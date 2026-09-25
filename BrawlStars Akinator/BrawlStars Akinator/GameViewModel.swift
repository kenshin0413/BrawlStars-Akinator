import Foundation
import Observation
import FirebaseAnalytics

@MainActor @Observable
final class GameViewModel {
    static let reviewAnswerThreshold = 2
    static let reviewCooldown: TimeInterval = 15 * 24 * 60 * 60
    static let gamesPerInterstitial = 3
    enum Phase { case home, playing, guessing, finished }
    private(set) var phase: Phase = .home
    private(set) var target: Brawler?
    private(set) var history: [AskedQuestion] = []
    private(set) var guessedBrawler: Brawler?
    private(set) var wasCorrect = false
    var selectedCategory: QuestionCategory = .popular
    var searchText = ""
    var reportPresented = false
    var infoPresented = false
    var reportQuestion: AskedQuestion?
    private(set) var reviewRequestPending = false
    var favoriteQuestionIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "favoriteQuestionIDs") ?? [])
    let maxQuestions = 8

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTestPlaying") || arguments.contains("-uiTestBasic") || arguments.contains("-uiTestMovement") || arguments.contains("-uiTestSpecial") || arguments.contains("-uiTestPicker") || arguments.contains("-uiTestHistory") || arguments.contains("-uiTestTwoQuestions") || arguments.contains("-uiTestThreeQuestions") || arguments.contains("-uiTestEightQuestions") || arguments.contains("-uiTestGuessing") || arguments.contains("-uiTestResult") || arguments.contains("-uiTestReport") {
            startGame()
        }
        if (arguments.contains("-uiTestHistory") || arguments.contains("-uiTestReport")), let question = QuestionDatabase.all.first(where: { $0.id == "stat.class.assassin" }) {
            ask(question)
        }
        if arguments.contains("-uiTestGuessing") { beginGuess() }
        if arguments.contains("-uiTestTwoQuestions") {
            QuestionDatabase.all.prefix(2).forEach(ask)
        }
        if arguments.contains("-uiTestThreeQuestions") {
            QuestionDatabase.all.prefix(3).forEach(ask)
        }
        if arguments.contains("-uiTestEightQuestions") {
            QuestionDatabase.all.prefix(maxQuestions).forEach(ask)
        }
        if arguments.contains("-uiTestResult"), let target {
            guessedBrawler = target; wasCorrect = true; phase = .finished
        }
        if arguments.contains("-uiTestReport"), let item = history.last {
            reportQuestion = item; reportPresented = true
        }
        if arguments.contains("-uiTestInfo") { infoPresented = true }
        #endif
    }

    var playCount: Int { UserDefaults.standard.integer(forKey: "playCount") }
    var winCount: Int { UserDefaults.standard.integer(forKey: "winCount") }
    var winRateText: String {
        guard playCount > 0 else { return "—" }
        return "\(Int((Double(winCount) / Double(playCount) * 100).rounded()))%"
    }
    var resultShareText: String {
        let result = wasCorrect ? "正解" : "不正解"
        return "ブロスタ逆アキネーターで\(history.count)問使って\(result)！あなたも8問で見抜ける？"
    }

    var remainingQuestions: Int { max(0, maxQuestions - history.count) }
    var isInterstitialDue: Bool {
        Self.isInterstitialDue(
            completedGames: UserDefaults.standard.integer(forKey: "completedGamesSinceInterstitial")
        )
    }
    var canAsk: Bool { phase == .playing && history.count < maxQuestions }
    var availableQuestions: [GameQuestion] {
        let used = Set(history.map { $0.question.id })
        return QuestionDatabase.all.filter { question in
            guard !used.contains(question.id) else { return false }
            let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let textMatch = question.text.localizedCaseInsensitiveContains(term) || question.detail.localizedCaseInsensitiveContains(term)
            if !term.isEmpty { return textMatch }
            return selectedCategory == .popular ? question.popular : question.category == selectedCategory
        }
    }

    var availableCategories: [QuestionCategory] {
        [.popular] + QuestionCategory.allCases.filter { category in
            category != .popular && QuestionDatabase.all.contains { $0.category == category }
        }
    }

    var favoriteQuestions: [GameQuestion] {
        QuestionDatabase.all.filter { favoriteQuestionIDs.contains($0.id) && !usedQuestionIDs.contains($0.id) }
    }

    var recentQuestions: [GameQuestion] {
        let ids = UserDefaults.standard.stringArray(forKey: "recentQuestionIDs") ?? []
        let questions = Dictionary(uniqueKeysWithValues: QuestionDatabase.all.map { ($0.id, $0) })
        return ids.compactMap { questions[$0] }.filter { !usedQuestionIDs.contains($0.id) }
    }

    var starterQuestions: [GameQuestion] {
        let preferredIDs = [
            "stat.class.assassin", "stat.class.tank", "stat.range.長距離",
            "stat.speed.高速", "attack.multiple", "attack.piercing",
            "special.wallBreaking", "special.healPlayers"
        ]
        let byID = Dictionary(uniqueKeysWithValues: QuestionDatabase.all.map { ($0.id, $0) })
        return preferredIDs.compactMap { byID[$0] }.filter { !usedQuestionIDs.contains($0.id) }
    }

    private var usedQuestionIDs: Set<String> { Set(history.map { $0.question.id }) }

    func startGame() {
        let all = BrawlerDatabase.brawlers
        let recent = Set(UserDefaults.standard.array(forKey: "recentBrawlerIDs") as? [Int] ?? [])
        let pool = all.filter { !recent.contains($0.id) }
        target = (pool.isEmpty ? all : pool).randomElement()
        history = []; guessedBrawler = nil; wasCorrect = false; searchText = ""; selectedCategory = .popular; phase = .playing
        Analytics.logEvent("mode_selected", parameters: ["mode": "reverse_akinator"])
        Analytics.logEvent("akinator_started", parameters: nil)
    }
    func ask(_ question: GameQuestion) {
        guard canAsk, let target, let answer = question.answer(for: target) else { return }
        history.append(AskedQuestion(question: question, answer: answer))
        rememberQuestion(question.id)
        Analytics.logEvent("akinator_question_asked", parameters: [
            "question_id": question.id,
            "answer": answer.rawValue,
            "question_number": history.count
        ])
    }
    func isFavorite(_ question: GameQuestion) -> Bool { favoriteQuestionIDs.contains(question.id) }
    func toggleFavorite(_ question: GameQuestion) {
        if favoriteQuestionIDs.contains(question.id) { favoriteQuestionIDs.remove(question.id) }
        else { favoriteQuestionIDs.insert(question.id) }
        UserDefaults.standard.set(Array(favoriteQuestionIDs), forKey: "favoriteQuestionIDs")
    }
    func beginGuess() { guard phase == .playing else { return }; phase = .guessing }
    func submitGuess(_ brawler: Brawler) {
        guard phase == .guessing, let target else { return }
        guessedBrawler = brawler; wasCorrect = brawler.id == target.id; remember(target.id)
        Analytics.logEvent("akinator_answered", parameters: [
            "result": wasCorrect ? "correct" : "wrong",
            "questions_used": history.count,
            "target_id": target.id
        ])
        UserDefaults.standard.set(playCount + 1, forKey: "playCount")
        if wasCorrect { UserDefaults.standard.set(winCount + 1, forKey: "winCount") }
        let adGameCount = UserDefaults.standard.integer(forKey: "completedGamesSinceInterstitial") + 1
        UserDefaults.standard.set(adGameCount, forKey: "completedGamesSinceInterstitial")
        phase = .finished
        registerCompletedAnswerForReview()
    }
    func registerExternalCompletedGame(wasCorrect: Bool) {
        UserDefaults.standard.set(playCount + 1, forKey: "playCount")
        if wasCorrect { UserDefaults.standard.set(winCount + 1, forKey: "winCount") }
        let adGameCount = UserDefaults.standard.integer(forKey: "completedGamesSinceInterstitial") + 1
        UserDefaults.standard.set(adGameCount, forKey: "completedGamesSinceInterstitial")
        registerCompletedAnswerForReview()
    }
    func markInterstitialPresented() {
        UserDefaults.standard.set(0, forKey: "completedGamesSinceInterstitial")
    }
    func markReviewRequestAttempted() {
        guard reviewRequestPending else { return }
        UserDefaults.standard.set(0, forKey: "completedAnswersSinceReviewRequest")
        UserDefaults.standard.set(Date(), forKey: "lastReviewRequestAt")
        reviewRequestPending = false
    }
    func returnHome() { phase = .home }
    func openReport(for item: AskedQuestion) { reportQuestion = item; reportPresented = true }
    func saveReport(note: String) {
        guard let target, let item = reportQuestion else { return }
        let report = WrongAnswerReport(id: UUID(), createdAt: Date(), brawlerID: target.id, brawlerName: target.name, questionID: item.question.id, question: item.question.text, shownAnswer: item.answer.rawValue, note: note)
        var reports = loadReports(); reports.append(report)
        if let data = try? JSONEncoder().encode(reports) { UserDefaults.standard.set(data, forKey: "wrongAnswerReports") }
        reportPresented = false
    }
    private func loadReports() -> [WrongAnswerReport] {
        guard let data = UserDefaults.standard.data(forKey: "wrongAnswerReports") else { return [] }
        return (try? JSONDecoder().decode([WrongAnswerReport].self, from: data)) ?? []
    }
    private func remember(_ id: Int) {
        var recent = UserDefaults.standard.array(forKey: "recentBrawlerIDs") as? [Int] ?? []
        recent.removeAll { $0 == id }; recent.insert(id, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(min(12, max(1, BrawlerDatabase.brawlers.count / 8)))), forKey: "recentBrawlerIDs")
    }
    private func rememberQuestion(_ id: String) {
        var recent = UserDefaults.standard.stringArray(forKey: "recentQuestionIDs") ?? []
        recent.removeAll { $0 == id }; recent.insert(id, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(12)), forKey: "recentQuestionIDs")
    }

    private func registerCompletedAnswerForReview() {
        let defaults = UserDefaults.standard
        let key = "completedAnswersSinceReviewRequest"
        let completedCount = defaults.integer(forKey: key) + 1
        defaults.set(completedCount, forKey: key)
        guard Self.isReviewRequestEligible(
            completedCount: completedCount,
            lastRequest: defaults.object(forKey: "lastReviewRequestAt") as? Date
        ) else { return }
        reviewRequestPending = true
    }

    static func isReviewRequestEligible(
        completedCount: Int,
        lastRequest: Date?,
        now: Date = Date()
    ) -> Bool {
        guard completedCount >= reviewAnswerThreshold else { return false }
        guard let lastRequest else { return true }
        return now.timeIntervalSince(lastRequest) >= reviewCooldown
    }

    static func isInterstitialDue(completedGames: Int) -> Bool {
        completedGames >= gamesPerInterstitial
    }
}
