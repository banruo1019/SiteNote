//
//  VoiceCaptureService.swift
//  SiteNote
//
//  同时进行语音识别 + 原始音频落盘。一个按住手势完成 "说 → 文字 + 文件"。
//

import Foundation
import Speech
import AVFoundation

/// 语音捕获服务：按住录音期间同步完成流式转写 + 写 .m4a 文件。
///
/// 线程：本类绑定 `@MainActor`。转写回调已切回主线程。
///
/// 使用流程：
/// 1. 首次使用前调用 `requestPermissions()`。
/// 2. 按下：`startCapturing(onPartialResult:)`。回调会随发声持续触发。
/// 3. 松开：`stopCapturing()` 收尾，返回最终转写和音频文件相对路径。
///
/// 录音文件存在 App 的 Documents/audio/ 目录下，文件名 `<uuid>.m4a`。
@MainActor
final class VoiceCaptureService {

    /// 本服务可能抛出的错误。`errorDescription` 为面向用户的中文提示。
    enum VoiceError: LocalizedError {
        case notAuthorized
        case recognizerUnavailable
        case audioSessionFailed
        case fileWriteFailed

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "请在 iPhone 设置 → SiteNote 里允许「麦克风」和「语音识别」。"
            case .recognizerUnavailable:
                return "本机不支持中文语音识别。请检查系统是否已下载中文听写包。"
            case .audioSessionFailed:
                return "麦克风启动失败,请稍后再试。"
            case .fileWriteFailed:
                return "音频文件写入失败。"
            }
        }
    }

    /// 停止录音后的结果。
    struct CaptureResult {
        /// 语音识别的最终最佳结果。可能为空串（完全没识别到时）。
        let transcription: String
        /// 音频文件的相对路径（相对 Documents，例如 "audio/ABC.m4a"）。
        /// 文件为空或写入失败时为 `nil`。
        let audioRelativePath: String?
    }

    private var recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var audioFile: AVAudioFile?
    private var currentFileURL: URL?
    private var latestTranscription: String = ""

    init() {}

    /// 从用户设置里读取当前语言并构造 `SFSpeechRecognizer`。
    /// 每次 `startCapturing` 会调一次，保证设置变更即时生效。
    private func refreshRecognizer() {
        let localeId = UserDefaults.standard.string(forKey: "settings.speechLanguage") ?? "zh-CN"
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
    }

    /// 同时请求语音识别 + 麦克风权限。首次调用弹系统对话框。
    /// - Returns: 两项权限都拿到返回 `true`；任一被拒返回 `false`。
    static func requestPermissions() async -> Bool {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// 当前是否两项权限都已授予。
    static var hasAllPermissions: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioApplication.shared.recordPermission == .granted
    }

    /// 把相对路径转成绝对 URL（读取 / 播放时用）。
    /// - Parameter relative: 相对 Documents 的路径，如 "audio/abc.m4a"。
    /// - Returns: 绝对 URL；无法构造时为 `nil`。
    static func absoluteURL(forRelative relative: String) -> URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return docs.appendingPathComponent(relative)
    }

    /// 用另一种语言再次识别已保存的音频文件(任务 11:双语回退)。
    /// - Parameters:
    ///   - audioRelativePath: "audio/xxx.m4a" 相对路径。
    ///   - alternateLocale: 要尝试的 locale,如 "en-US"(当主识别是 zh-CN 时)。
    /// - Returns: 替代语言的转写;失败返回空串。
    static func retranscribe(
        audioRelativePath: String,
        alternateLocale: String
    ) async -> String {
        guard let url = absoluteURL(forRelative: audioRelativePath) else { return "" }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: alternateLocale))
        guard let recognizer, recognizer.isAvailable else { return "" }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return await withCheckedContinuation { cont in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let result, result.isFinal {
                    resumed = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    resumed = true
                    cont.resume(returning: "")
                }
            }
        }
    }

    /// 开始录音和识别。
    /// - Parameters:
    ///   - onPartialResult: 识别更新时回调(主线程)。
    ///   - onAudioLevel: 每个音频 buffer 的 RMS 电平(0-1),主线程,可为 nil。
    ///     用于渲染实时波形。
    /// - Throws: 见 `VoiceError`。
    func startCapturing(
        onPartialResult: @escaping @MainActor (String) -> Void,
        onAudioLevel: (@MainActor (Float) -> Void)? = nil
    ) throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        latestTranscription = ""

        refreshRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw VoiceError.audioSessionFailed
        }

        // 准备 .m4a 输出文件
        let fileURL: URL
        do {
            fileURL = try prepareAudioFileURL()
        } catch {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw VoiceError.fileWriteFailed
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // AVAudioFile 会把 PCM 输入自动转码为 AAC 写入 .m4a
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: recordingFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: fileSettings)
        } catch {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw VoiceError.fileWriteFailed
        }
        currentFileURL = fileURL

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        // 捕获时 self 被 nonisolated tap 闭包使用，需用弱引用/nonisolated 隔离
        let fileRef = self.audioFile
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
            try? fileRef?.write(from: buffer)

            if let onAudioLevel {
                let level = Self.computeRMS(buffer: buffer)
                Task { @MainActor in
                    onAudioLevel(level)
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.audioFile = nil
            currentFileURL = nil
            try? FileManager.default.removeItem(at: fileURL)
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw VoiceError.audioSessionFailed
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let transcription = result.bestTranscription.formattedString
            Task { @MainActor in
                self?.latestTranscription = transcription
                onPartialResult(transcription)
            }
        }
    }

    /// 停止录音并收尾。幂等。
    /// - Returns: 最终转写 + 音频文件相对路径。
    func stopCapturing() -> CaptureResult {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.finish()
        recognitionTask = nil

        let relativePath: String?
        if let url = currentFileURL {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if size > 0 {
                relativePath = "audio/\(url.lastPathComponent)"
            } else {
                try? FileManager.default.removeItem(at: url)
                relativePath = nil
            }
        } else {
            relativePath = nil
        }

        audioFile = nil
        currentFileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let result = CaptureResult(
            transcription: latestTranscription,
            audioRelativePath: relativePath
        )
        latestTranscription = ""
        return result
    }

    /// 计算一个 PCM buffer 的 RMS 电平,归一化到 0-1 区间。
    /// 用于实时波形显示。不是精确响度,只为视觉反馈。
    private static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        // 对数缩放到 0-1,让小声音也看得见 bar
        let boosted = min(1.0, rms * 12)
        return boosted
    }

    /// 在 Documents/audio 下生成一个新文件的 URL，确保目录存在。
    private func prepareAudioFileURL() throws -> URL {
        let docsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let audioDir = docsURL.appendingPathComponent("audio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: audioDir.path) {
            try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        }
        let filename = "\(UUID().uuidString).m4a"
        return audioDir.appendingPathComponent(filename)
    }
}
