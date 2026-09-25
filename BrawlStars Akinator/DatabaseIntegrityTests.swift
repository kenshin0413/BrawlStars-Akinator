import XCTest
@testable import BrawlStars_Akinator

@MainActor
final class DatabaseIntegrityTests: XCTestCase {
    func testPanelQuizStartsWithOneOpenPanelAndNoDuplicates() async {
        let quiz = PanelQuizViewModel()
        quiz.start()
        XCTAssertEqual(quiz.openPanels.count, 0)
        quiz.imageDidLoad()
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(quiz.openPanels.count, 1)
        XCTAssertTrue(0..<16 ~= quiz.initialOpenPanelIndex)
        XCTAssertEqual(quiz.remainingSeconds, 90)
        XCTAssertEqual(quiz.queue.count + 1, BrawlerDatabase.brawlers.count)
        let runIDs = quiz.queue.map(\.id) + [quiz.current!.id]
        XCTAssertEqual(Set(runIDs).count, BrawlerDatabase.brawlers.count)
    }

    func testPanelQuizRunHintsAreSingleUseAndCenterFourCannotBeChosen() async {
        let quiz = PanelQuizViewModel()
        quiz.start()
        quiz.imageDidLoad()
        try? await Task.sleep(for: .milliseconds(250))
        quiz.revealRarity()
        XCTAssertFalse(quiz.rarityHintAvailable)
        quiz.requestExtraPanel()
        [5, 6, 9, 10].forEach { XCTAssertFalse(quiz.canOpenExtraPanel($0)) }
        let closed = (0..<16).first { quiz.canOpenExtraPanel($0) }!
        quiz.openExtraPanel(closed)
        XCTAssertFalse(quiz.extraPanelAvailable)
        XCTAssertEqual(quiz.openPanels.count, 2)
        quiz.usePass()
        XCTAssertFalse(quiz.passAvailable)
        XCTAssertEqual(quiz.passedCount, 1)
    }

    func testPanelQuizTwentyCorrectAnswersAdvanceWithoutDuplicatesOrBareImageState() async throws {
        let quiz = PanelQuizViewModel()
        quiz.start()
        var seen = Set<Int>()

        for expectedScore in 1...20 {
            let current = try XCTUnwrap(quiz.current)
            XCTAssertTrue(seen.insert(current.id).inserted, "同一プレイ中にキャラが重複: \(current.name)")
            XCTAssertTrue(quiz.openPanels.isEmpty, "画像準備前は全パネルを閉じる")
            XCTAssertFalse(quiz.roundInteractive)

            quiz.imageDidLoad()
            try? await Task.sleep(for: .milliseconds(250))
            XCTAssertEqual(quiz.openPanels.count, 1)
            XCTAssertTrue(quiz.roundInteractive)

            quiz.beginChoosing()
            quiz.select(current)
            quiz.submitSelected()
            XCTAssertEqual(quiz.phase, .correctFeedback)
            XCTAssertEqual(quiz.correctCount, expectedScore)

            try? await Task.sleep(for: .milliseconds(1_250))
            XCTAssertEqual(quiz.phase, .playing)
        }
    }

    func testPanelQuizWrongAnswerAndTimeoutFinishTheRun() async throws {
        let wrongQuiz = PanelQuizViewModel()
        wrongQuiz.start()
        wrongQuiz.imageDidLoad()
        try? await Task.sleep(for: .milliseconds(250))
        let targetID = try XCTUnwrap(wrongQuiz.current?.id)
        let wrong = try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.id != targetID })
        wrongQuiz.beginChoosing()
        wrongQuiz.select(wrong)
        wrongQuiz.submitSelected()
        XCTAssertEqual(wrongQuiz.phase, .finished)
        XCTAssertEqual(wrongQuiz.endReason, .wrong)

        let timeoutQuiz = PanelQuizViewModel()
        timeoutQuiz.start()
        timeoutQuiz.debugExpireCurrentRound()
        XCTAssertEqual(timeoutQuiz.phase, .finished)
        XCTAssertEqual(timeoutQuiz.endReason, .timeout)
    }

    func testInterstitialBecomesDueEveryThreeCompletedGames() {
        XCTAssertFalse(GameViewModel.isInterstitialDue(completedGames: 0))
        XCTAssertFalse(GameViewModel.isInterstitialDue(completedGames: 1))
        XCTAssertFalse(GameViewModel.isInterstitialDue(completedGames: 2))
        XCTAssertTrue(GameViewModel.isInterstitialDue(completedGames: 3))
    }

    func testReviewRequestEligibility() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertFalse(GameViewModel.isReviewRequestEligible(completedCount: 1, lastRequest: nil, now: now))
        XCTAssertTrue(GameViewModel.isReviewRequestEligible(completedCount: 2, lastRequest: nil, now: now))
        XCTAssertFalse(GameViewModel.isReviewRequestEligible(
            completedCount: 3,
            lastRequest: now.addingTimeInterval(-GameViewModel.reviewCooldown + 1),
            now: now
        ))
        XCTAssertTrue(GameViewModel.isReviewRequestEligible(
            completedCount: 3,
            lastRequest: now.addingTimeInterval(-GameViewModel.reviewCooldown),
            now: now
        ))
    }

    func testAppStoreVersionComparison() {
        XCTAssertTrue(AppUpdateChecker.isVersion("1.1", newerThan: "1.0"))
        XCTAssertTrue(AppUpdateChecker.isVersion("1.0.1", newerThan: "1.0"))
        XCTAssertFalse(AppUpdateChecker.isVersion("1.0", newerThan: "1.0"))
        XCTAssertFalse(AppUpdateChecker.isVersion("0.9.9", newerThan: "1.0"))
    }

    func testEveryQuestionHasExactlyOneTernaryAnswerForEveryBrawler() {
        XCTAssertTrue(QuestionDatabase.validationIssues().isEmpty, QuestionDatabase.validationIssues().joined(separator: "\n"))
    }

    func testEveryBrawlerHasOneStrongFilteringQuestion() {
        for brawler in BrawlerDatabase.brawlers {
            XCTAssertEqual(
                QuestionDatabase.unique.filter { $0.answers[brawler.id] == .yes }.count,
                1,
                brawler.name
            )
        }
    }

    func testDatabaseIdentityAndSourcesAreComplete() {
        XCTAssertFalse(BrawlerDatabase.brawlers.isEmpty)
        XCTAssertEqual(Set(BrawlerDatabase.brawlers.map(\.id)).count, BrawlerDatabase.brawlers.count)
        XCTAssertTrue(BrawlerDatabase.brawlers.allSatisfy { !$0.name.isEmpty && !$0.sourceIDs.isEmpty })
        XCTAssertTrue(BrawlerDatabase.sources.contains { $0.kind == "official" })
    }

    func testJapaneseLocalizedContentIsPresentForEveryBrawler() {
        for brawler in BrawlerDatabase.brawlers {
            XCTAssertFalse(brawler.name.isEmpty, "キャラ名: \(brawler.id)")
            XCTAssertFalse(brawler.description.isEmpty, brawler.name)
            XCTAssertFalse(brawler.className.isEmpty, brawler.name)
            XCTAssertFalse(brawler.rarity.isEmpty, brawler.name)
            XCTAssertTrue(brawler.gadgets.allSatisfy { !$0.name.isEmpty && !$0.description.isEmpty }, brawler.name)
            XCTAssertTrue(brawler.starPowers.allSatisfy { !$0.name.isEmpty && !$0.description.isEmpty }, brawler.name)
        }
    }

    func testEveryBrawlerHasStructuredCombatStats() {
        for brawler in BrawlerDatabase.brawlers {
            XCTAssertGreaterThan(brawler.movementSpeed, 0, brawler.name)
            XCTAssertGreaterThanOrEqual(brawler.attackRange, 0, brawler.name)
            XCTAssertGreaterThanOrEqual(brawler.reloadTimeMs, 0, brawler.name)
            XCTAssertGreaterThan(brawler.battleStartHitpoints, 0, brawler.name)
            XCTAssertGreaterThan(brawler.ammoCount, 0, brawler.name)
            XCTAssertFalse(brawler.classKey.isEmpty, brawler.name)
            XCTAssertFalse(brawler.movementLabels.isEmpty, brawler.name)
            XCTAssertFalse(brawler.rangeLabels.isEmpty, brawler.name)
            XCTAssertFalse(brawler.reloadLabels.isEmpty, brawler.name)
            XCTAssertFalse(brawler.statLabelSourceID.isEmpty, brawler.name)
        }
    }

    func testEveryStatDimensionPartitionsAllBrawlersExactlyOnce() {
        let prefixes = ["stat.rarity.", "stat.class.", "stat.speed.", "stat.range.", "stat.reload."]
        for prefix in prefixes {
            let questions = QuestionDatabase.structured.filter { $0.id.hasPrefix(prefix) }
            for brawler in BrawlerDatabase.brawlers {
                XCTAssertGreaterThanOrEqual(questions.filter { $0.answers[brawler.id] != .no }.count, 1, "\(prefix) / \(brawler.name)")
            }
        }
    }

    func testMovementSpeedUsesBattleStartStateOnly() throws {
        let speedQuestions = QuestionDatabase.structured.filter { $0.id.hasPrefix("stat.speed.") }
        for brawler in BrawlerDatabase.brawlers {
            XCTAssertEqual(brawler.movementLabels.count, 1, brawler.name)
            XCTAssertEqual(speedQuestions.filter { $0.answers[brawler.id] == .yes }.count, 1, brawler.name)
            XCTAssertFalse(speedQuestions.contains { $0.answers[brawler.id] == .partial }, brawler.name)
        }

        XCTAssertEqual(try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == "アッシュ" }).movementLabels, ["普通"])
        XCTAssertEqual(try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == "ボニー" }).movementLabels, ["低速"])
        let meg = try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == "メグ" })
        XCTAssertEqual(meg.movementSpeed, 720)
        XCTAssertEqual(meg.movementLabels, ["普通"])
        XCTAssertEqual(try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == "ボルト" }).movementLabels, ["超高速"])
    }

    func testConfirmedInGameRangeLabels() throws {
        let nori = try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == "ノリ" })
        XCTAssertEqual(nori.rangeLabels, ["長距離"])
        XCTAssertEqual(nori.reloadLabels, ["溜めて攻撃"])
    }

    func testWebStatLabelsAreSinglePublishedValues() {
        for brawler in BrawlerDatabase.brawlers {
            XCTAssertEqual(brawler.movementLabels.count, 1, brawler.name)
            XCTAssertEqual(brawler.rangeLabels.count, 1, brawler.name)
            XCTAssertEqual(brawler.reloadLabels.count, 1, brawler.name)
            XCTAssertEqual(brawler.statLabelSourceID, "gamewith-jp-brawler-list", brawler.name)
        }
    }

    func testPublishedArtilleryClassIsAlwaysMarkedAsThrower() {
        for brawler in BrawlerDatabase.brawlers {
            if brawler.classKey == "artillery" {
                XCTAssertTrue(brawler.isThrower, brawler.name)
            }
        }
    }

    func testAllSourceReferencesResolve() {
        let sourceIDs = Set(BrawlerDatabase.sources.map(\.id))
        for brawler in BrawlerDatabase.brawlers {
            XCTAssertTrue(Set(brawler.sourceIDs + [brawler.statLabelSourceID]).isSubset(of: sourceIDs), brawler.name)
        }
    }

    func testGameplayFactsCoverEveryBrawler() {
        XCTAssertEqual(
            Set(BrawlerDatabase.gameplayFactsFile.facts.map(\.id)),
            Set(BrawlerDatabase.brawlers.map(\.id))
        )
        XCTAssertEqual(BrawlerDatabase.gameplayFactsFile.schemaVersion, 5)
        XCTAssertEqual(BrawlerDatabase.gameplayFactsFile.policyVersion, 4)
        XCTAssertFalse(BrawlerDatabase.gameplayFactsFile.sourceIDs.isEmpty)
    }

    func testConfirmedGameplayClassificationRegressions() throws {
        func fact(_ name: String) throws -> GameplayFact {
            let brawler = try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == name })
            return try XCTUnwrap(BrawlerDatabase.gameplayFactsByID[brawler.id])
        }

        XCTAssertEqual(try fact("チェスター").singleAttack, .partial)
        XCTAssertEqual(try fact("チェスター").multipleAttack, .partial)
        XCTAssertEqual(try fact("ボニー").multipleAttack, .no)
        XCTAssertEqual(try fact("メグ").multipleAttack, .yes)
        XCTAssertEqual(try fact("クランシー").multipleAttack, .partial)
        XCTAssertEqual(try fact("ケンジ").multipleAttack, .no)
        XCTAssertEqual(try fact("ケンジ").piercingAttack, .yes)
        XCTAssertEqual(try fact("カゼ").multipleAttack, .no)
        XCTAssertEqual(try fact("カゼ").piercingAttack, .no)
        XCTAssertEqual(try fact("アンバー").singleAttack, .no)
        XCTAssertEqual(try fact("アンバー").multipleAttack, .no)
        XCTAssertEqual(try fact("アンバー").piercingAttack, .yes)
        XCTAssertEqual(try fact("カール").singleAttack, .yes)
        XCTAssertEqual(try fact("カール").multipleAttack, .no)
        XCTAssertEqual(try fact("カール").piercingAttack, .yes)
        XCTAssertEqual(try fact("Emz").singleAttack, .yes)
        XCTAssertEqual(try fact("Emz").multipleAttack, .no)
        XCTAssertEqual(try fact("Emz").piercingAttack, .yes)
        XCTAssertEqual(try fact("ラフス").wallBreaking, .partial)
        XCTAssertEqual(try fact("R-T").waterMovement, .partial)
        XCTAssertEqual(try fact("ジャネット").jumping, .partial)
        XCTAssertEqual(try fact("ナーニ").attackingPet, .no)
        XCTAssertEqual(try fact("アッシュ").singleAttack, .yes)
        XCTAssertEqual(try fact("アッシュ").multipleAttack, .no)
        XCTAssertEqual(try fact("アッシュ").piercingAttack, .yes)
        XCTAssertEqual(try fact("アッシュ").attackingPet, .yes)
        XCTAssertEqual(try fact("オーリー").singleAttack, .yes)
        XCTAssertEqual(try fact("オーリー").multipleAttack, .no)
        XCTAssertEqual(try fact("オーリー").piercingAttack, .yes)
        XCTAssertEqual(try fact("オーリー").jumping, .partial)
        XCTAssertEqual(try fact("ジャネット").singleAttack, .yes)
        XCTAssertEqual(try fact("ジャネット").multipleAttack, .no)
        XCTAssertEqual(try fact("ジャネット").wallBreaking, .no)
        XCTAssertEqual(try fact("チャック").singleAttack, .yes)
        XCTAssertEqual(try fact("チャック").multipleAttack, .partial)
        XCTAssertEqual(try fact("チャック").piercingAttack, .yes)
        XCTAssertEqual(try fact("ルミ").singleAttack, .no)
        XCTAssertEqual(try fact("ルミ").multipleAttack, .no)
        XCTAssertEqual(try fact("ルミ").piercingAttack, .yes)
        XCTAssertEqual(try fact("ミナ").piercingAttack, .partial)
        XCTAssertEqual(try fact("ノリ").piercingAttack, .yes)
        XCTAssertEqual(try fact("ノリ").jumping, .yes)
        XCTAssertEqual(try fact("ボルト").singleAttack, .no)
        XCTAssertEqual(try fact("ボルト").multipleAttack, .no)
        XCTAssertEqual(try fact("リリー").piercingAttack, .yes)
        XCTAssertEqual(try fact("スターノヴァ").piercingAttack, .yes)
        XCTAssertEqual(try fact("ナジア").piercingAttack, .yes)
        XCTAssertEqual(try fact("ジーン").wallBreaking, .yes)
        XCTAssertEqual(try fact("ミコ").wallBreaking, .no)
        XCTAssertEqual(try fact("アンジェロ").jumping, .partial)
        XCTAssertEqual(try fact("シェイド").jumping, .yes)
        XCTAssertEqual(try fact("アリー").jumping, .partial)
        XCTAssertEqual(try fact("アリー").piercingAttack, .no)
        XCTAssertEqual(try fact("ミープル").waterMovement, .partial)
        XCTAssertEqual(try fact("レオン").attackingPet, .yes)
        XCTAssertEqual(try fact("ナジア").singleAttack, .yes)
        XCTAssertEqual(try fact("ナジア").multipleAttack, .no)
        XCTAssertEqual(try fact("ボウ").singleAttack, .no)
        XCTAssertEqual(try fact("ボウ").multipleAttack, .yes)
        XCTAssertEqual(try fact("ブル").piercingAttack, .partial)
        XCTAssertEqual(try fact("ブロック").piercingAttack, .no)
        XCTAssertEqual(try fact("グリフ").piercingAttack, .partial)
        XCTAssertEqual(try fact("8ビット").attackingPet, .no)
        XCTAssertFalse(BrawlerDatabase.gameplayFactsFile.facts.contains { $0.attackingPet == .partial })

        XCTAssertEqual(try fact("フランケン").canStun, .yes)
        XCTAssertEqual(try fact("ニタ").canStun, .partial)
        XCTAssertEqual(try fact("フィンクス").canStun, .no)
        XCTAssertEqual(try fact("グローウィー").canHealPlayers, .yes)
        XCTAssertEqual(try fact("タラ").canHealPlayers, .partial)
        XCTAssertEqual(try fact("ジェシー").canHealPlayers, .no)
        XCTAssertEqual(try fact("ティック").canHealPlayers, .no)
        XCTAssertEqual(try fact("スパイク").canSlow, .yes)
        XCTAssertEqual(try fact("シリウス").canSlow, .partial)
        XCTAssertEqual(try fact("ダミアン").canKnockback, .yes)
        XCTAssertEqual(try fact("ジーン").canKnockback, .partial)
        XCTAssertEqual(try fact("リコ").basicAttackRicochet, .yes)
        XCTAssertEqual(try fact("ラフス").basicAttackRicochet, .yes)
        XCTAssertEqual(try fact("ベル").basicAttackRicochet, .partial)
        XCTAssertEqual(try fact("サージ").basicAttackRicochet, .partial)
    }

    func testNewAbilityQuestionsCoverEveryBrawler() {
        let ids = ["special.stun", "special.healPlayers", "special.slow", "special.knockback", "attack.ricochet", "movement.dashCharge", "special.allyShield", "special.allyDamageBoost", "special.allySpeedBoost", "super.heal", "super.summon", "super.selfMovement", "attack.damageOverTime", "attack.thrown", "super.damage", "attack.ammo.three"]
        for id in ids {
            let question = QuestionDatabase.all.first { $0.id == id }
            XCTAssertNotNil(question, id)
            XCTAssertEqual(question?.answers.count, BrawlerDatabase.brawlers.count, id)
        }
    }

    func testNewQuestionPolicyRegressions() throws {
        func fact(_ name: String) throws -> GameplayFact {
            let brawler = try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == name })
            return try XCTUnwrap(BrawlerDatabase.gameplayFactsByID[brawler.id])
        }

        XCTAssertEqual(try fact("バイロン").basicAttackDamageOverTime, .yes)
        XCTAssertEqual(try fact("クロウ").basicAttackDamageOverTime, .yes)
        XCTAssertEqual(try fact("Emz").basicAttackDamageOverTime, .no)
        XCTAssertEqual(try fact("パム").superCanSummon, .yes)
        // ハイパーチャージ中はウルトのダメージブースターがレーザーで攻撃するため装備限定。
        XCTAssertEqual(try fact("8ビット").superDealsDamage, .partial)
        XCTAssertEqual(try fact("ガス").canShieldOtherAllies, .yes)
        XCTAssertEqual(try fact("MAX").canBoostAllySpeed, .yes)
        XCTAssertEqual(try fact("ストゥー").canBoostAllySpeed, .partial)
        XCTAssertEqual(try fact("ナジア").basicAttackDamageOverTime, .yes)
        XCTAssertEqual(try fact("ダミアン").basicAttackDamageOverTime, .no)
        XCTAssertEqual(try fact("パール").basicAttackDamageOverTime, .partial)
        XCTAssertEqual(try fact("モーティス").superCanHeal, .yes)
        XCTAssertEqual(try fact("ポコ").canShieldOtherAllies, .partial)
        XCTAssertEqual(try fact("ウェンディ").superDealsDamage, .no)
        XCTAssertEqual(try fact("ピアス").superDealsDamage, .yes)
        XCTAssertEqual(try fact("アンバー").superDealsDamage, .no)
        XCTAssertEqual(try fact("アリー").superDealsDamage, .no)
        XCTAssertEqual(try fact("ジジ").superMovesSelf, .yes)
        XCTAssertEqual(try fact("シェイド").superMovesSelf, .no)
        XCTAssertEqual(try fact("アンジェロ").basicAttackDamageOverTime, .partial)
        XCTAssertEqual(try fact("ダグ").superCanHeal, .no)
        XCTAssertEqual(try fact("ローラ").superCanHeal, .no)
        XCTAssertEqual(try fact("スターノヴァ").superCanHeal, .no)
        XCTAssertEqual(try fact("コーデリアス").superMovesSelf, .no)
        XCTAssertEqual(try fact("ノリ").superMovesSelf, .yes)
        XCTAssertEqual(try fact("バズ").canDashOrCharge, .no)
        XCTAssertEqual(try fact("カール").canDashOrCharge, .no)

        let hpQuestions = QuestionDatabase.structured.filter { $0.id.hasPrefix("basic.hpAtLeast.") }
        XCTAssertEqual(hpQuestions.count, 5)
        let ammoQuestion = try XCTUnwrap(QuestionDatabase.structured.first { $0.id == "attack.ammo.three" })
        XCTAssertEqual(ammoQuestion.answers.count, BrawlerDatabase.brawlers.count)
    }

    func testTimeBasedSuperChargeTraitUsesTimeOnly() throws {
        let question = try XCTUnwrap(QuestionDatabase.structured.first { $0.id == "special.timeBasedSuperCharge" })
        let actual = Set(BrawlerDatabase.brawlers.filter { question.answers[$0.id] == .yes }.map(\.name))
        XCTAssertEqual(actual, Set(["ダリル", "エドガー", "キット", "ジェヨン", "シリウス"]))
        XCTAssertEqual(question.answers[try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == "チャック" }).id], .no)
        XCTAssertEqual(question.answers[try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == "MAX" }).id], .no)
        XCTAssertEqual(question.answers[try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == "ボルト" }).id], .no)
    }

    func testConfirmedHumanAppearanceClassification() throws {
        let question = try XCTUnwrap(QuestionDatabase.structured.first { $0.id == "appearance.human" })
        for name in ["タラ", "サンディ", "MAX", "アンバー", "グレイ", "カゼ", "ニタ", "スターノヴァ", "アリー"] {
            let brawler = try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == name })
            XCTAssertEqual(question.answers[brawler.id], .yes, name)
        }
        let pierce = try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == "ピアス" })
        XCTAssertEqual(question.answers[pierce.id], .no)
        XCTAssertEqual(question.answers.values.filter { $0 == .yes }.count, 56)
        XCTAssertEqual(question.answers.values.filter { $0 == .no }.count, 50)
        XCTAssertFalse(question.answers.values.contains(.partial))
    }

    func testConfirmedRobotAppearanceClassification() throws {
        let question = try XCTUnwrap(QuestionDatabase.structured.first { $0.id == "appearance.robot" })
        let expected: Set<String> = ["バーリー", "リコ", "ダリル", "カール", "ティック", "8ビット", "ナーニ", "パール", "ラリー＆ローリー", "R-T", "サージ", "スプラウト", "ストゥー", "ルー", "アッシュ", "ミープル"]
        let actual = Set(BrawlerDatabase.brawlers.filter { question.answers[$0.id] == .yes }.map(\.name))
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(question.answers.values.filter { $0 == .no }.count, BrawlerDatabase.brawlers.count - expected.count)
        XCTAssertFalse(question.answers.values.contains(.partial))
    }

    func testConfirmedAnimalAppearanceClassification() throws {
        let question = try XCTUnwrap(QuestionDatabase.structured.first { $0.id == "appearance.animal" })
        let expected: Set<String> = ["ラフス", "ミコ", "クランシー", "イヴ", "モー", "キット", "アリー", "ミスターP", "ベリー"]
        let actual = Set(BrawlerDatabase.brawlers.filter { question.answers[$0.id] == .yes }.map(\.name))
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(question.answers.values.filter { $0 == .no }.count, BrawlerDatabase.brawlers.count - expected.count)
        XCTAssertFalse(question.answers.values.contains(.partial))
    }

    func testConfirmedMonsterAppearanceClassification() throws {
        let question = try XCTUnwrap(QuestionDatabase.structured.first { $0.id == "appearance.monster" })
        let expected: Set<String> = ["ジーン", "フランケン", "モーティス", "ウィロー", "グローウィー"]
        let actual = Set(BrawlerDatabase.brawlers.filter { question.answers[$0.id] == .yes }.map(\.name))
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(question.answers.values.filter { $0 == .no }.count, BrawlerDatabase.brawlers.count - expected.count)
        XCTAssertFalse(question.answers.values.contains(.partial))
    }

    func testConfirmedFeminineAppearanceClassification() throws {
        let question = try XCTUnwrap(QuestionDatabase.structured.first { $0.id == "appearance.feminine" })
        let expected: Set<String> = ["ウェンディ", "スターノヴァ", "ナジア", "ミナ", "アリー", "カゼ", "ルミ", "ジュジュ", "メロディー", "チャーリー", "メイジー", "マンディ", "ボニー", "ジャネット", "ローラ", "メグ", "ベル", "アンバー", "コレット", "MAX", "ビー", "ビビ", "ローサ", "ジャッキー", "パム", "エリザベス", "ペニー", "ニタ", "ジェシー", "シェリー"]
        let actual = Set(BrawlerDatabase.brawlers.filter { question.answers[$0.id] == .yes }.map(\.name))
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(question.answers.values.filter { $0 == .no }.count, BrawlerDatabase.brawlers.count - expected.count)
        XCTAssertEqual(question.answers[try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == "ビー" }).id], .yes)
        XCTAssertEqual(question.answers[try XCTUnwrap(BrawlerDatabase.brawlers.first { $0.name == "タラ" }).id], .no)
        XCTAssertFalse(question.answers.values.contains(.partial))
    }

    func testConfirmedMasculineAppearanceClassification() throws {
        let question = try XCTUnwrap(QuestionDatabase.structured.first { $0.id == "appearance.masculine" })
        let expected: Set<String> = ["ノリ", "ダミアン", "ジギー", "ジェヨン", "オーリー", "ケンジ", "ドラコ", "グレイ", "チェスター", "バスター", "ガス", "サム", "ファング", "グロム", "エドガー", "バイロン", "ゲイル", "サンディ", "レオン", "ボウ", "エル・プリモ", "ダイナマイク", "ブロック", "ブル", "コルト"]
        let actual = Set(BrawlerDatabase.brawlers.filter { question.answers[$0.id] == .yes }.map(\.name))
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(question.answers.values.filter { $0 == .no }.count, BrawlerDatabase.brawlers.count - expected.count)
        XCTAssertFalse(question.answers.values.contains(.partial))

        let human = try XCTUnwrap(QuestionDatabase.structured.first { $0.id == "appearance.human" })
        let feminine = try XCTUnwrap(QuestionDatabase.structured.first { $0.id == "appearance.feminine" })
        for brawler in BrawlerDatabase.brawlers {
            if question.answers[brawler.id] == .yes || feminine.answers[brawler.id] == .yes {
                XCTAssertEqual(human.answers[brawler.id], .yes, brawler.name)
            }
        }
    }

    func testRemovedQuestionsStayRemoved() {
        XCTAssertFalse(QuestionDatabase.all.contains { $0.id == "stat.rarity.初期" })
        XCTAssertFalse(QuestionDatabase.all.contains { $0.id == "stat.thrower" })
        XCTAssertFalse(QuestionDatabase.all.contains { $0.id == "basic.nameNumber" })
        XCTAssertFalse(QuestionDatabase.all.contains { $0.id == "basic.nameSymbol" })
    }

    func testStructuredQuestionsAreUsefulAndNotExactDuplicates() {
        let brawlers = BrawlerDatabase.brawlers
        var signatures: [[TernaryAnswer]: String] = [:]

        for question in QuestionDatabase.structured {
            let signature = brawlers.map { question.answers[$0.id] ?? .no }
            XCTAssertGreaterThan(Set(signature).count, 1, "全キャラが同じ回答です: \(question.id)")
            if let duplicate = signatures[signature] {
                XCTFail("回答パターンが完全重複しています: \(duplicate) / \(question.id)")
            } else {
                signatures[signature] = question.id
            }
        }
    }

    func testGreedyQuestionStrategyCanIdentifyEveryBrawlerWithinEightQuestions() {
        let questions = QuestionDatabase.structured

        func unresolved(_ candidates: [Brawler], remaining: [Int], depth: Int) -> Set<String> {
            guard candidates.count > 1 else { return [] }
            guard depth < 8, !remaining.isEmpty else { return Set(candidates.map(\.name)) }

            let ranked = remaining.compactMap { index -> (Int, Int, Int)? in
                let groups = Dictionary(grouping: candidates) { questions[index].answers[$0.id] ?? .no }
                guard groups.count > 1 else { return nil }
                let largest = groups.values.map(\.count).max() ?? candidates.count
                let squared = groups.values.reduce(0) { $0 + $1.count * $1.count }
                return (index, largest, squared)
            }.sorted {
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                return $0.2 < $1.2
            }

            guard let selected = ranked.first?.0 else { return Set(candidates.map(\.name)) }
            let nextRemaining = remaining.filter { $0 != selected }
            let groups = Dictionary(grouping: candidates) { questions[selected].answers[$0.id] ?? .no }
            return groups.values.reduce(into: Set<String>()) { result, group in
                result.formUnion(unresolved(group, remaining: nextRemaining, depth: depth + 1))
            }
        }

        let failures = unresolved(BrawlerDatabase.brawlers, remaining: Array(questions.indices), depth: 0)
        XCTAssertTrue(failures.isEmpty, "8問の貪欲戦略で特定できないキャラ: \(failures.sorted().joined(separator: "、"))")
    }
}
