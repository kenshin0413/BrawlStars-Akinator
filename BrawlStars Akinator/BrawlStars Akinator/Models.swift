import Foundation

enum TernaryAnswer: String, Codable, CaseIterable, Identifiable, Hashable {
    case yes = "はい"
    case no = "いいえ"
    case partial = "部分的にそう"

    var id: String { rawValue }
    var symbol: String {
        switch self { case .yes: "checkmark"; case .no: "xmark"; case .partial: "circle.lefthalf.filled" }
    }
}

struct AbilityInfo: Codable, Hashable {
    let name: String
    let description: String
}

struct DataSource: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let url: URL
    let kind: String
    let checkedAt: String
}

struct Brawler: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let description: String
    let rarity: String
    let className: String
    let classKey: String
    let movementSpeed: Int
    let attackRange: Int
    let reloadTimeMs: Int
    let battleStartHitpoints: Int
    let ammoCount: Int
    let hasTimeBasedSuperCharge: Bool
    let isThrower: Bool
    let movementLabels: [String]
    let rangeLabels: [String]
    let reloadLabels: [String]
    let statLabelSourceID: String
    let imageURL: URL?
    let gadgets: [AbilityInfo]
    let starPowers: [AbilityInfo]
    let sourceIDs: [String]
}

struct BrawlerDatabaseFile: Codable {
    let schemaVersion: Int
    let verifiedAt: String
    let sources: [DataSource]
    let brawlers: [Brawler]
}

struct GameplayFact: Codable, Hashable, Identifiable {
    let id: Int
    let singleAttack: TernaryAnswer
    let multipleAttack: TernaryAnswer
    let piercingAttack: TernaryAnswer
    let wallBreaking: TernaryAnswer
    let jumping: TernaryAnswer
    let waterMovement: TernaryAnswer
    let attackingPet: TernaryAnswer
    let canStun: TernaryAnswer
    let canHealPlayers: TernaryAnswer
    let canSlow: TernaryAnswer
    let canKnockback: TernaryAnswer
    let basicAttackRicochet: TernaryAnswer
    let canDashOrCharge: TernaryAnswer
    let canShieldOtherAllies: TernaryAnswer
    let canBoostAllyDamage: TernaryAnswer
    let canBoostAllySpeed: TernaryAnswer
    let superCanHeal: TernaryAnswer
    let superCanSummon: TernaryAnswer
    let superMovesSelf: TernaryAnswer
    let basicAttackDamageOverTime: TernaryAnswer
    let superDealsDamage: TernaryAnswer
    let humanAppearance: TernaryAnswer
    let sourceIDs: [String]
    let evidence: [String: String]
}

struct GameplayFactsFile: Codable {
    let schemaVersion: Int
    let checkedAt: String
    let policyVersion: Int
    let sourceIDs: [String]
    let facts: [GameplayFact]
}

enum QuestionCategory: String, CaseIterable, Identifiable {
    case popular = "よく使う"
    case basic = "基本情報"
    case attack = "攻撃"
    case superAbility = "ウルト"
    case movement = "移動・射程"
    case special = "特殊能力"
    case appearance = "見た目"
    case unique = "固有能力"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .popular: "sparkles"
        case .basic: "info.circle"
        case .attack: "scope"
        case .superAbility: "bolt.fill"
        case .movement: "figure.run"
        case .special: "wand.and.stars"
        case .appearance: "eye.fill"
        case .unique: "fingerprint"
        }
    }
}

struct GameQuestion: Identifiable, Hashable {
    let id: String
    let text: String
    let category: QuestionCategory
    let detail: String
    let popular: Bool
    let answers: [Int: TernaryAnswer]

    func answer(for brawler: Brawler) -> TernaryAnswer? { answers[brawler.id] }
}

struct AskedQuestion: Identifiable, Hashable {
    let id = UUID()
    let question: GameQuestion
    let answer: TernaryAnswer
}

struct WrongAnswerReport: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let brawlerID: Int
    let brawlerName: String
    let questionID: String
    let question: String
    let shownAnswer: String
    let note: String
}
