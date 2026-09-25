import Foundation

enum BrawlerDatabase {
    static let file: BrawlerDatabaseFile = {
        guard let url = Bundle.main.url(forResource: "Brawlers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(BrawlerDatabaseFile.self, from: data) else {
            preconditionFailure("Brawlers.json could not be decoded")
        }
        return decoded
    }()

    static var brawlers: [Brawler] { file.brawlers.sorted { $0.name < $1.name } }
    static var sources: [DataSource] { file.sources }
    static var verifiedAt: String { file.verifiedAt }

    static let gameplayFactsFile: GameplayFactsFile = {
        guard let url = Bundle.main.url(forResource: "GameplayFacts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(GameplayFactsFile.self, from: data) else {
            preconditionFailure("GameplayFacts.json could not be decoded")
        }
        return decoded
    }()

    static let gameplayFactsByID: [Int: GameplayFact] =
        Dictionary(uniqueKeysWithValues: gameplayFactsFile.facts.map { ($0.id, $0) })
}

enum QuestionDatabase {
    private static func displayText(_ sourceText: String) -> String {
        sourceText.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    private static func answers(where predicate: (Brawler) -> Bool) -> [Int: TernaryAnswer] {
        Dictionary(uniqueKeysWithValues: BrawlerDatabase.brawlers.map { ($0.id, predicate($0) ? .yes : .no) })
    }

    private static func generated(_ id: String, _ text: String, _ category: QuestionCategory, _ detail: String, popular: Bool = false, where predicate: (Brawler) -> Bool) -> GameQuestion {
        GameQuestion(id: id, text: text, category: category, detail: detail, popular: popular, answers: answers(where: predicate))
    }

    private static func factQuestion(_ id: String, _ text: String, _ category: QuestionCategory, _ detail: String, popular: Bool = false, answer: (GameplayFact) -> TernaryAnswer) -> GameQuestion {
        let matrix = Dictionary(uniqueKeysWithValues: BrawlerDatabase.brawlers.map { brawler in
            guard let fact = BrawlerDatabase.gameplayFactsByID[brawler.id] else {
                preconditionFailure("\(brawler.name)のゲームプレイ分類がありません")
            }
            return (brawler.id, answer(fact))
        })
        return GameQuestion(id: id, text: text, category: category, detail: detail, popular: popular, answers: matrix)
    }

    private static func generatedLabel(_ id: String, _ text: String, _ category: QuestionCategory, _ detail: String, popular: Bool = false, labels: (Brawler) -> [String], matches label: String) -> GameQuestion {
        let matrix = Dictionary(uniqueKeysWithValues: BrawlerDatabase.brawlers.map { brawler in
            let values = labels(brawler)
            let answer: TernaryAnswer = values.contains(label) ? (values.count == 1 ? .yes : .partial) : .no
            return (brawler.id, answer)
        })
        return GameQuestion(id: id, text: text, category: category, detail: detail, popular: popular, answers: matrix)
    }

    static let structured: [GameQuestion] = {
        let rarityOrder = ["レア", "スーパーレア", "ハイパーレア", "ウルトラレア", "レジェンドレア", "ウルトラレジェンドレア"]
        let rarities = rarityOrder.filter { rarity in BrawlerDatabase.brawlers.contains { $0.rarity == rarity } }
        let classOrder: [(String, String)] = [("tank","タンク"), ("assassin","アサシン"), ("support","サポート"), ("controller","コントローラー"), ("damage_dealer","アタッカー"), ("marksman","スナイパー"), ("artillery","グレネーディア")]
        let rarityQuestions = rarities.map { rarity in
            generated("stat.rarity.\(rarity)", "レア度は\(rarity)？", .basic, "ゲーム内の現行レア度で判定します。", popular: rarity == "ウルトラレア" || rarity == "レジェンドレア") { $0.rarity == rarity }
        }
        let classQuestions = classOrder.map { key, label in
            generated("stat.class.\(key)", "キャラタイプは\(label)？", .basic, "ゲーム内のキャラ詳細に表示されるキャラタイプで判定します。", popular: true) { $0.classKey == key }
        }
        let speedQuestions = ["超低速", "低速", "普通", "高速", "超高速"].map { band in
            generatedLabel("stat.speed.\(band)", "移動速度は\(band)？", .movement, "バトル開始直後の基本状態における移動速度区分です。怒り、ウルト、変身、搭乗解除など、戦闘中の速度変化は含めません。", popular: band == "普通" || band == "高速", labels: { $0.movementLabels }, matches: band)
        }
        let rangeBands = ["超短距離", "短距離", "普通", "中距離", "長距離", "超長距離"].filter { band in
            BrawlerDatabase.brawlers.contains { $0.rangeLabels.contains(band) }
        }
        let rangeQuestions = rangeBands.map { band in
            generatedLabel("stat.range.\(band)", "通常攻撃の射程は\(band)？", .attack, "日本語Webのキャラ詳細に記載された通常攻撃の射程区分です。", popular: true, labels: { $0.rangeLabels }, matches: band)
        }
        let reloadQuestions = ["超高速", "高速", "普通", "低速", "超低速", "溜めて攻撃"].map { band in
            generatedLabel("stat.reload.\(band)", "リロード速度は\(band)？", .attack, "日本語Webのキャラ詳細に記載された通常攻撃のリロード表示です。", popular: band == "普通" || band == "高速", labels: { $0.reloadLabels }, matches: band)
        }
        let nameLengths = Set(BrawlerDatabase.brawlers.map { $0.name.count }).sorted()
        let nameQuestions = nameLengths.map { length in
            generated("basic.nameLength.\(length)", "正式名称は\(length)文字？", .basic, "ゲーム内の日本語正式名称を、記号を含む表示どおりの文字数で数えます。", popular: length >= 3 && length <= 6) { $0.name.count == length }
        }
        let latinName = generated("basic.nameLatin", "正式名称に英字が入る？", .basic, "日本語正式名称にA〜Zの英字が1文字以上含まれる場合に成立します。") {
            $0.name.range(of: "[A-Za-z]", options: .regularExpression) != nil
        }
        let water = factQuestion("special.water", "水上を移動できる？", .movement, "通常ルールで水上を移動できる特性を持つ場合は「はい」。状態などの条件付きのみ可能なら「部分的にそう」。ジャンプやダッシュで越えるだけの場合と期間限定イベント能力は含みません。", popular: true, answer: { $0.waterMovement })
        let single = factQuestion("attack.single", "通常攻撃は単発攻撃？", .attack, "バトル開始時の通常攻撃で、弾薬1回につき攻撃を1発だけ放つ場合。継続ダメージ、往復、着弾後の分裂は回数に含めず、アンバー型の特殊弾薬は対象外です。", popular: true, answer: { $0.singleAttack })
        let multiple = factQuestion("attack.multiple", "通常攻撃は複数攻撃？", .attack, "バトル開始時の通常攻撃で、弾薬1回につき複数の弾・打撃を最初から放つ場合。継続ダメージ、往復、着弾後の分裂は含めません。", popular: true, answer: { $0.multipleAttack })
        let piercing = factQuestion("attack.piercing", "通常攻撃は敵を貫通する？", .attack, "通常攻撃が敵を通過し、1回で複数の敵に当たり得る場合。壁貫通、爆発、跳弾、連鎖、分裂は含めません。ガジェット・スターパワー・ハイパーチャージ・バフィーで通常攻撃が貫通する場合のみ「部分的にそう」。", popular: true, answer: { $0.piercingAttack })
        let wall = factQuestion("special.wallBreaking", "壁を壊せる？", .attack, "通常攻撃・ウルト・恒常装備を含む全能力で、通常の破壊可能な壁を実際に除去できるかを判定。装備時だけなら「部分的にそう」。", popular: true, answer: { $0.wallBreaking })
        let jump = factQuestion("special.jumping", "ジャンプできる？", .movement, "自身が物理的に跳び上がる能力で判定。飛行・ワープ・ダッシュ・突進は含めず、装備時だけなら「部分的にそう」。", popular: true, answer: { $0.jumping })
        let pet = factQuestion("special.attackingPet", "攻撃するペット系を出せる？", .attack, "攻撃できるペット・タレット・クローン・シャドーのみ対象。設置物、罠、壁、サンドバッグ、非攻撃タレット、ナーニのピープは含めません。この質問は「はい」「いいえ」のみです。", popular: true, answer: { $0.attackingPet })
        let stun = factQuestion("special.stun", "敵をスタンできる？", .attack, "通常攻撃・ウルト・ガジェット・スターパワー・ハイパーチャージ・バフィーの説明に「スタン」または「気絶」と明記された能力で判定します。凍結・睡眠・移動不能などは含めません。装備などが必要な場合は「部分的にそう」です。", popular: true, answer: { $0.canStun })
        let healing = factQuestion("special.healPlayers", "味方を回復できる？", .attack, "自分自身または味方プレイヤーのHPを直接増やせる全能力で判定します。タラの回復する影など、召喚物によるプレイヤー回復も含みます。タレットやペットだけの回復、自然回復の開始短縮は含めません。", popular: true, answer: { $0.canHealPlayers })
        let slowing = factQuestion("special.slow", "敵をスローダウンにできる？", .attack, "通常攻撃・ウルト・ガジェット・スターパワー・ハイパーチャージ・バフィーを含む全能力が対象です。装備や特定能力だけで可能な場合は「部分的にそう」です。", popular: true, answer: { $0.canSlow })
        let knockback = factQuestion("special.knockback", "敵をノックバックできる？", .attack, "全能力を対象に、敵をノックバック・押し戻す・吹き飛ばす効果で判定します。引き寄せ、投げ飛ばし、恐怖、空中への打ち上げは含めません。", popular: true, answer: { $0.canKnockback })
        let ricochet = factQuestion("attack.ricochet", "通常攻撃が壁で跳弾する？", .attack, "リコのように通常攻撃が壁で跳ね返る場合に成立します。敵同士の連鎖、ウルトだけの反射は含めません。装備やバフィーで通常攻撃が跳弾する場合は「部分的にそう」です。", popular: true, answer: { $0.basicAttackRicochet })
        let dash = factQuestion("movement.dashCharge", "ダッシュまたは突進できる？", .movement, "ゲーム上のダッシュ・突進・チャージ系の前方移動が対象です。標準能力なら「はい」、装備時だけなら「部分的にそう」。ジャンプ、飛行、ワープ、自分を対象へ引き寄せる移動は含めません。", popular: true, answer: { $0.canDashOrCharge })
        let allyShield = factQuestion("special.allyShield", "自分以外の味方にシールドを付与できる？", .special, "味方プレイヤー本人に被ダメージを軽減するシールドを付与できるかで判定します。自分だけ、ペットやタレットだけ、物体を盾にする効果は含めません。", answer: { $0.canShieldOtherAllies })
        let allyDamage = factQuestion("special.allyDamageBoost", "味方の攻撃力を上げられる？", .special, "自分以外の味方が与えるダメージを増加できる全能力が対象です。装備時だけなら「部分的にそう」です。", answer: { $0.canBoostAllyDamage })
        let allySpeed = factQuestion("special.allySpeedBoost", "味方の移動速度を上げられる？", .special, "自分以外の味方プレイヤーの移動速度を上昇できる全能力が対象です。装備時だけなら「部分的にそう」です。", answer: { $0.canBoostAllySpeed })
        let superHeal = factQuestion("super.heal", "ウルトで回復できる？", .superAbility, "ウルト本体、ウルトで出した召喚物・設置物によって、自分または味方プレイヤーのHPを回復できる場合に成立します。装備時だけなら「部分的にそう」です。", popular: true, answer: { $0.superCanHeal })
        let superSummon = factQuestion("super.summon", "ウルトで召喚物を出す？", .superAbility, "ウルトでキャラクター、ペット、クローン、タレットなど独立したHPを持つ対象を出す場合に成立します。パムの回復タレットなど、攻撃しない召喚物も含めます。地雷・投射物・壁・ワープ地点・信号機は含めません。", popular: true, answer: { $0.superCanSummon })
        let superMovement = factQuestion("super.selfMovement", "ウルトで自身が移動する？", .superAbility, "ウルトによって本人の位置が変わるなら、ダッシュ・突進・ジャンプ・飛行・ワープ・潜行など方式を問わず成立します。", popular: true, answer: { $0.superMovesSelf })
        let damageOverTime = factQuestion("attack.damageOverTime", "通常攻撃で継続ダメージを与えられる？", .attack, "バイロンやクロウの毒のように、命中後も時間を置いてダメージが発生する通常攻撃が対象です。エムズのように攻撃判定内で複数回ヒットする攻撃は含めません。", popular: true, answer: { $0.basicAttackDamageOverTime })
        let thrown = generated("attack.thrown", "通常攻撃は投げ攻撃？", .attack, "ゲームデータ上、通常攻撃を壁越しに投げるキャラとして分類されているかで判定します。", popular: true) { $0.isThrower }
        let superDamage = factQuestion("super.damage", "ウルトは敵にダメージを与える？", .superAbility, "ウルトを発動した結果として発生するダメージが対象です。ウルトで出したタレットやペットなどの攻撃も含めますが、アンバーの点火のように別途通常攻撃が必要なものは含めません。装備時だけなら「部分的にそう」です。", popular: true, answer: { $0.superDealsDamage })
        let threeAmmo = generated("attack.ammo.three", "通常攻撃の弾薬数は3つ？", .attack, "バトル開始直後の基本状態で表示される最大弾薬数で判定します。", popular: true) { $0.ammoCount == 3 }
        let timeBasedSuperCharge = generated("special.timeBasedSuperCharge", "時間とともにウルトが貯まる特性を持ってる？", .special, "攻撃・移動・被ダメージ・周囲の敵味方などを条件とせず、時間経過だけでウルトが自動チャージされる固有特性が対象です。リワーク後のチャックは含めません。", popular: true) { $0.hasTimeBasedSuperCharge }
        let human = factQuestion("appearance.human", "見た目は人間っぽい？", .appearance, "通常スキンの外見を基準にしたユーザー確定分類です。実際の種族ではなく、画面上で人間らしく見えるかを判定します。", popular: true, answer: { $0.humanAppearance })
        let confirmedRobots: Set<String> = ["バーリー", "リコ", "ダリル", "カール", "ティック", "8ビット", "ナーニ", "パール", "ラリー＆ローリー", "R-T", "サージ", "スプラウト", "ストゥー", "ルー", "アッシュ", "ミープル"]
        let robot = generated("appearance.robot", "見た目はロボットっぽい？", .appearance, "通常スキンの外見を基準にしたユーザー確定分類です。実際の種族や公式説明での明記ではなく、画面上でロボットらしく見えるかを判定します。", popular: true) { confirmedRobots.contains($0.name) }
        let confirmedAnimals: Set<String> = ["ラフス", "ミコ", "クランシー", "イヴ", "モー", "キット", "アリー", "ミスターP", "ベリー"]
        let animal = generated("appearance.animal", "見た目は動物っぽい？", .appearance, "通常スキンの外見を基準にしたユーザー確定分類です。確定した9体だけを「はい」とし、それ以外は「いいえ」と判定します。", popular: true) { confirmedAnimals.contains($0.name) }
        let confirmedMonsters: Set<String> = ["ジーン", "フランケン", "モーティス", "ウィロー", "グローウィー"]
        let monster = generated("appearance.monster", "見た目は怪人っぽい？", .appearance, "通常スキンの外見を基準にしたユーザー確定分類です。確定した5体だけを「はい」とし、それ以外は「いいえ」と判定します。", popular: true) { confirmedMonsters.contains($0.name) }
        let confirmedFeminine: Set<String> = ["ウェンディ", "スターノヴァ", "ナジア", "ミナ", "アリー", "カゼ", "ルミ", "ジュジュ", "メロディー", "チャーリー", "メイジー", "マンディ", "ボニー", "ジャネット", "ローラ", "メグ", "ベル", "アンバー", "コレット", "MAX", "ビー", "ビビ", "ローサ", "ジャッキー", "パム", "エリザベス", "ペニー", "ニタ", "ジェシー", "シェリー"]
        let feminine = generated("appearance.feminine", "見た目は女性っぽい？", .appearance, "「見た目は人間っぽい？」が「はい」のキャラだけを対象にしたユーザー確定分類です。確定した30体を「はい」とし、タラは男女どちらにも含めません。", popular: true) { confirmedFeminine.contains($0.name) }
        let confirmedMasculine: Set<String> = ["ノリ", "ダミアン", "ジギー", "ジェヨン", "オーリー", "ケンジ", "ドラコ", "グレイ", "チェスター", "バスター", "ガス", "サム", "ファング", "グロム", "エドガー", "バイロン", "ゲイル", "サンディ", "レオン", "ボウ", "エル・プリモ", "ダイナマイク", "ブロック", "ブル", "コルト"]
        let masculine = generated("appearance.masculine", "見た目は男性っぽい？", .appearance, "「見た目は人間っぽい？」が「はい」のキャラだけを対象にしたユーザー確定分類です。確定した25体を「はい」とし、タラは男女どちらにも含めません。", popular: true) { confirmedMasculine.contains($0.name) }
        let hpQuestions = stride(from: 6_000, through: 10_000, by: 1_000).map { hp in
            generated("basic.hpAtLeast.\(hp)", "HPは\(hp)以上？", .basic, "パワー11・バトル開始直後の基本状態における最大HPで判定します。シールドや戦闘中の形態変化は含めません。", popular: hp == 8_000) { $0.battleStartHitpoints >= hp }
        }
        return rarityQuestions + classQuestions + speedQuestions + rangeQuestions + reloadQuestions + hpQuestions + nameQuestions + [latinName, water, single, multiple, piercing, ricochet, damageOverTime, thrown, threeAmmo, superDamage, superHeal, superSummon, superMovement, wall, jump, dash, pet, stun, healing, slowing, knockback, allyShield, allyDamage, allySpeed, timeBasedSuperCharge, human, robot, animal, monster, feminine, masculine]
    }()

    static let unique: [GameQuestion] = BrawlerDatabase.brawlers.flatMap { brawler in
        let fallback = AbilityInfo(
            name: "キャラクター紹介",
            description: brawler.description.isEmpty ? "\(brawler.name)の公式名称に関する質問です。" : brawler.description
        )
        let abilities = [brawler.gadgets.first ?? brawler.starPowers.first ?? fallback]
        return abilities.enumerated().map { index, ability in
            GameQuestion(
                id: "unique.\(brawler.id).\(index)",
                text: ability.name == "キャラクター紹介"
                    ? "公式紹介文が「\(String(ability.description.prefix(32)))…」で始まる？"
                    : "「\(ability.name)」という能力を持つ？",
                category: .unique,
                detail: ability.description.isEmpty ? "\(brawler.name)固有の能力名です。" : displayText(ability.description),
                popular: false,
                answers: Dictionary(uniqueKeysWithValues: BrawlerDatabase.brawlers.map { ($0.id, $0.id == brawler.id ? .yes : .no) })
            )
        }
    }

    // Curated questions stay excluded until every per-brawler answer has an
    // attributable source. Gameplay only exposes source-backed data.
    static let all = structured + unique

    static func validationIssues() -> [String] {
        var issues: [String] = []
        let ids = Set(BrawlerDatabase.brawlers.map(\.id))
        let sourceIDs = Set(BrawlerDatabase.sources.map(\.id))
        let validRarities = Set(["レア", "スーパーレア", "ハイパーレア", "ウルトラレア", "レジェンドレア", "ウルトラレジェンドレア"])
        let validClasses = Set(["tank", "assassin", "support", "controller", "damage_dealer", "marksman", "artillery"])
        let validMovement = Set(["超低速", "低速", "普通", "高速", "超高速"])
        let validRange = Set(["超短距離", "短距離", "普通", "中距離", "長距離", "超長距離"])
        let validReload = Set(["超高速", "高速", "普通", "低速", "超低速", "溜めて攻撃"])
        if BrawlerDatabase.file.schemaVersion < 6 { issues.append("DBスキーマが古いバージョンです") }
        if ids.count != BrawlerDatabase.brawlers.count { issues.append("キャラIDが重複しています") }
        for question in all {
            if Set(question.answers.keys) != ids { issues.append("\(question.id): 全キャラの回答がありません") }
            if Set(question.answers.keys).count != question.answers.count { issues.append("\(question.id): 回答が重複しています") }
        }
        for brawler in BrawlerDatabase.brawlers {
            if !validRarities.contains(brawler.rarity) { issues.append("\(brawler.name): 未知のレア度 \(brawler.rarity)") }
            if !validClasses.contains(brawler.classKey) { issues.append("\(brawler.name): 未知のキャラタイプ \(brawler.classKey)") }
            if !Set(brawler.movementLabels).isSubset(of: validMovement) { issues.append("\(brawler.name): 未知の移動速度区分") }
            if brawler.movementLabels.count != 1 { issues.append("\(brawler.name): バトル開始時の移動速度区分が1つではありません") }
            if !Set(brawler.rangeLabels).isSubset(of: validRange) { issues.append("\(brawler.name): 未知の射程区分") }
            if !Set(brawler.reloadLabels).isSubset(of: validReload) { issues.append("\(brawler.name): 未知のリロード区分") }
            if brawler.classKey == "artillery" && !brawler.isThrower { issues.append("\(brawler.name): グレネーディアなのに投げキャラ判定がありません") }
            if brawler.battleStartHitpoints <= 0 { issues.append("\(brawler.name): バトル開始時HPが不正です") }
            if brawler.ammoCount <= 0 { issues.append("\(brawler.name): 通常攻撃の弾薬数が不正です") }
            let references = Set(brawler.sourceIDs + [brawler.statLabelSourceID])
            if !references.isSubset(of: sourceIDs) { issues.append("\(brawler.name): 未登録の情報源IDがあります") }
            let uniqueCount = unique.filter { $0.answers[brawler.id] == .yes }.count
            if uniqueCount != 1 { issues.append("\(brawler.name): 固有質問が\(uniqueCount)件あります") }
        }
        let factIDs = Set(BrawlerDatabase.gameplayFactsFile.facts.map(\.id))
        if factIDs != ids { issues.append("ゲームプレイ構造化データが全キャラ分揃っていません") }
        if BrawlerDatabase.gameplayFactsFile.schemaVersion < 5 { issues.append("ゲームプレイ分類スキーマが古いバージョンです") }
        if BrawlerDatabase.gameplayFactsFile.policyVersion != 4 { issues.append("ゲームプレイ分類基準が不正です") }
        if !Set(BrawlerDatabase.gameplayFactsFile.sourceIDs).isSubset(of: sourceIDs) { issues.append("ゲームプレイ分類に未登録の情報源があります") }
        for fact in BrawlerDatabase.gameplayFactsFile.facts {
            if fact.attackingPet == .partial { issues.append("\(fact.id): ペット系に部分判定は使用できません") }
            if fact.singleAttack == .yes && fact.multipleAttack == .yes { issues.append("\(fact.id): 単発と複数が同時に『はい』です") }
            if fact.sourceIDs.isEmpty || !Set(fact.sourceIDs).isSubset(of: sourceIDs) { issues.append("\(fact.id): 分類の情報源が不正です") }
            let requiredEvidence = Set(["singleAttack", "multipleAttack", "piercingAttack", "wallBreaking", "jumping", "waterMovement", "attackingPet", "canStun", "canHealPlayers", "canSlow", "canKnockback", "basicAttackRicochet", "canDashOrCharge", "canShieldOtherAllies", "canBoostAllyDamage", "canBoostAllySpeed", "superCanHeal", "superCanSummon", "superMovesSelf", "basicAttackDamageOverTime", "superDealsDamage", "humanAppearance"])
            if Set(fact.evidence.keys) != requiredEvidence { issues.append("\(fact.id): 22分類の根拠が揃っていません") }
        }
        return issues
    }
}
