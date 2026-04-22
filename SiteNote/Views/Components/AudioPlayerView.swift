//
//  AudioPlayerView.swift
//  SiteNote
//
//  详情页的录音播放小部件。播放 / 暂停 / 显示时长。
//

import SwiftUI
import AVFoundation

/// AVAudioPlayer 的 @Observable 包装。控制播放状态 + 观察当前时间 / 总时长。
@MainActor
@Observable
final class AudioPlayerModel: NSObject {
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var loadFailed: Bool = false

    private var player: AVAudioPlayer?
    /// 用 cancellable Task 代替 Timer,避免 Swift 6 并发下的"unsafeForcedSync"警告/崩溃。
    private var progressTask: Task<Void, Never>?

    /// 加载一个本地音频文件。成功返回 `true`。
    @discardableResult
    func load(url: URL) -> Bool {
        do {
            // 配置播放音频会话（与录音的 .record 互斥，这里用 .playback）
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            loadFailed = false
            return true
        } catch {
            loadFailed = true
            return false
        }
    }

    func play() {
        player?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        isPlaying = false
        stopTimer()
    }

    private func startTimer() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                guard let self else { return }
                if Task.isCancelled { return }
                self.currentTime = self.player?.currentTime ?? 0
                if !self.isPlaying { return }
            }
        }
    }

    private func stopTimer() {
        progressTask?.cancel()
        progressTask = nil
    }
}

extension AudioPlayerModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // 委托回调是 nonisolated,跳回主线程时必须显式弱引用 self 避免 Swift 6 并发报错。
        Task { @MainActor [weak self] in
            self?.isPlaying = false
            self?.currentTime = 0
            self?.stopTimer()
        }
    }
}

/// 音频播放控件。播放/暂停按钮 + 进度文字。
struct AudioPlayerView: View {
    let audioRelativePath: String
    @State private var model = AudioPlayerModel()

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            Button {
                if model.isPlaying { model.pause() } else { model.play() }
            } label: {
                Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(model.loadFailed ? .gray : Color.accentColor)
            }
            .disabled(model.loadFailed)
            .accessibilityLabel(model.isPlaying ? "暂停录音" : "播放录音")

            VStack(alignment: .leading, spacing: 2) {
                Text("录音")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                if model.loadFailed {
                    Text("无法加载录音文件")
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(.red)
                } else {
                    Text("\(format(model.currentTime)) / \(format(model.duration))")
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.medium)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            guard let url = VoiceCaptureService.absoluteURL(forRelative: audioRelativePath) else {
                model.loadFailed = true
                return
            }
            _ = model.load(url: url)
        }
        .onDisappear {
            model.stop()
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
