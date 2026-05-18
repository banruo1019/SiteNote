//
//  VoiceCaptureService.swift
//  SiteNote
//
//  同时进行语音识别 + 原始音频落盘。一个按住手势完成 "说 → 文字 + 文件"。
//

import Foundation
import Speech
import AVFoundation
import SwiftData

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
                return String(localized: "请在 iPhone 设置 → SiteNote 里允许「麦克风」和「语音识别」。", locale: AppLanguageManager.currentLocale)
            case .recognizerUnavailable:
                return String(localized: "本机不支持中文语音识别。请检查系统是否已下载中文听写包。", locale: AppLanguageManager.currentLocale)
            case .audioSessionFailed:
                return String(localized: "麦克风启动失败,请稍后再试。", locale: AppLanguageManager.currentLocale)
            case .fileWriteFailed:
                return String(localized: "音频文件写入失败。", locale: AppLanguageManager.currentLocale)
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
        /// E1.4:识别期间 recognizer 抛 error(突然 unavailable / 内部错误)→ true。
        /// HomeViewModel 看到 true 时给用户一个提示:音频已保留,但识别引擎挂了。
        let recognitionFailed: Bool
    }

    private var recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var audioFile: AVAudioFile?
    private var currentFileURL: URL?
    private var latestTranscription: String = ""
    /// E1.4:recognitionTask 回调收到 error 时置 true。stopCapturing 把它带到结果里。
    /// 录制中识别引擎抽风(unavailable / network 中断 on-device fail-back / 系统 bug)
    /// → callback 不再 fire → latestTranscription 为空 → 用户看不到任何反馈。
    /// 拿这个标记走错误路径,而不是默默吞。
    private var recognitionFailed: Bool = false

    /// 录音中是否被系统(来电/Siri/闹钟)或路由变更(AirPods 拔掉)打断的回调。
    /// 在 startCapturing 时由调用方设置,中断发生时主线程触发。
    var onInterruption: (@MainActor () -> Void)?

    /// 当前是否正在录音(audioEngine 运行中)。用于防御重复 startCapturing。
    var isRecording: Bool { audioEngine.isRunning }

    /// 已注册的中断 / 路由变更观察者。stopCapturing 时反注册。
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    init() {}

    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

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
        // 双语回退也走同一份行业词典(英文 locale 也吃中英混词,提升识别)。
        request.contextualStrings = JargonDictionary.contextualStrings()

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
        // B5 防御:已经在录音再次进入说明状态机错乱(比如 1.5s 内连按两次)。
        // 抛错让 HomeViewModel 走错误路径,不要去碰 audioEngine.start 第二次。
        guard !audioEngine.isRunning else {
            throw VoiceError.audioSessionFailed
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        latestTranscription = ""
        recognitionFailed = false

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
        // 关键:把行业词典塞给 STT 做 prior。会强烈偏向这些词,显著提升识别准确率。
        // 词典 = 静态 baseline(107 词)+ 用户工地名/分类/模板/条款 + 用户自定义专业词汇。
        // Apple 限制:每条 ≤30 字符,数组总 ≤50KB。JargonDictionary 内部已过滤。
        request.contextualStrings = JargonDictionary.contextualStrings()
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
            // P1 #197:audioEngine.start 失败的清理路径必须释放所有已分配资源,
            // 否则 recognitionRequest / audioFile 残留 → 下次 startCapturing 时 refreshRecognizer
            // 覆盖前会撞一阵 leak,以及 audioFile 持有的临时文件句柄不释放。
            inputNode.removeTap(onBus: 0)
            self.audioFile = nil
            currentFileURL = nil
            recognitionRequest = nil           // 清识别 request,避免悬空持有 buffers
            try? FileManager.default.removeItem(at: fileURL)
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw VoiceError.audioSessionFailed
        }

        // E1.4:不再忽略 error。识别期间 recognizer 抽风时 callback 收到 error,
        // 我们把 recognitionFailed 置 true,stopCapturing 通过结果 surface 给上层。
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let error {
                // 收到 error 一般意味着这次任务已经废掉,后续不会再 fire。
                // 标记失败让 stopCapturing 能区分"用户没说话"和"识别引擎挂了"。
                Task { @MainActor in
                    self?.recognitionFailed = true
                }
                print("[SiteNote] STT recognitionTask error: \(error.localizedDescription)")
                return
            }
            guard let result else { return }
            let transcription = result.bestTranscription.formattedString
            Task { @MainActor in
                self?.latestTranscription = transcription
                onPartialResult(transcription)
            }
        }

        registerInterruptionObservers()
    }

    /// 注册 AVAudioSession 中断 / 路由变更观察者。系统中断会停 audioEngine
    /// 但不会重置我们的状态,所以必须主动收尾,否则 isRecording 永远卡 true。
    private func registerInterruptionObservers() {
        // 先反注册旧的(防御性,正常路径里 stopCapturing 已清掉)
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }

        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
                return
            }
            if type == .began {
                Task { @MainActor [weak self] in
                    self?.handleInterruption()
                }
            }
        }

        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else {
                return
            }
            // 只处理设备拔出(老设备不可用):AirPods 拔掉、有线耳机拔掉。
            // 其他类型(.newDeviceAvailable / .categoryChange)系统会自动衔接,不必中断。
            if reason == .oldDeviceUnavailable {
                Task { @MainActor [weak self] in
                    self?.handleInterruption()
                }
            }
        }
    }

    /// 收到中断:主动停录、清状态、回调 HomeViewModel。
    /// 与 stopCapturing 的差别:我们不返回 CaptureResult,因为 RecordView
    /// 的"按住松开"语义已经被破坏,只能丢弃。但音频文件 / partial 已经写到这里,
    /// HomeViewModel 决定怎么呈现。
    @MainActor
    private func handleInterruption() {
        guard audioEngine.isRunning else { return }
        _ = stopCapturing()
        onInterruption?()
    }

    /// 停止录音并收尾。幂等。
    /// - Returns: 最终转写 + 音频文件相对路径。
    func stopCapturing() -> CaptureResult {
        // 反注册中断观察者(B1)。即使 audioEngine 没在跑也要清,handleInterruption
        // 进来后 stopCapturing 会再调一次 stop()——必须保证幂等。
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }

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

        // E1.4:把失败标记带出去——同时只在转写为空且失败时才视为真失败,
        // 因为 SFSpeechRecognitionTask 在已经吐出 final 之后再报 error 也是常见的(任务收尾正常路径),
        // 那种情况 latestTranscription 非空,不应该当失败。
        let failed = recognitionFailed && latestTranscription.isEmpty
        let result = CaptureResult(
            transcription: latestTranscription,
            audioRelativePath: relativePath,
            recognitionFailed: failed
        )
        latestTranscription = ""
        recognitionFailed = false
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

    /// 启动孤儿 .m4a 清理(B2)。
    ///
    /// 录音过程中 App 被杀,`stopCapturing` 不会调,文件永久留在 Documents/audio/。
    /// 启动时扫一遍:删除 mtime 早于 1 小时前 **且** 没有任何 Note 引用其文件名的文件。
    /// 1 小时门槛避免误删:正在录的音频或刚保存还没 commit 的 fly。
    ///
    /// 同步执行,失败静默不阻塞启动。在 `RootContainerView.initContainer` 成功后调。
    static func cleanupOrphanAudio(modelContext: ModelContext) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let audioDir = docs.appendingPathComponent("audio", isDirectory: true)
        guard fm.fileExists(atPath: audioDir.path) else { return }

        // 拉所有还活着的 Note 的 audioFilePath。集合查可以 O(1) 命中。
        let descriptor = FetchDescriptor<Note>()
        let referenced: Set<String>
        do {
            let allNotes = try modelContext.fetch(descriptor)
            referenced = Set(allNotes.compactMap { $0.audioFilePath })
        } catch {
            // SwiftData 拉不出来就放弃 GC,不要冒险删任何文件。
            print("[SiteNote] cleanupOrphanAudio: 读 Note 失败,跳过. \(error.localizedDescription)")
            return
        }

        let cutoff = Date().addingTimeInterval(-3600) // 1 小时前
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: audioDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            print("[SiteNote] cleanupOrphanAudio: 列目录失败. \(error.localizedDescription)")
            return
        }

        var deleted = 0
        for fileURL in contents {
            guard fileURL.pathExtension.lowercased() == "m4a" else { continue }
            let relative = "audio/\(fileURL.lastPathComponent)"
            if referenced.contains(relative) { continue }

            let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            guard mtime < cutoff else { continue }

            do {
                try fm.removeItem(at: fileURL)
                deleted += 1
            } catch {
                print("[SiteNote] cleanupOrphanAudio: 删除失败 \(fileURL.lastPathComponent). \(error.localizedDescription)")
            }
        }
        if deleted > 0 {
            print("[SiteNote] cleanupOrphanAudio: 清理 \(deleted) 个孤儿 .m4a")
        }
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
