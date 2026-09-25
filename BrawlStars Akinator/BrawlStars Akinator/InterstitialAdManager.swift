import Foundation
import GoogleMobileAds
import Observation
import UserMessagingPlatform

@MainActor @Observable
final class InterstitialAdManager: NSObject, FullScreenContentDelegate {
    private var interstitialAd: InterstitialAd?
    private var appOpenAd: AppOpenAd?
    private var appOpenAdLoadTime: Date?
    private var completion: (() -> Void)?
    private var onPresented: (() -> Void)?
    private var pendingAppOpenPresentation = false
    private var appOpenOnPresented: (() -> Void)?
    private var appOpenCompletion: (() -> Void)?
    private var isLoading = false
    private var isLoadingAppOpen = false
    private var isShowingFullScreenAd = false
    private var didStartAds = false
    private(set) var privacyOptionsRequired = false

    private static var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/4411468910"
        #else
        return "ca-app-pub-2277987033120510/8256072533"
        #endif
    }

    private static var appOpenAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/5575463023"
        #else
        return "ca-app-pub-2277987033120510/4619455136"
        #endif
    }

    func configure() {
        let parameters = RequestParameters()
        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await ConsentForm.loadAndPresentIfRequired(from: nil)
                privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
                startAdsIfAllowed()
            }
        }
    }

    func presentIfAvailable(onPresented: @escaping () -> Void, completion: @escaping () -> Void) -> Bool {
        guard !isShowingFullScreenAd, self.completion == nil, let interstitialAd else { return false }
        self.interstitialAd = nil
        self.onPresented = onPresented
        self.completion = completion
        isShowingFullScreenAd = true
        interstitialAd.present(from: nil)
        return true
    }

    func requestAppOpenPresentation(onPresented: @escaping () -> Void, completion: @escaping () -> Void) {
        guard !isShowingFullScreenAd else { return }
        pendingAppOpenPresentation = true
        appOpenOnPresented = onPresented
        appOpenCompletion = completion
        presentAppOpenIfPossible()
        if appOpenAd == nil, didStartAds {
            Task { await loadAppOpenAd() }
        }
    }

    func presentPrivacyOptions() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: nil)
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        startAdsIfAllowed()
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        isShowingFullScreenAd = true
        if ad is AppOpenAd {
            appOpenOnPresented?()
            appOpenOnPresented = nil
        } else {
            onPresented?()
            onPresented = nil
        }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if ad is AppOpenAd { finishAppOpenPresentation() }
        else { finishPresentation() }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        if ad is AppOpenAd { finishAppOpenPresentation() }
        else { finishPresentation() }
    }

    private func startAdsIfAllowed() {
        guard ConsentInformation.shared.canRequestAds else { return }
        if !didStartAds {
            didStartAds = true
            MobileAds.shared.start()
        }
        Task {
            await loadAd()
            await loadAppOpenAd()
        }
    }

    private func loadAd() async {
        guard !isLoading, interstitialAd == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let ad = try await InterstitialAd.load(with: Self.adUnitID, request: Request())
            ad.fullScreenContentDelegate = self
            interstitialAd = ad
        } catch {
            // Ads are optional. A load failure must never block navigation.
        }
    }

    private func loadAppOpenAd() async {
        guard !isLoadingAppOpen, appOpenAd == nil else {
            presentAppOpenIfPossible()
            return
        }
        isLoadingAppOpen = true
        defer { isLoadingAppOpen = false }
        do {
            let ad = try await AppOpenAd.load(with: Self.appOpenAdUnitID, request: Request())
            ad.fullScreenContentDelegate = self
            appOpenAd = ad
            appOpenAdLoadTime = Date()
            presentAppOpenIfPossible()
        } catch {
            // 起動広告を取得できなくても、アプリの利用は妨げない。
        }
    }

    private func presentAppOpenIfPossible() {
        guard pendingAppOpenPresentation, !isShowingFullScreenAd else { return }
        guard let appOpenAd, let loadTime = appOpenAdLoadTime,
              Date().timeIntervalSince(loadTime) < 4 * 60 * 60 else {
            self.appOpenAd = nil
            appOpenAdLoadTime = nil
            return
        }
        pendingAppOpenPresentation = false
        self.appOpenAd = nil
        appOpenAdLoadTime = nil
        isShowingFullScreenAd = true
        appOpenAd.present(from: nil)
    }

    private func finishPresentation() {
        isShowingFullScreenAd = false
        let action = completion
        completion = nil
        onPresented = nil
        action?()
        Task { await loadAd() }
    }

    private func finishAppOpenPresentation() {
        isShowingFullScreenAd = false
        let action = appOpenCompletion
        appOpenCompletion = nil
        appOpenOnPresented = nil
        action?()
        Task { await loadAppOpenAd() }
    }
}
