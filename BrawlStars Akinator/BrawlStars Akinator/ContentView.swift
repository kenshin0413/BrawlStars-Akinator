import SwiftUI
import StoreKit
import UIKit

struct ContentView: View {
    @State private var game = GameViewModel()
    @State private var audio = OracleAudioManager()
    @State private var updates = AppUpdateChecker()
    @State private var ads = InterstitialAdManager()
    @State private var panelQuiz = PanelQuizViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    var body: some View {
        ZStack {
            OracleBackdrop()
            Group {
                if panelQuiz.phase != .idle {
                    PanelQuizView(quiz: panelQuiz, game: game, ads: ads, audio: audio)
                } else {
                    switch game.phase {
                    case .home: HomeView(game: game, audio: audio, startPanelQuiz: panelQuiz.start)
                    case .playing: GameView(game: game)
                    case .guessing: GuessView(game: game)
                    case .finished: ResultView(game: game, ads: ads, audio: audio)
                    }
                }
            }
        }
        .tint(OraclePalette.aqua).preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.28), value: game.phase)
        .sheet(isPresented: $game.reportPresented) { ReportView(game: game) }
        .sheet(isPresented: $game.infoPresented) { DataInfoView(ads: ads) }
        .task {
            if !isUITesting {
                ads.configure()
                showAppOpenAd()
            }
            await updates.check()
        }
        .onChange(of: scenePhase) { _, phase in
            panelQuiz.setPaused(phase != .active)
            guard phase == .active, !isUITesting else { return }
            showAppOpenAd()
        }
        .onChange(of: game.reviewRequestPending) { _, shouldRequest in
            guard shouldRequest else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                await requestReview()
                game.markReviewRequestAttempted()
            }
        }
        .alert("アップデートがあります", isPresented: Binding(
            get: { updates.isUpdateAvailable },
            set: { if !$0 { updates.dismiss() } }
        )) {
            Button("あとで", role: .cancel) { updates.dismiss() }
            Button("アップデート") {
                if let url = updates.updateURL { openURL(url) }
                updates.dismiss()
            }
        } message: {
            Text("バージョン \(updates.latestVersion) を利用できます。App Storeから更新してください。")
        }
    }

    private func showAppOpenAd() {
        ads.requestAppOpenPresentation(
            onPresented: { audio.pauseForAd() },
            completion: { audio.resumeAfterAd() }
        )
    }

    private var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uiTest") }
        #else
        false
        #endif
    }
}

private struct HomeView: View {
    let game: GameViewModel
    @Bindable var audio: OracleAudioManager
    let startPanelQuiz: () -> Void
    var body: some View {
        GeometryReader { proxy in
            HomeDesignCanvas(
                game: game,
                audio: audio,
                startPanelQuiz: startPanelQuiz,
                viewport: proxy.size
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct HomeDesignCanvas: View {
    let game: GameViewModel
    @Bindable var audio: OracleAudioManager
    let startPanelQuiz: () -> Void
    let viewport: CGSize

    var body: some View {
        let source = CGSize(width: 853, height: 1844)
        let renderedWidth = min(viewport.width * 0.90, viewport.height * 0.49)
        let uniformScale = renderedWidth / source.width
        let rendered = CGSize(width: renderedWidth, height: source.height * uniformScale)
        let topOffset: CGFloat = viewport.height > 800 ? 22 : 6
        let origin = CGPoint(x: (viewport.width - rendered.width) / 2, y: topOffset)

        ZStack {
            Image("ModeSelectionForeground")
                .resizable()
                .scaledToFit()
                .frame(width: rendered.width, height: rendered.height)
                .position(x: origin.x + rendered.width / 2, y: origin.y + rendered.height / 2)
                .allowsHitTesting(false)

            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-showHitTargets") {
                ModePanelHitShape(kind: .akinator)
                    .fill(.green.opacity(0.34))
                    .frame(width: rendered.width, height: rendered.height)
                    .position(x: origin.x + rendered.width / 2, y: origin.y + rendered.height / 2)
                    .allowsHitTesting(false)
                ModePanelHitShape(kind: .panelQuiz)
                    .fill(.red.opacity(0.34))
                    .frame(width: rendered.width, height: rendered.height)
                    .position(x: origin.x + rendered.width / 2, y: origin.y + rendered.height / 2)
                    .allowsHitTesting(false)
            }
            #endif

            modePanelButton(
                kind: .akinator,
                renderedSize: rendered,
                origin: origin,
                label: "逆アキネーター、8問で見抜く",
                action: game.startGame
            )

            modePanelButton(
                kind: .panelQuiz,
                renderedSize: rendered,
                origin: origin,
                label: "16パネルクイズ、連続正解に挑戦",
                action: startPanelQuiz
            )

            HStack(spacing: 24) {
                Button { audio.toggle() } label: {
                    Label(
                        audio.isEnabled ? "BGM オン" : "BGM オフ",
                        systemImage: audio.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
                    )
                    .frame(minWidth: 118, minHeight: 48)
                    .contentShape(Rectangle())
                }
                Button { game.infoPresented = true } label: {
                    Label("データと情報源", systemImage: "checkmark.shield.fill")
                        .frame(minWidth: 132, minHeight: 48)
                        .contentShape(Rectangle())
                }
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .buttonStyle(.plain)
            .position(x: viewport.width / 2, y: viewport.height - 45)
        }
        .frame(width: viewport.width, height: viewport.height)
    }

    private func modePanelButton(
        kind: ModePanelHitShape.Kind,
        renderedSize: CGSize,
        origin: CGPoint,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        let hitShape = ModePanelHitShape(kind: kind)
        return Button(action: action) {
            hitShape
                // A tiny alpha keeps the label's rendered geometry identical to
                // the custom path without producing any visible overlay.
                .fill(Color.white.opacity(0.001))
                .frame(width: renderedSize.width, height: renderedSize.height)
        }
        .buttonStyle(.plain)
        .contentShape(hitShape)
        .accessibilityLabel(label)
        .position(
            x: origin.x + renderedSize.width / 2,
            y: origin.y + renderedSize.height / 2
        )
    }
}

private struct ModePanelHitShape: Shape {
    enum Kind { case akinator, panelQuiz }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.width * x, y: rect.height * y)
        }

        switch kind {
        case .akinator:
            // Trace only the visible cyan lobe. The inward curve deliberately
            // leaves the ghost and the central ornament non-interactive.
            path.move(to: point(0.50, 0.245))
            path.addCurve(to: point(0.10, 0.315),
                          control1: point(0.34, 0.245), control2: point(0.17, 0.265))
            path.addCurve(to: point(0.025, 0.485),
                          control1: point(0.045, 0.360), control2: point(0.005, 0.430))
            path.addCurve(to: point(0.205, 0.565),
                          control1: point(0.020, 0.535), control2: point(0.095, 0.575))
            path.addCurve(to: point(0.355, 0.450),
                          control1: point(0.300, 0.550), control2: point(0.280, 0.485))
            path.addCurve(to: point(0.575, 0.410),
                          control1: point(0.410, 0.405), control2: point(0.500, 0.395))
            path.addCurve(to: point(0.790, 0.430),
                          control1: point(0.655, 0.420), control2: point(0.715, 0.460))
            path.addCurve(to: point(0.935, 0.355),
                          control1: point(0.875, 0.445), control2: point(0.935, 0.410))
            path.addCurve(to: point(0.820, 0.275),
                          control1: point(0.935, 0.310), control2: point(0.895, 0.280))
            path.addCurve(to: point(0.50, 0.245),
                          control1: point(0.720, 0.245), control2: point(0.610, 0.235))
            path.closeSubpath()
        case .panelQuiz:
            // Trace only the visible purple lobe. This shape meets the cyan
            // panel at its border without covering the center illustration.
            path.move(to: point(0.800, 0.455))
            path.addCurve(to: point(0.960, 0.570),
                          control1: point(0.885, 0.455), control2: point(0.950, 0.505))
            path.addCurve(to: point(0.850, 0.725),
                          control1: point(0.975, 0.640), control2: point(0.930, 0.690))
            path.addCurve(to: point(0.510, 0.790),
                          control1: point(0.755, 0.775), control2: point(0.625, 0.795))
            path.addCurve(to: point(0.160, 0.725),
                          control1: point(0.370, 0.790), control2: point(0.235, 0.770))
            path.addCurve(to: point(0.075, 0.625),
                          control1: point(0.095, 0.695), control2: point(0.055, 0.655))
            path.addCurve(to: point(0.135, 0.575),
                          control1: point(0.070, 0.590), control2: point(0.095, 0.575))
            path.addCurve(to: point(0.335, 0.615),
                          control1: point(0.205, 0.550), control2: point(0.275, 0.590))
            path.addCurve(to: point(0.575, 0.650),
                          control1: point(0.405, 0.655), control2: point(0.505, 0.670))
            path.addCurve(to: point(0.710, 0.565),
                          control1: point(0.640, 0.635), control2: point(0.675, 0.605))
            path.addCurve(to: point(0.800, 0.455),
                          control1: point(0.750, 0.515), control2: point(0.755, 0.465))
            path.closeSubpath()
        }
        return path
    }
}

private struct RadialModeSelector: View {
    let startAkinator: () -> Void
    let startPanelQuiz: () -> Void
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().stroke(OraclePalette.cream.opacity(0.28), lineWidth: 1).padding(side * 0.035)
                    .scaleEffect(x: 1, y: 1.22)
                Circle().stroke(.white.opacity(0.1), lineWidth: 1).padding(side * 0.095)
                    .scaleEffect(x: 1, y: 1.22)
                Image("ModeSelectorRing").resizable().scaledToFit()
                    .scaleEffect(x: 1, y: 1.22)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Button(action: startAkinator) { Color.clear.contentShape(Rectangle()) }
                        .accessibilityLabel("逆アキネーター、8問で見抜く")
                    Button(action: startPanelQuiz) { Color.clear.contentShape(Rectangle()) }
                        .accessibilityLabel("16パネルクイズ、連続正解に挑戦")
                }
                .padding(side * 0.07)

                modeLabel(
                    title: "逆アキネーター",
                    subtitle: "8問で見抜く",
                    icon: "bubble.left.fill",
                    arrowFirst: false,
                    side: side
                )
                .offset(y: -side * 0.31)

                bottomModeLabel(side: side)

                Image("OracleGhost").resizable().scaledToFit().frame(height: side * 0.35)
                    .offset(y: side * 0.025)
                    .shadow(color: OraclePalette.aqua.opacity(0.35), radius: 18).allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func bottomModeLabel(side: CGFloat) -> some View {
        ZStack {
            arrowBadge(side: side)
                .position(x: side * 0.22, y: side * 0.78)

            VStack(spacing: side * 0.008) {
                Text("16パネルクイズ")
                    .font(.system(size: side * 0.052, weight: .black, design: .rounded))
                    .lineLimit(1)
                Text("連続正解に挑戦")
                    .font(.system(size: side * 0.032, weight: .bold, design: .rounded))
                    .opacity(0.82)
            }
            .position(x: side * 0.50, y: side * 0.87)

            iconBadge("square.grid.3x3.fill", side: side)
                .position(x: side * 0.78, y: side * 0.76)
        }
        .frame(width: side, height: side)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        .allowsHitTesting(false)
    }

    private func modeLabel(title: String, subtitle: String, icon: String, arrowFirst: Bool, side: CGFloat) -> some View {
        HStack(spacing: side * 0.035) {
            if arrowFirst { arrowBadge(side: side) }
            iconBadge(icon, side: side)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: side * 0.046, weight: .black, design: .rounded))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: side * 0.032, weight: .bold, design: .rounded))
                    .opacity(0.82)
            }
            if !arrowFirst { arrowBadge(side: side) }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        .allowsHitTesting(false)
    }

    private func iconBadge(_ icon: String, side: CGFloat) -> some View {
        Image(systemName: icon)
            .font(.system(size: side * 0.046, weight: .black))
            .frame(width: side * 0.13, height: side * 0.13)
            .background(.white.opacity(0.12), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 2))
    }

    private func arrowBadge(side: CGFloat) -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: side * 0.033, weight: .black))
            .frame(width: side * 0.09, height: side * 0.09)
            .background(.white.opacity(0.08), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.82), lineWidth: 1.5))
    }
}

private struct IllustratedModeButton: View {
    let title: String, subtitle: String, icon: String
    let accent: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 30, weight: .black)).foregroundStyle(accent)
                    .frame(width: 64, height: 64).background(.white.opacity(0.92), in: Circle())
                    .shadow(color: .white.opacity(0.5), radius: 10)
                Spacer()
                Text(title).font(.system(size: 15, weight: .black, design: .rounded)).lineLimit(1).minimumScaleFactor(0.62)
                Text(subtitle).font(.caption2.bold()).foregroundStyle(.white.opacity(0.86))
            }
            .foregroundStyle(.white).multilineTextAlignment(.center)
            .padding(.vertical, 15).padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(ModeCardButtonStyle())
    }
}

private struct OracleModeCardStage: View {
    let compact: Bool
    let startAkinator: () -> Void
    let startPanelQuiz: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Image("ModeSelectionCards")
                .resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .accessibilityHidden(true)
            HStack(spacing: compact ? 6 : 10) {
                ModeCard(title: "逆アキネーター", subtitle: "8問で見抜く", icon: "bubble.left.and.bubble.right.fill", accent: .blue, compact: compact, action: startAkinator)
                    .rotationEffect(.degrees(-3.2), anchor: .bottom)
                ModeCard(title: "16パネルクイズ", subtitle: "連続正解に挑戦", icon: "square.grid.3x3.fill", accent: OraclePalette.plum, compact: compact, action: startPanelQuiz)
                    .rotationEffect(.degrees(3.2), anchor: .bottom)
            }
            .padding(.horizontal, compact ? 25 : 34)
            .padding(.bottom, compact ? 91 : 119)
        }
    }
}

private struct ModeCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 7 : 11) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 30 : 38, weight: .black))
                    .frame(width: compact ? 62 : 78, height: compact ? 62 : 78)
                    .background(.white.opacity(0.9), in: Circle())
                    .foregroundStyle(accent)
                    .shadow(color: .white.opacity(0.55), radius: 12)
                Spacer(minLength: 0)
                Text(title).font(.system(size: compact ? 14 : 17, weight: .black, design: .rounded)).lineLimit(1).minimumScaleFactor(0.68)
                Rectangle().fill(OraclePalette.cream.opacity(0.72)).frame(width: 54, height: 1)
                Text(subtitle).font(compact ? .caption2.bold() : .caption.bold()).foregroundStyle(.white.opacity(0.82))
                Image(systemName: "diamond.fill").font(.system(size: 8)).foregroundStyle(OraclePalette.cream)
            }
            .foregroundStyle(.white).multilineTextAlignment(.center)
            .padding(.horizontal, 6).padding(.top, compact ? 32 : 42).padding(.bottom, compact ? 17 : 23)
            .frame(maxWidth: .infinity).frame(height: compact ? 246 : 310)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(ModeCardButtonStyle())
    }
}

private struct ModeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct HomeOracleHero: View {
    let compact: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(LinearGradient(
                    colors: [.white.opacity(0.46), OraclePalette.aqua.opacity(0.16), OraclePalette.cream.opacity(0.42)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1.2)
                .frame(width: compact ? 162 : 214, height: compact ? 162 : 214)
                .overlay {
                    Circle()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 8]))
                        .foregroundStyle(.white.opacity(0.24))
                        .padding(8)
                }
                .shadow(color: OraclePalette.aqua.opacity(0.22), radius: 16)
            HStack {
                Image(systemName: "diamond").offset(x: compact ? -7 : -12)
                Spacer()
                Image(systemName: "diamond").offset(x: compact ? 7 : 12)
            }
            .font(.system(size: compact ? 12 : 16, weight: .bold))
            .foregroundStyle(OraclePalette.aqua.opacity(0.82))
            .frame(width: compact ? 174 : 230)

            Image("OracleGhost")
                .resizable()
                .scaledToFit()
                .frame(height: compact ? 126 : 168)
                .shadow(color: OraclePalette.aqua.opacity(0.34), radius: 18)
        }
        .frame(height: compact ? 144 : 190)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HomeBrandLockup: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 1 : 3) {
            HStack(spacing: 8) {
                brandRule
                Text("ブロスタ")
                    .font(.system(size: compact ? 29 : 35, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(LinearGradient(
                        colors: [.white, OraclePalette.cream],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .shadow(color: OraclePalette.plum.opacity(0.7), radius: 1, y: 2)
                brandRule
            }
            Text("逆アキネーター")
                .font(.system(size: compact ? 18 : 21, weight: .heavy, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(OraclePalette.cream.opacity(0.96))
            HStack(spacing: 6) {
                Rectangle().frame(width: 30, height: 1)
                Image(systemName: "diamond.fill").font(.system(size: 6))
                Rectangle().frame(width: 30, height: 1)
            }
            .foregroundStyle(OraclePalette.aqua.opacity(0.72))
        }
        .accessibilityElement(children: .combine)
    }

    private var brandRule: some View {
        LinearGradient(
            colors: [.clear, OraclePalette.cream.opacity(0.72)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: compact ? 24 : 34, height: 1)
    }
}

private struct HomeStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.bold()).foregroundStyle(OraclePalette.plum)
            Text(label).font(.caption2.bold()).foregroundStyle(OraclePalette.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OraclePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [OraclePalette.aqua, Color(red: 0.18, green: 0.55, blue: 0.87)], startPoint: .leading, endPoint: .trailing), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.72), lineWidth: 2) }
            .shadow(color: OraclePalette.aqua.opacity(configuration.isPressed ? 0.18 : 0.45), radius: configuration.isPressed ? 4 : 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct GameView: View {
    @Bindable var game: GameViewModel
    @State private var confirmGuess = false
    @State private var lane: OracleLane = .attack

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: geometry.size.height < 700 ? 7 : 10) {
                    historyBoard
                    oracleResponse(compact: geometry.size.height < 700)
                    laneSelector
                    questionLibrary
                }
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .background {
                    Image("OracleBackground").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height + 120)
                        .clipped().ignoresSafeArea()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("回答画面へ進みますか？", isPresented: $confirmGuess, titleVisibility: .visible) {
                Button("回答画面へ進む") { game.beginGuess() }
                Button("まだ質問する", role: .cancel) {}
            } message: {
                Text("回答画面を開くと、質問画面には戻れません。")
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: game.history.count)
            .onAppear {
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("-uiTestBasic") { lane = .basic }
                if arguments.contains("-uiTestMovement") { lane = .movement }
                if arguments.contains("-uiTestSpecial") { lane = .special }
                let visibleIDs = Set(OracleLane.allCases.flatMap { item in
                    QuestionDatabase.all.filter { item.categories.contains($0.category) }.map(\.id)
                })
                assert(visibleIDs == Set(QuestionDatabase.all.map(\.id)), "4カテゴリに含まれない質問があります")
                #endif
            }
        }
    }

    private var historyBoard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("質問履歴", systemImage: "clock.arrow.circlepath").font(.caption.bold()).foregroundStyle(OraclePalette.plum)
                Spacer()
                Text("\(game.history.count) / \(game.maxQuestions)").font(.caption.bold()).foregroundStyle(OraclePalette.ink.opacity(0.55))
                Button { confirmGuess = true } label: {
                    Label("キャラを回答", systemImage: "person.fill")
                        .font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(OraclePalette.coral, in: Capsule())
                }.buttonStyle(.plain)
            }.padding(.horizontal, 12).padding(.top, 9)
            if game.history.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles").foregroundStyle(OraclePalette.aqua)
                    Text("質問すると、答えがここに並びます").font(.caption.bold()).foregroundStyle(OraclePalette.ink.opacity(0.62))
                    Spacer()
                }.padding(.horizontal, 12).frame(height: 49)
            } else if game.history.count <= 2 {
                HStack(spacing: 8) {
                    ForEach(Array(game.history.enumerated()), id: \.element.id) { index, item in
                        historyCard(index: index, item: item).frame(maxWidth: .infinity)
                    }
                }.padding(.horizontal, 10)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(game.history.enumerated()), id: \.element.id) { index, item in
                                historyCard(index: index, item: item).frame(width: 160).id(item.id)
                            }
                        }
                    }
                    .contentMargins(.horizontal, 10, for: .scrollContent)
                    .defaultScrollAnchor(.trailing)
                    .onChange(of: game.history.count) { _, _ in
                        if let last = game.history.last { withAnimation { proxy.scrollTo(last.id, anchor: .trailing) } }
                    }
                }
            }
        }
        .frame(height: 88)
        .background(OraclePalette.cream.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.72), lineWidth: 1.5) }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func historyCard(index: Int, item: AskedQuestion) -> some View {
        Button { game.openReport(for: item) } label: {
            HStack(spacing: 8) {
                Text("Q\(index + 1)").font(.caption2.bold()).foregroundStyle(.white).frame(width: 28, height: 28).background(OraclePalette.plum, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.question.text).font(.caption2.bold()).foregroundStyle(OraclePalette.ink).lineLimit(1).minimumScaleFactor(0.72)
                    Label(item.answer.rawValue, systemImage: item.answer.symbol).font(.caption2.bold()).foregroundStyle(answerColor(item.answer))
                }
            }.padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading).frame(height: 43)
                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    private func oracleResponse(compact: Bool) -> some View {
        VStack(spacing: 2) {
            VStack(alignment: .center, spacing: 2) {
                if let latest = game.history.last {
                    Text(latest.answer.rawValue)
                        .font(.system(size: compact ? 20 : 23, weight: .black, design: .rounded))
                        .foregroundStyle(answerColor(latest.answer))
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(ghostFollowUp)
                        .font(.caption2.bold()).foregroundStyle(OraclePalette.ink.opacity(0.62))
                        .lineLimit(1).multilineTextAlignment(.center)
                } else {
                    Text("最初の質問は？").font(.system(size: compact ? 16 : 19, weight: .black, design: .rounded)).foregroundStyle(OraclePalette.ink)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, compact ? 7 : 9)
            .background(OraclePalette.cream, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: OraclePalette.plum.opacity(0.24), radius: 7, y: 3)

            Image("OracleGhost").resizable().scaledToFit().frame(height: compact ? 124 : 154)
                .phaseAnimator([false, true]) { content, raised in
                    content.offset(y: raised ? -2 : 2)
                } animation: { _ in
                    .easeInOut(duration: 2.4)
                }
                .offset(y: compact ? 8 : 6)
        }
        .frame(maxWidth: .infinity).frame(height: compact ? 222 : 242, alignment: .top)
    }

    private var ghostFollowUp: String {
        guard let latest = game.history.last else { return "" }
        let yesLines = [
            "最初の手がかりをつかんだね",
            "その特徴は大きな手がかりだ",
            "候補の輪郭が見えてきたよ",
            "いい流れだ。別の角度も見よう",
            "かなり深く絞れてきたね",
            "答えに近づく一手になった",
            "最後の確認を慎重に選ぼう",
            "質問はここまで。答えを決めよう"
        ]
        let noLines = [
            "違う特徴から探してみよう",
            "候補をまとめて外せそうだ",
            "その線ではなさそうだね",
            "反対側の特徴を確かめよう",
            "消えた候補を思い返してみて",
            "残る可能性に集中しよう",
            "あと一手で確信を持てるかな",
            "聞けるのはここまで。回答しよう"
        ]
        let partialLines = [
            "条件つきで当てはまるようだ",
            "装備や状態も考えてみて",
            "一部だけ成立するのが鍵だね",
            "例外を含む候補に注目しよう",
            "条件を整理すると見えてくるよ",
            "特殊な能力を思い出してみよう",
            "この曖昧さが最後の手がかりだ",
            "条件も含めて答えを決めよう"
        ]
        let index = min(max(game.history.count - 1, 0), game.maxQuestions - 1)
        switch latest.answer {
        case .yes: return yesLines[index]
        case .no: return noLines[index]
        case .partial: return partialLines[index]
        }
    }

    private var laneSelector: some View {
        HStack(spacing: 6) {
            ForEach(OracleLane.allCases) { item in
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { lane = item } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon).font(.caption.bold())
                        Text(item.title).font(.caption.weight(.black))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(item.color.opacity(lane == item ? 1 : 0.72), in: RoundedRectangle(cornerRadius: 11))
                    .overlay { RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(lane == item ? 0.95 : 0.48), lineWidth: lane == item ? 2 : 1) }
                    .shadow(color: lane == item ? item.color.opacity(0.55) : .clear, radius: 7, y: 3)
                    .offset(y: lane == item ? -2 : 0)
                }.buttonStyle(.plain)
            }
        }
    }

    private var laneQuestions: [GameQuestion] {
        let used = Set(game.history.map { $0.question.id })
        let questions = QuestionDatabase.all.filter { question in
            lane.categories.contains(question.category) && !used.contains(question.id)
        }
        return questions.filter(game.isFavorite) + questions.filter { !game.isFavorite($0) }
    }

    private var questionLibrary: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(lane.title)の質問").font(.subheadline.bold()).foregroundStyle(OraclePalette.ink)
                Spacer()
                Text("\(laneQuestions.count)件").font(.caption.bold()).foregroundStyle(OraclePalette.plum.opacity(0.65))
            }.padding(.horizontal, 14).frame(height: 38)
            Divider().overlay(OraclePalette.plum.opacity(0.14)).padding(.horizontal, 12)
            if game.canAsk {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(laneQuestions.enumerated()), id: \.element.id) { index, question in
                            HStack(spacing: 8) {
                                Button { game.ask(question) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: question.category.icon).font(.caption.bold()).foregroundStyle(lane.color).frame(width: 27, height: 27).background(lane.color.opacity(0.12), in: Circle())
                                        Text(question.text).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(OraclePalette.ink).multilineTextAlignment(.leading)
                                        Spacer(); Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(OraclePalette.plum.opacity(0.38))
                                    }.padding(.horizontal, 12).frame(minHeight: 50).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                        game.toggleFavorite(question)
                                    }
                                } label: {
                                    Image(systemName: game.isFavorite(question) ? "star.fill" : "star")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(game.isFavorite(question) ? Color.orange : OraclePalette.plum.opacity(0.46))
                                        .frame(width: 36, height: 42)
                                        .offset(x: -6)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(game.isFavorite(question) ? "お気に入りから削除" : "お気に入りに追加")
                            }
                            if index < laneQuestions.count - 1 { Divider().overlay(OraclePalette.plum.opacity(0.11)).padding(.leading, 49).padding(.trailing, 12) }
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.title2).foregroundStyle(OraclePalette.plum)
                    Text("8問の質問が終わりました")
                        .font(.headline).foregroundStyle(OraclePalette.ink)
                    Button { confirmGuess = true } label: {
                        Label("キャラを回答", systemImage: "person.fill")
                            .font(.headline.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(OraclePalette.coral, in: Capsule())
                    }.buttonStyle(.plain)
                }.padding(22)
            }
        }.frame(maxHeight: .infinity)
            .background(OraclePalette.cream.opacity(0.97), in: RoundedRectangle(cornerRadius: 21))
            .overlay { RoundedRectangle(cornerRadius: 21).stroke(.white.opacity(0.72), lineWidth: 1.5) }
            .sensoryFeedback(.selection, trigger: game.favoriteQuestionIDs)
    }

}

private enum OracleLane: String, CaseIterable, Identifiable {
    case basic, attack, movement, special
    var id: String { rawValue }
    var title: String { switch self { case .basic: "基本"; case .attack: "攻撃"; case .movement: "移動"; case .special: "特殊" } }
    var icon: String { switch self { case .basic: "diamond.fill"; case .attack: "scope"; case .movement: "figure.run"; case .special: "sparkles" } }
    var color: Color { switch self { case .basic: OraclePalette.coral; case .attack: OraclePalette.plum; case .movement: OraclePalette.aqua; case .special: OraclePalette.blue } }
    var categories: Set<QuestionCategory> {
        switch self {
        case .basic: [.basic, .appearance]
        case .attack: [.attack, .superAbility]
        case .movement: [.movement]
        case .special: [.special, .unique]
        }
    }

}

private enum OraclePalette {
    static let ink = Color(red: 0.12, green: 0.08, blue: 0.24)
    static let cream = Color(red: 1.0, green: 0.96, blue: 0.91)
    static let plum = Color(red: 0.35, green: 0.19, blue: 0.65)
    static let coral = Color(red: 0.94, green: 0.42, blue: 0.48)
    static let aqua = Color(red: 0.12, green: 0.67, blue: 0.73)
    static let blue = Color(red: 0.31, green: 0.48, blue: 0.82)
}

private struct DiamondProgress: View {
    let filled: Bool
    let current: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 2).rotation(.degrees(45))
            .fill(filled ? OraclePalette.coral : current ? Color.white : Color.white.opacity(0.2))
            .overlay { RoundedRectangle(cornerRadius: 2).rotation(.degrees(45)).stroke(.white.opacity(0.55), lineWidth: 1) }
            .frame(width: current ? 12 : 9, height: current ? 12 : 9)
            .shadow(color: current ? .white.opacity(0.7) : .clear, radius: 5)
    }
}

private struct GuessView: View {
    @Bindable var game: GameViewModel
    @State private var search = ""
    @State private var pendingGuess: Brawler?
    private var results: [Brawler] {
        let query = normalizedSearchText(search)
        guard !query.isEmpty else { return BrawlerDatabase.brawlers }
        return BrawlerDatabase.brawlers.filter { normalizedSearchText($0.name).contains(query) }
    }

    private func normalizedSearchText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let compact = geometry.size.height < 700
                VStack(spacing: compact ? 8 : 11) {
                    HStack(spacing: 11) {
                        Image("OracleGhost").resizable().scaledToFit().frame(width: compact ? 48 : 58, height: compact ? 48 : 58)
                            .shadow(color: OraclePalette.aqua.opacity(0.34), radius: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("最後の答えを選ぼう")
                                .font(.system(size: compact ? 20 : 23, weight: .black, design: .rounded)).foregroundStyle(.white)
                            Label("選ぶと質問には戻れません", systemImage: "lock.fill")
                                .font(.caption2.bold()).foregroundStyle(.white.opacity(0.68))
                        }
                        Spacer()
                    }.padding(.horizontal, 4)
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(OraclePalette.plum)
                        TextField("", text: $search, prompt: Text("正式名称を検索").foregroundStyle(OraclePalette.ink.opacity(0.45))).foregroundStyle(OraclePalette.ink)
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(OraclePalette.ink.opacity(0.35)) }
                                .buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 15).frame(height: compact ? 46 : 50).background(OraclePalette.cream, in: Capsule())
                        .overlay { Capsule().stroke(.white.opacity(0.72), lineWidth: 1.5) }
                    HStack {
                        Text(search.isEmpty ? "全キャラ" : "検索結果").font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text("\(results.count)体").font(.caption.bold()).foregroundStyle(OraclePalette.cream)
                    }.padding(.horizontal, 5)
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(results) { brawler in
                                Button { withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { pendingGuess = brawler } } label: {
                                    BrawlerRow(brawler: brawler, selected: pendingGuess?.id == brawler.id)
                                }.buttonStyle(.plain)
                            }
                            if results.isEmpty {
                                VStack(spacing: 9) {
                                    Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(OraclePalette.plum.opacity(0.5))
                                    Text("該当するキャラが見つかりません").font(.subheadline.bold()).foregroundStyle(OraclePalette.ink.opacity(0.62))
                                }.frame(maxWidth: .infinity).padding(.vertical, 34)
                                    .background(OraclePalette.cream.opacity(0.95), in: RoundedRectangle(cornerRadius: 22))
                            }
                        }.padding(.bottom, 4)
                    }.scrollClipDisabled(false)
                }
                .padding(.horizontal, 16).padding(.top, 10)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .background {
                    Image("OracleBackground").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height + 120)
                        .clipped().ignoresSafeArea()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let pendingGuess {
                    GuessConfirmationBar(brawler: pendingGuess, clear: {
                        withAnimation(.easeOut(duration: 0.2)) { self.pendingGuess = nil }
                    }, submit: {
                        game.submitGuess(pendingGuess)
                    })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sensoryFeedback(.selection, trigger: pendingGuess?.id)
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-uiTestGuessSelected") {
                    pendingGuess = results.first
                }
                #endif
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct BrawlerRow: View {
    let brawler: Brawler
    let selected: Bool
    var body: some View {
        HStack(spacing: 13) {
            AsyncImage(url: brawler.imageURL) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "person.crop.circle.fill").font(.largeTitle).foregroundStyle(.secondary) }
                .frame(width: 56, height: 56).background(.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 15)).clipShape(RoundedRectangle(cornerRadius: 15))
            Text(brawler.name).font(.headline).foregroundStyle(OraclePalette.ink).lineLimit(1).minimumScaleFactor(0.75)
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3).foregroundStyle(selected ? OraclePalette.aqua : OraclePalette.plum.opacity(0.33))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(selected ? OraclePalette.cream : OraclePalette.cream.opacity(0.94), in: RoundedRectangle(cornerRadius: 19))
        .overlay { RoundedRectangle(cornerRadius: 19).stroke(selected ? OraclePalette.aqua : .white.opacity(0.62), lineWidth: selected ? 2.5 : 1) }
        .shadow(color: selected ? OraclePalette.aqua.opacity(0.25) : OraclePalette.ink.opacity(0.08), radius: selected ? 10 : 4, y: 3)
        .contentShape(Rectangle())
    }
}

private struct GuessConfirmationBar: View {
    let brawler: Brawler
    let clear: () -> Void
    let submit: () -> Void
    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                AsyncImage(url: brawler.imageURL) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.2) }
                    .frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text("このキャラで決定？").font(.caption2.bold()).foregroundStyle(.white.opacity(0.62))
                    Text(brawler.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                }
                Spacer()
                Button(action: clear) { Image(systemName: "xmark").font(.caption.bold()).frame(width: 32, height: 32).background(.white.opacity(0.12), in: Circle()) }
                    .buttonStyle(.plain).foregroundStyle(.white)
            }
            Button(action: submit) {
                Label("このキャラで回答する", systemImage: "sparkles")
                    .font(.headline).frame(maxWidth: .infinity).frame(height: 48)
            }.buttonStyle(OraclePrimaryButtonStyle())
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 9)
        .background(LinearGradient(colors: [OraclePalette.plum.opacity(0.97), OraclePalette.ink.opacity(0.98)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
        .shadow(color: OraclePalette.ink.opacity(0.4), radius: 18, y: -4)
        .overlay(alignment: .top) { Divider().overlay(.white.opacity(0.18)) }
    }
}

private struct ResultView: View {
    let game: GameViewModel
    let ads: InterstitialAdManager
    let audio: OracleAudioManager
    var body: some View {
        ZStack {
            OracleBackdrop()
            GeometryReader { geometry in
                let compact = geometry.size.height < 700
                VStack(spacing: compact ? 7 : 10) {
                    Image("OracleGhost").resizable().scaledToFit().frame(height: compact ? 100 : 120)
                        .shadow(color: (game.wasCorrect ? OraclePalette.aqua : OraclePalette.coral).opacity(0.3), radius: 15)
                    VStack(spacing: compact ? 8 : 10) {
                        Text(game.wasCorrect ? "見事、正解！" : "正体はこのキャラ")
                            .font(.system(size: compact ? 27 : 30, weight: .black, design: .rounded))
                            .foregroundStyle(game.wasCorrect ? OraclePalette.aqua : OraclePalette.coral)
                        if let target = game.target {
                            AsyncImage(url: target.imageURL) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(OraclePalette.plum) }
                                .frame(width: compact ? 118 : 130, height: compact ? 118 : 130)
                                .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 24))
                                .overlay { RoundedRectangle(cornerRadius: 24).stroke(OraclePalette.plum.opacity(0.12), lineWidth: 1) }
                            Text("選ばれていたキャラ").font(.caption.bold()).foregroundStyle(OraclePalette.ink.opacity(0.48)).tracking(0.5)
                            Text(target.name).font(.system(size: compact ? 34 : 39, weight: .black, design: .rounded)).foregroundStyle(OraclePalette.plum)
                            Text("\(target.rarity) ・ \(target.className)").font(.subheadline.bold()).foregroundStyle(OraclePalette.ink.opacity(0.52))
                        }
                        if !game.wasCorrect, let guessed = game.guessedBrawler {
                            HStack(spacing: 6) {
                                Text("あなたの回答").foregroundStyle(OraclePalette.ink.opacity(0.48))
                                Text(guessed.name).foregroundStyle(OraclePalette.ink)
                            }.font(.caption.bold()).padding(.horizontal, 14).frame(height: 34).background(.white.opacity(0.62), in: Capsule())
                        }
                    }.frame(maxWidth: .infinity).padding(compact ? 14 : 17)
                        .background(OraclePalette.cream.opacity(0.97), in: RoundedRectangle(cornerRadius: 30))
                        .overlay { RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.76), lineWidth: 1.5) }
                        .shadow(color: OraclePalette.ink.opacity(0.15), radius: 16, y: 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 22).padding(.vertical, compact ? 5 : 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    Button { performResultTransition(game.startGame) } label: {
                        Label("もう一度", systemImage: "arrow.clockwise")
                            .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                    }
                    .buttonStyle(OraclePrimaryButtonStyle())
                    HStack(spacing: 8) {
                        ResultShareButton(game: game)
                        .buttonStyle(.plain).foregroundStyle(OraclePalette.ink)
                        .background(OraclePalette.cream.opacity(0.94), in: Capsule())
                        Button("トップへ") { performResultTransition(game.returnHome) }
                            .font(.caption.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .background(OraclePalette.plum.opacity(0.88), in: Capsule())
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 5)
                .background(LinearGradient(colors: [OraclePalette.plum.opacity(0.2), OraclePalette.ink.opacity(0.74)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            }
        }
    }

    private func performResultTransition(_ action: @escaping () -> Void) {
        guard game.isInterstitialDue else {
            action()
            return
        }
        let didPresent = ads.presentIfAvailable(
            onPresented: {
                game.markInterstitialPresented()
                audio.pauseForAd()
            },
            completion: {
                audio.resumeAfterAd()
                action()
            }
        )
        if !didPresent { action() }
    }
}

private struct ResultShareButton: View {
    let game: GameViewModel
    @State private var isPreparing = false
    @State private var shareItems: [Any] = []
    @State private var isPresentingShare = false

    var body: some View {
        Button(action: prepareShare) {
            HStack(spacing: 6) {
                if isPreparing {
                    ProgressView().tint(OraclePalette.plum)
                    Text("画像を準備中")
                } else {
                    Image(systemName: "square.and.arrow.up")
                    Text("結果をシェア")
                }
            }
            .font(.caption.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity).frame(height: 38)
        .contentShape(Capsule())
        .disabled(isPreparing)
        .sheet(isPresented: $isPresentingShare) { ActivityShareSheet(items: shareItems) }
    }

    private func prepareShare() {
        guard let target = game.target else { return }
        isPreparing = true
        Task {
            var portrait: UIImage?
            if let url = target.imageURL,
               let (data, _) = try? await URLSession.shared.data(from: url) {
                portrait = UIImage(data: data)
            }
            let image = await MainActor.run {
                ResultShareCardRenderer.render(
                    wasCorrect: game.wasCorrect,
                    targetName: target.name,
                    guessedName: game.guessedBrawler?.name,
                    questionCount: game.history.count,
                    portrait: portrait
                )
            }
            shareItems = [image, game.resultShareText]
            isPreparing = false
            isPresentingShare = true
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

@MainActor
private enum ResultShareCardRenderer {
    static func render(wasCorrect: Bool, targetName: String, guessedName: String?, questionCount: Int, portrait: UIImage?) -> UIImage {
        let size = CGSize(width: 1080, height: 1350)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let colors = [UIColor(red: 0.09, green: 0.17, blue: 0.49, alpha: 1).cgColor,
                          UIColor(red: 0.46, green: 0.30, blue: 0.73, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

            if let background = UIImage(named: "OracleBackground") {
                background.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: 0.38)
            }
            drawCentered("ブロスタ 逆アキネーター", y: 92, font: .systemFont(ofSize: 45, weight: .heavy), color: .white)
            drawCentered("8問で見抜け", y: 154, font: .systemFont(ofSize: 27, weight: .bold), color: UIColor.white.withAlphaComponent(0.75))

            let card = CGRect(x: 90, y: 245, width: 900, height: 840)
            UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 0.97).setFill()
            UIBezierPath(roundedRect: card, cornerRadius: 64).fill()

            let resultColor = wasCorrect ? UIColor(red: 0.08, green: 0.65, blue: 0.70, alpha: 1) : UIColor(red: 0.94, green: 0.36, blue: 0.43, alpha: 1)
            drawCentered(wasCorrect ? "見事、正解！" : "惜しい！", y: 318, font: .systemFont(ofSize: 67, weight: .black), color: resultColor)

            let portraitRect = CGRect(x: 330, y: 440, width: 420, height: 420)
            UIColor.white.withAlphaComponent(0.62).setFill()
            UIBezierPath(roundedRect: portraitRect, cornerRadius: 55).fill()
            if let portrait {
                let side = min(portrait.size.width, portrait.size.height)
                let crop = CGRect(x: (portrait.size.width - side) / 2, y: (portrait.size.height - side) / 2, width: side, height: side)
                if let cropped = portrait.cgImage?.cropping(to: crop) {
                    UIImage(cgImage: cropped).draw(in: portraitRect)
                }
            }

            drawCentered("選ばれていたキャラ", y: 895, font: .systemFont(ofSize: 27, weight: .bold), color: UIColor(red: 0.35, green: 0.31, blue: 0.43, alpha: 0.65))
            drawCentered(targetName, y: 946, font: .systemFont(ofSize: 70, weight: .black), color: UIColor(red: 0.35, green: 0.18, blue: 0.66, alpha: 1))
            if !wasCorrect, let guessedName {
                drawCentered("あなたの回答：\(guessedName)", y: 1030, font: .systemFont(ofSize: 30, weight: .bold), color: UIColor(red: 0.15, green: 0.10, blue: 0.25, alpha: 0.72))
            }

            drawCentered("\(questionCount) / 8 問で回答", y: 1155, font: .systemFont(ofSize: 42, weight: .heavy), color: .white)
            drawCentered("あなたも8問で見抜ける？", y: 1224, font: .systemFont(ofSize: 31, weight: .bold), color: UIColor.white.withAlphaComponent(0.82))
        }
    }

    private static func drawCentered(_ text: String, y: CGFloat, font: UIFont, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let measured = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: (1080 - measured.width) / 2, y: y), withAttributes: attributes)
    }
}

private struct ReportView: View {
    let game: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    var body: some View {
        NavigationStack {
            ZStack {
                OracleBackdrop()
                VStack(alignment: .leading, spacing: 16) {
                    OracleSheetHeader(title: "誤回答を報告", closeTitle: "キャンセル", close: { dismiss() })
                    VStack(alignment: .leading, spacing: 8) {
                        Text("表示された回答").font(.caption.bold()).foregroundStyle(OraclePalette.plum)
                        Text(game.reportQuestion?.question.text ?? "").font(.headline).foregroundStyle(OraclePalette.ink)
                        if let answer = game.reportQuestion?.answer { Label(answer.rawValue, systemImage: answer.symbol).font(.subheadline.bold()).foregroundStyle(answerColor(answer)) }
                    }.padding(16).background(OraclePalette.cream.opacity(0.96), in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("どこが違いましたか？").font(.caption.bold()).foregroundStyle(.white.opacity(0.75))
                        TextField("例：ガジェット使用時は該当する", text: $note, axis: .vertical).lineLimit(4...7).padding(14).foregroundStyle(OraclePalette.ink).background(OraclePalette.cream, in: RoundedRectangle(cornerRadius: 18))
                    }
                    Text("報告は端末内に保存され、外部には送信されません。").font(.caption).foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button { game.saveReport(note: note) } label: { Label("報告を保存", systemImage: "tray.and.arrow.down.fill").font(.headline).frame(maxWidth: .infinity).frame(height: 52) }
                        .buttonStyle(.plain).foregroundStyle(.white).background(OraclePalette.aqua, in: Capsule()).disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).opacity(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
                .padding(18)
            }.toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct DataInfoView: View {
    let ads: InterstitialAdManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                OracleBackdrop()
                VStack(spacing: 12) {
                    OracleSheetHeader(title: "データと判定基準", closeTitle: "閉じる", close: { dismiss() })
                    ScrollView {
                        VStack(spacing: 12) {
                            OracleInfoCard(title: "データベース", icon: "cylinder.split.1x2") {
                                OracleInfoRow(label: "キャラ数", value: "\(BrawlerDatabase.brawlers.count)")
                                OracleInfoRow(label: "確認日", value: BrawlerDatabase.verifiedAt)
                                OracleInfoRow(label: "質問数", value: "\(QuestionDatabase.all.count)")
                                OracleInfoRow(label: "整合性", value: QuestionDatabase.validationIssues().isEmpty ? "問題なし" : "要確認")
                            }
                            OracleInfoCard(title: "情報源", icon: "link") {
                                ForEach(BrawlerDatabase.sources) { source in
                                    Link(destination: source.url) { VStack(alignment: .leading, spacing: 3) { Text(source.title).font(.subheadline.bold()); Text("確認：\(source.checkedAt) ・ \(source.kindJapanese)").font(.caption).opacity(0.6) }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5) }.foregroundStyle(OraclePalette.ink)
                                }
                            }
                            OracleInfoCard(title: "判定方針", icon: "checklist") {
                                Text("完全に成立→「はい」、一切成立しない→「いいえ」、装備・状態など条件付き→「部分的にそう」。攻撃質問は通常攻撃、ウルト、派生攻撃、召喚物、設置物まで含めます。")
                                    .font(.subheadline).foregroundStyle(OraclePalette.ink).fixedSize(horizontal: false, vertical: true)
                            }
                            OracleInfoCard(title: "BGM", icon: "music.note") {
                                Text("Sylblanc")
                                    .font(.subheadline.bold()).foregroundStyle(OraclePalette.ink)
                                Text("音楽：PeriTune / むつき醒\n利用規約確認：2026-09-04")
                                    .font(.caption).foregroundStyle(OraclePalette.ink.opacity(0.62))
                                Link("楽曲ページ", destination: URL(string: "https://peritune.com/blog/2026/07/05/sylblanc/")!)
                                    .font(.subheadline.bold()).foregroundStyle(OraclePalette.plum)
                            }
                            OracleInfoCard(title: "非公式ファンコンテンツ", icon: "info.circle") {
                                Text("このアプリは非公式であり、Supercellによる承認を受けていません。")
                                Link("Supercell ファンコンテンツポリシー", destination: URL(string: "https://supercell.com/en/fan-content-policy/jp/")!).font(.subheadline.bold()).foregroundStyle(OraclePalette.plum)
                            }
                            if ads.privacyOptionsRequired {
                                OracleInfoCard(title: "広告のプライバシー", icon: "hand.raised.fill") {
                                    Button("プライバシー設定を開く") {
                                        Task { await ads.presentPrivacyOptions() }
                                    }
                                    .font(.subheadline.bold())
                                    .foregroundStyle(OraclePalette.plum)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }.toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct OracleBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            Image("OracleBackground").resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height + 120)
                .clipped().ignoresSafeArea()
        }
    }
}

private struct OracleSheetHeader: View {
    let title: String
    let closeTitle: String
    let close: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.title3.bold()).foregroundStyle(.white)
            Spacer()
            Button(closeTitle, action: close).font(.subheadline.bold()).foregroundStyle(.white).padding(.horizontal, 12).frame(height: 36).background(.white.opacity(0.14), in: Capsule())
        }
    }
}

private struct OracleInfoRow: View {
    let label: String
    let value: String
    var body: some View { HStack { Text(label).foregroundStyle(OraclePalette.ink.opacity(0.6)); Spacer(); Text(value).bold().foregroundStyle(OraclePalette.ink) }.font(.subheadline).padding(.vertical, 3) }
}

private struct OracleInfoCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    init(title: String, icon: String, @ViewBuilder content: () -> Content) { self.title = title; self.icon = icon; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(OraclePalette.plum)
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(OraclePalette.cream.opacity(0.96), in: RoundedRectangle(cornerRadius: 22))
    }
}

private func answerColor(_ answer: TernaryAnswer) -> Color { switch answer { case .yes: .green; case .no: .pink; case .partial: .orange } }

private extension DataSource {
    var kindJapanese: String {
        switch kind {
        case "official": "公式"
        case "communityGameData": "公開ゲームデータ"
        case "communityVerification": "コミュニティによる検証"
        default: "情報源"
        }
    }
}

#Preview { ContentView() }
