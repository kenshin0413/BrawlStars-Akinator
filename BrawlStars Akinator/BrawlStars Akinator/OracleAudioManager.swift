import AVFoundation
import AudioToolbox
import Observation
import UIKit

@MainActor @Observable
final class OracleAudioManager {
    private(set) var isEnabled: Bool
    private var player: AVAudioPlayer?

    init() {
        isEnabled = UserDefaults.standard.object(forKey: "oracleBGMEnabled") as? Bool ?? true
        if isEnabled { start() }
    }

    func toggle() {
        isEnabled.toggle()
        UserDefaults.standard.set(isEnabled, forKey: "oracleBGMEnabled")
        isEnabled ? start() : stop()
    }

    func pauseForAd() {
        player?.pause()
    }

    func resumeAfterAd() {
        if isEnabled { player?.play() }
    }

    func playCountdownTick(secondsRemaining: Int) {
        guard isEnabled, (0...10).contains(secondsRemaining) else { return }
        AudioServicesPlaySystemSound(secondsRemaining == 0 ? 1053 : 1104)
        if secondsRemaining <= 3 {
            let feedback = UIImpactFeedbackGenerator(style: secondsRemaining == 0 ? .heavy : .medium)
            feedback.prepare()
            feedback.impactOccurred()
        }
    }

    private func start() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            if player == nil {
                guard let url = Bundle.main.url(forResource: "PeriTune_Sylblanc_loop", withExtension: "mp3") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer.numberOfLoops = -1
                audioPlayer.volume = 0.26
                audioPlayer.prepareToPlay()
                player = audioPlayer
            }
            player?.play()
        } catch {
            // BGM must never prevent the game from starting.
            isEnabled = false
        }
    }

    private func stop() {
        player?.stop()
        player?.currentTime = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
