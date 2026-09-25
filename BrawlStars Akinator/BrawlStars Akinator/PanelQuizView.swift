import SwiftUI

struct PanelQuizView: View {
    @Bindable var quiz: PanelQuizViewModel
    let game: GameViewModel
    let ads: InterstitialAdManager
    let audio: OracleAudioManager

    var body: some View {
        ZStack {
            PanelBackground()
            switch quiz.phase {
            case .playing: PanelPlayView(quiz: quiz)
            case .choosing: PanelAnswerPicker(quiz: quiz)
            case .correctFeedback: PanelCorrectFeedbackView(quiz: quiz)
            case .finished: PanelResultView(quiz: quiz, game: game, ads: ads, audio: audio)
            case .idle: EmptyView()
            }

            if (quiz.phase == .playing || quiz.phase == .choosing),
               quiz.remainingSeconds <= 10 {
                CountdownUrgencyOverlay(seconds: quiz.remainingSeconds)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: quiz.remainingSeconds) { _, seconds in
            if seconds <= 10 { audio.playCountdownTick(secondsRemaining: seconds) }
        }
    }
}

private struct PanelPlayView: View {
    @Bindable var quiz: PanelQuizViewModel

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 700
            VStack(spacing: compact ? 8 : 13) {
                header(compact: compact)
                if quiz.rarityRevealed, let current = quiz.current {
                    Label(current.rarity, systemImage: "sparkles")
                        .font(.caption.bold()).foregroundStyle(PanelColors.cream)
                        .padding(.horizontal, 13).frame(height: 28)
                        .background(PanelColors.violet.opacity(0.78), in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Label(
                        quiz.selectingExtraPanel
                            ? "開けたいパネルを選んでください"
                            : (quiz.remainingSeconds <= 10 ? "急いで！残り\(quiz.remainingSeconds)秒" : "隠れているキャラは誰？"),
                        systemImage: quiz.selectingExtraPanel
                            ? "hand.tap.fill"
                            : (quiz.remainingSeconds <= 10 ? "timer" : "eye.slash.fill")
                    )
                    .font(.subheadline.bold())
                    .foregroundStyle(quiz.remainingSeconds <= 10 ? PanelColors.coral : .white.opacity(0.9))
                    .padding(.horizontal, 15).frame(height: 31)
                    .background(.white.opacity(0.09), in: Capsule())
                }
                PanelPortrait(quiz: quiz, compact: compact)
                HStack(spacing: compact ? 6 : 9) {
                    HintButton(title: "パス", icon: "forward.end.fill", available: quiz.passAvailable && quiz.roundInteractive, action: quiz.usePass)
                    HintButton(title: quiz.selectingExtraPanel ? "選択中" : "1枚開ける", icon: "square.grid.3x3", available: quiz.extraPanelAvailable && quiz.roundInteractive, highlighted: quiz.selectingExtraPanel, action: quiz.requestExtraPanel)
                    HintButton(title: quiz.rarityRevealed ? "表示中" : "レア度", icon: "diamond.fill", available: quiz.rarityHintAvailable && quiz.roundInteractive, action: quiz.revealRarity)
                }
                Button(action: quiz.beginChoosing) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill.questionmark")
                        Text("キャラを回答")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline.bold()).opacity(0.82)
                    }
                    .font(.headline.bold()).padding(.horizontal, 22)
                    .frame(maxWidth: .infinity).frame(height: compact ? 50 : 56)
                }
                .buttonStyle(PanelAnswerButtonStyle())
                .disabled(!quiz.roundInteractive)
                VStack(spacing: 2) {
                    Text("回答は1回だけ。間違えるとチャレンジ終了")
                    Text("キャラ回答も時間内に含まれます")
                }
                .font(.caption2.bold()).foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, 17).padding(.vertical, compact ? 8 : 14)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("16パネルクイズ").font(.headline.bold()).foregroundStyle(.white)
                Text("問題 \(quiz.progressText)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.68))
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(.white.opacity(0.1), in: Capsule())
            }
            Spacer()
            Label("\(quiz.correctCount)連勝", systemImage: "flame.fill")
                .font(.caption.bold()).foregroundStyle(PanelColors.cream)
                .padding(.horizontal, 10).frame(height: 30)
                .background(.white.opacity(0.09), in: Capsule())
            ZStack {
                Circle().stroke(.white.opacity(0.16), lineWidth: 5)
                Circle().trim(from: 0, to: CGFloat(quiz.remainingSeconds) / 90)
                    .stroke(quiz.remainingSeconds <= 15 ? PanelColors.coral : PanelColors.aqua, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(quiz.remainingSeconds)").font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(.white)
            }
            .frame(width: compact ? 43 : 48, height: compact ? 43 : 48)
            .scaleEffect(
                quiz.remainingSeconds <= 10
                    ? (quiz.remainingSeconds.isMultiple(of: 2) ? 1.03 : 1.13)
                    : 1
            )
            .shadow(
                color: quiz.remainingSeconds <= 10 ? PanelColors.coral.opacity(0.75) : .clear,
                radius: quiz.remainingSeconds <= 10 ? 10 : 0
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: quiz.remainingSeconds)
        }
        .padding(.horizontal, 14).frame(height: compact ? 58 : 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 1) }
        .shadow(color: PanelColors.indigo.opacity(0.2), radius: 12, y: 5)
    }
}

private struct CountdownUrgencyOverlay: View {
    let seconds: Int

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 30)
                .stroke(PanelColors.coral.opacity(seconds.isMultiple(of: 2) ? 0.28 : 0.68), lineWidth: 5)
                .shadow(color: PanelColors.coral.opacity(0.46), radius: 13)
                .padding(4)
                .animation(.easeInOut(duration: 0.18), value: seconds)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct PanelPortrait: View {
    @Bindable var quiz: PanelQuizViewModel
    let compact: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28).fill(PanelColors.cream.opacity(0.96))
            if let current = quiz.current {
                AsyncImage(url: current.imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill().onAppear { quiz.imageDidLoad() }
                    case .failure:
                        VStack(spacing: 8) { Image(systemName: "wifi.exclamationmark"); Text("画像を読み込めません") }.foregroundStyle(PanelColors.ink)
                    default: ProgressView().tint(PanelColors.violet)
                    }
                }
                .id(current.id)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            GeometryReader { proxy in
                let gap: CGFloat = 0
                let width = (proxy.size.width - gap * 3) / 4
                let height = (proxy.size.height - gap * 3) / 4
                ForEach(0..<16, id: \.self) { index in
                    let row = index / 4, column = index % 4
                    if !quiz.openPanels.contains(index) {
                        let canOpenWithHint = quiz.canOpenExtraPanel(index)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                quiz.openExtraPanel(index)
                            }
                        } label: {
                            PanelCoverTile(
                                index: index,
                                selecting: quiz.selectingExtraPanel,
                                blocked: quiz.selectingExtraPanel && !canOpenWithHint
                            )
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(quiz.selectingExtraPanel && canOpenWithHint)
                        .frame(width: width, height: height)
                        .position(x: CGFloat(column) * (width + gap) + width / 2, y: CGFloat(row) * (height + gap) + height / 2)
                    }
                }
            }
            if !quiz.roundInteractive {
                ZStack {
                    LinearGradient(
                        colors: [PanelColors.violet, PanelColors.indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("次の問題を準備中")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxHeight: compact ? 345 : 430)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).stroke(PanelColors.cream.opacity(0.72), lineWidth: 2) }
        .shadow(color: PanelColors.violet.opacity(0.42), radius: 18, y: 8)
        .transaction { $0.animation = nil }
    }
}

private struct PanelCoverTile: View {
    let index: Int
    let selecting: Bool
    let blocked: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [PanelColors.violet, PanelColors.indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Rectangle().stroke(.white.opacity(selecting ? 0.72 : 0.2), lineWidth: selecting ? 2 : 1)

            VStack(spacing: 5) {
                Image(systemName: blocked ? "lock.fill" : (selecting ? "plus" : "sparkle"))
                    .font(.system(size: selecting ? 19 : 10, weight: .bold))
                if selecting && !blocked {
                    Text("\(index + 1)").font(.caption2.bold())
                }
            }
            .foregroundStyle(.white.opacity(blocked ? 0.32 : (selecting ? 0.9 : 0.24)))
        }
    }
}

private struct HintButton: View {
    let title: String, icon: String
    let available: Bool
    var highlighted = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(.white.opacity(available ? 0.14 : 0.07))
                    Image(systemName: available ? icon : "checkmark")
                }
                .frame(width: 29, height: 29)
                Text(available ? title : "使用済み").font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(available ? .white : .white.opacity(0.38))
            .frame(maxWidth: .infinity).frame(height: 64)
            .background(highlighted ? PanelColors.aqua.opacity(0.42) : .white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(highlighted ? 0.68 : 0.2), lineWidth: 1) }
        }.buttonStyle(.plain).disabled(!available)
    }
}

private struct PanelAnswerPicker: View {
    @Bindable var quiz: PanelQuizViewModel
    @State private var search: String = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTestMikoSearch") { return "ミコ" }
        if arguments.contains("-uiTestEdgarSearch") { return "えどがー" }
        if arguments.contains("-uiTestHiraganaSearch") { return "まっくす" }
        return ""
    }()
    private var results: [Brawler] {
        let query = BrawlerNameSearch.normalize(search)
        return query.isEmpty
            ? BrawlerDatabase.brawlers
            : BrawlerDatabase.brawlers.filter { BrawlerNameSearch.matches($0, query: query) }
    }
    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                Button(action: quiz.cancelChoosing) { Image(systemName: "chevron.left").frame(width: 42, height: 42).background(.white.opacity(0.12), in: Circle()) }
                VStack(alignment: .leading, spacing: 1) { Text("キャラを回答").font(.headline.bold()); Text("残り\(quiz.remainingSeconds)秒").font(.caption.bold()).foregroundStyle(quiz.remainingSeconds <= 15 ? PanelColors.coral : .white.opacity(0.62)) }
                Spacer()
                Label("\(quiz.correctCount)連勝", systemImage: "flame.fill")
                    .font(.caption2.bold()).foregroundStyle(PanelColors.cream)
                    .padding(.horizontal, 9).frame(height: 29)
                    .background(.white.opacity(0.1), in: Capsule())
            }.foregroundStyle(.white)
            HStack { Image(systemName: "magnifyingglass"); TextField("正式名称を検索", text: $search); if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") } } }
                .foregroundStyle(PanelColors.ink).padding(.horizontal, 14).frame(height: 46).background(PanelColors.cream, in: Capsule())
            HStack {
                Text(search.isEmpty ? "全キャラ" : "検索結果")
                Spacer()
                Text("\(results.count)体")
            }
            .font(.caption2.bold())
            .foregroundStyle(.white.opacity(0.68))
            .padding(.horizontal, 7)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(results) { brawler in
                        Button { quiz.select(brawler) } label: { PanelBrawlerRow(brawler: brawler, selected: quiz.selectedAnswer?.id == brawler.id) }.buttonStyle(.plain)
                    }
                }.padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 16).padding(.top, 10)
        .safeAreaInset(edge: .bottom) {
            if let selected = quiz.selectedAnswer {
                Button(action: quiz.submitSelected) { Text("\(selected.name)で回答する").font(.headline).frame(maxWidth: .infinity).frame(height: 50) }
                    .buttonStyle(PanelPrimaryButtonStyle()).padding(.horizontal, 18).padding(.vertical, 10)
                    .background(PanelColors.indigo.opacity(0.9).ignoresSafeArea())
            }
        }
    }
}

private enum BrawlerNameSearch {
    private static let readingAliases: [String: [String]] = [
        "R-T": ["あーるてぃー", "あーるてぃ", "あーるてぃい"],
        "MAX": ["まっくす"],
        "Emz": ["えむず", "えむじー"],
        "8ビット": ["えいとびっと", "はちびっと", "8bit"],
        "ミスターP": ["みすたーぴー"],
        "ラリー＆ローリー": ["らりーあんどろーりー"],
        "エル・プリモ": ["えるぷりも"]
    ]

    static func matches(_ brawler: Brawler, query: String) -> Bool {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return true }
        return searchKeys(for: brawler)
            .map(normalize)
            .contains { $0.contains(normalizedQuery) }
    }

    static func normalize(_ text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "ja_JP")
        )
        let hiragana = folded.applyingTransform(.hiraganaToKatakana, reverse: true) ?? folded
        return hiragana.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }

    private static func searchKeys(for brawler: Brawler) -> [String] {
        [brawler.name] + (readingAliases[brawler.name] ?? [])
    }
}

private struct PanelBrawlerRow: View {
    let brawler: Brawler; let selected: Bool
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(selected ? PanelColors.aqua : PanelColors.violet.opacity(0.12))
                Image(systemName: selected ? "checkmark" : "person.fill.questionmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(selected ? .white : PanelColors.violet.opacity(0.72))
            }
            .frame(width: 36, height: 36)
            Text(brawler.name).font(.headline.bold()).foregroundStyle(PanelColors.ink)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(PanelColors.violet.opacity(0.45))
        }.padding(.horizontal, 11).frame(height: 54).background(PanelColors.cream.opacity(selected ? 1 : 0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? PanelColors.aqua : .white.opacity(0.22), lineWidth: selected ? 2 : 1) }
    }
}

private struct PanelCorrectFeedbackView: View {
    @Bindable var quiz: PanelQuizViewModel

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 700
            VStack(spacing: compact ? 14 : 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("16パネルクイズ").font(.headline.bold())
                        Text("\(quiz.correctCount)問正解").font(.caption.bold()).opacity(0.62)
                    }
                    Spacer()
                    Label("\(quiz.correctCount)連勝", systemImage: "flame.fill")
                        .font(.caption.bold()).foregroundStyle(PanelColors.cream)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 15).frame(height: compact ? 58 : 64)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 21))
                .overlay { RoundedRectangle(cornerRadius: 21).stroke(.white.opacity(0.2), lineWidth: 1) }

                Spacer(minLength: 0)

                if let brawler = quiz.feedbackBrawler {
                    VStack(spacing: compact ? 10 : 14) {
                        Label("正解！", systemImage: "checkmark.seal.fill")
                            .font(.system(size: compact ? 22 : 25, weight: .black, design: .rounded))
                            .foregroundStyle(PanelColors.aqua)
                            .padding(.horizontal, 17).frame(height: 40)
                            .background(PanelColors.aqua.opacity(0.12), in: Capsule())

                        AsyncImage(url: brawler.imageURL) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                ProgressView().tint(PanelColors.violet)
                            }
                        }
                        .frame(width: compact ? 132 : 166, height: compact ? 132 : 166)
                        .clipShape(RoundedRectangle(cornerRadius: compact ? 22 : 27))
                        .overlay {
                            RoundedRectangle(cornerRadius: compact ? 22 : 27)
                                .stroke(PanelColors.violet.opacity(0.18), lineWidth: 1)
                        }

                        Text(brawler.name)
                            .font(.system(size: compact ? 27 : 32, weight: .black, design: .rounded))
                            .foregroundStyle(PanelColors.violet)

                        VStack(spacing: 8) {
                            HStack(spacing: 10) {
                                ProgressView().tint(PanelColors.violet)
                                Text("次の問題を準備しています")
                                    .font(.caption.bold())
                                    .foregroundStyle(PanelColors.ink.opacity(0.52))
                            }
                            HStack(spacing: 9) {
                                ProgressView(
                                    value: Double(quiz.correctCount),
                                    total: Double(max(BrawlerDatabase.brawlers.count, 1))
                                )
                                .tint(PanelColors.aqua)
                                Text(quiz.nextProgressText)
                                    .font(.caption2.bold())
                                    .foregroundStyle(PanelColors.ink.opacity(0.48))
                                    .fixedSize()
                            }
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, compact ? 20 : 28)
                    .padding(.vertical, compact ? 18 : 24)
                    .frame(maxWidth: 370)
                    .background(PanelColors.cream.opacity(0.98), in: RoundedRectangle(cornerRadius: 30))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(.white.opacity(0.78), lineWidth: 2)
                    }
                    .shadow(color: PanelColors.violet.opacity(0.3), radius: 22, y: 10)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 17).padding(.vertical, compact ? 8 : 14)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }
}

private struct PanelResultView: View {
    @Bindable var quiz: PanelQuizViewModel
    let game: GameViewModel, ads: InterstitialAdManager, audio: OracleAudioManager
    @State private var registered = false
    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 700
            VStack(spacing: compact ? 9 : 14) {
                Spacer()
                Image(systemName: quiz.endReason == .completed ? "crown.fill" : (quiz.endReason == .timeout ? "timer" : "sparkles"))
                    .font(.system(size: compact ? 42 : 54)).foregroundStyle(quiz.endReason == .completed ? .yellow : PanelColors.aqua)
                Text(title).font(.system(size: compact ? 27 : 33, weight: .black, design: .rounded)).foregroundStyle(.white)
                VStack(spacing: compact ? 8 : 12) {
                    if quiz.endReason != .completed, let current = quiz.current {
                        AsyncImage(url: current.imageURL) { $0.resizable().scaledToFill() } placeholder: { ProgressView() }
                            .frame(width: compact ? 112 : 140, height: compact ? 112 : 140).clipShape(RoundedRectangle(cornerRadius: 24))
                        Text(current.name).font(.system(size: 29, weight: .black, design: .rounded)).foregroundStyle(PanelColors.violet)
                    }
                    HStack { ResultMetric(value: "\(quiz.correctCount)", label: "連続正解"); ResultMetric(value: "\(quiz.passedCount)", label: "パス"); ResultMetric(value: "\(quiz.bestScore)", label: "最高記録") }
                }.padding(compact ? 15 : 20).frame(maxWidth: .infinity).background(PanelColors.cream.opacity(0.97), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.78), lineWidth: 1.5) }
                    .shadow(color: PanelColors.indigo.opacity(0.3), radius: 20, y: 9)
                Button { transition(quiz.start) } label: { Label("もう一度", systemImage: "arrow.clockwise").font(.headline).frame(maxWidth: .infinity).frame(height: 54) }.buttonStyle(PanelPrimaryButtonStyle())
                Button { transition(quiz.returnToIdle) } label: { Text("ゲームモードへ戻る").font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 44).background(.white.opacity(0.12), in: Capsule()) }.buttonStyle(.plain).foregroundStyle(.white)
                Spacer()
            }.padding(.horizontal, 21).frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            guard !registered else { return }; registered = true
            game.registerExternalCompletedGame(wasCorrect: quiz.endReason == .completed)
        }
    }
    private var title: String { switch quiz.endReason { case .wrong: "惜しい！チャレンジ終了"; case .timeout: "時間切れ！"; case .completed: quiz.passedCount == 0 ? "全キャラ完全制覇！" : "チャレンジ完走！"; case nil: "結果" } }
    private func transition(_ action: @escaping () -> Void) {
        guard game.isInterstitialDue else { action(); return }
        if !ads.presentIfAvailable(onPresented: { game.markInterstitialPresented(); audio.pauseForAd() }, completion: { audio.resumeAfterAd(); action() }) { action() }
    }
}

private struct ResultMetric: View {
    let value: String, label: String
    var body: some View { VStack(spacing: 3) { Text(value).font(.system(.title2, weight: .black)).foregroundStyle(PanelColors.violet); Text(label).font(.caption2.bold()).foregroundStyle(PanelColors.ink.opacity(0.5)) }.frame(maxWidth: .infinity) }
}

private struct PanelPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.white)
            .background(LinearGradient(colors: [PanelColors.aqua, PanelColors.blue], startPoint: .leading, endPoint: .trailing), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.72), lineWidth: 2) }
            .shadow(color: PanelColors.aqua.opacity(0.38), radius: 11, y: 5)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
    }
}

private struct PanelAnswerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [PanelColors.aqua, PanelColors.blue],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 19)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 19)
                    .stroke(.white.opacity(0.68), lineWidth: 1.5)
            }
            .shadow(color: PanelColors.aqua.opacity(0.32), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

private struct PanelBackground: View {
    var body: some View { GeometryReader { geo in Image("OracleBackground").resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height + 120).clipped().ignoresSafeArea() } }
}

private enum PanelColors {
    static let ink = Color(red: 0.12, green: 0.08, blue: 0.24)
    static let cream = Color(red: 1, green: 0.96, blue: 0.91)
    static let violet = Color(red: 0.35, green: 0.19, blue: 0.65)
    static let indigo = Color(red: 0.12, green: 0.12, blue: 0.38)
    static let coral = Color(red: 0.94, green: 0.42, blue: 0.48)
    static let aqua = Color(red: 0.12, green: 0.67, blue: 0.73)
    static let blue = Color(red: 0.18, green: 0.55, blue: 0.87)
}
