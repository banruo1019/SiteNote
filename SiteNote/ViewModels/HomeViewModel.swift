//
//  HomeViewModel.swift
//  SiteNote
//
//  Phase 9 架构重构:首页录音协调器。
//  新模式:录音/拍照完成后立即保存(用默认/推断值),3 秒 toast 可撤销/改隐患/进细记。
//

import Foundation
import SwiftData
import UIKit
import Observation

/// 最近一次保存的快照——供 UndoToast 撤销。
struct LastSaveSnapshot {
    let noteID: UUID
    let summary: String
    /// 上次保存时一并落盘的相对路径,如果撤销要一起删掉。
    let audioRelativePath: String?
    let photoRelativePaths: [String]
}

/// 录音+拍照的业务协调器。
@MainActor
@Observable
final class HomeViewModel {
    private(set) var isRecording: Bool = false
    var partialTranscription: String = ""
    /// 实时音量(0-1),供 RecordView 波形动画用。录音中 VoiceCaptureService 喂入,停录时归零。
    var currentAudioLevel: Float = 0

    /// 最近一次保存的 note 快照。非空时 UndoToast 显示。
    var lastSave: LastSaveSnapshot?
    /// UndoToast 倒计时秒数(3→0)。0 时 UI 自动隐藏。
    var undoSecondsRemaining: Int = 0

    /// 拍照流程暂存的照片(按顺序)。按住录音时如有,会一起保存为同一条 note。
    var stagedPhotos: [UIImage] = []

    var errorMessage: String?
    /// E1.6:权限被永久拒绝时设 true,RecordView 的 alert 会多出"打开设置"按钮。
    /// 任意一次 errorMessage = nil 会把它一起复位。
    var showsPermissionSettingsButton: Bool = false

    private var modelContext: ModelContext?
    /// 录音开始时间。RecordView 的 TimelineView 用它驱动 mm:ss 计时器。
    /// commit 时清空,UI 自动隐藏计时。
    private(set) var recordingStartTime: Date?
    private var undoTask: Task<Void, Never>?

    /// B3:每个保存的 note 对应的所有 AI enrich Task 句柄。用 noteID(UUID)做 key。
    /// undoLastSave / convertLastSaveToDiary 删 note 前先 cancel 对应 Task,
    /// 避免 AI 回写已撤销的 note。Task 完成时移除自己。
    /// 数组允许同一 note 有多个并行 Task(commit AI 链 + 后台 enrich)。
    private var enrichTasks: [UUID: [Task<Void, Never>]] = [:]

    /// B5:防快速重按。stopAndSave 入口设 true,await 完成后 false。
    /// startRecording 入口判这个,防止 1.5s 内连按两次 mic 让 audioEngine 状态机错乱。
    private var isProcessingStop: Bool = false

    /// F5 (R2-P2-20):录音超时哨兵。startRecording 启动时 sleep maxRecordingDuration,
    /// 到点还在录就强制 stopAndSave。stopAndSave 入口取消它。
    /// 用户口袋误触按住 mic 几分钟会产生超大音频,提前止血。
    private var maxDurationGuard: Task<Void, Never>?

    /// F5:录音 hard cap = 3 分钟。超过自动停录并提示用户。
    /// 真实速记一般 < 30 秒,30 秒-3 分钟 = 描述性长录,3 分钟以上几乎可断定误触。
    private let maxRecordingDuration: TimeInterval = 180

    private let voice = VoiceCaptureService()
    private let location = LocationService()
    private let weather = WeatherService()

    private let minRecordingDuration: TimeInterval = 0.5
    /// Undo toast 倒计时总秒数。加长到 5 秒是为了工地戴手套用户有足够时间反应。
    private let undoSeconds = 5

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        // B1:语音服务被系统(来电/Siri/闹钟/AirPods 拔掉)中断时,
        // 主动通知 ViewModel 重置状态 + 给用户提示。
        voice.onInterruption = { [weak self] in
            self?.handleVoiceInterruption()
        }
    }

    /// B1:VoiceCaptureService 检测到 AVAudioSession 中断时的回调。
    /// 此时 audioEngine 已被服务自己 stopCapturing 收尾,这里只需重置 ViewModel 状态。
    /// 已经写到此刻的 partial 转写和音频文件被丢弃——session 中断后接续无意义。
    private func handleVoiceInterruption() {
        guard isRecording else { return }
        isRecording = false
        currentAudioLevel = 0
        partialTranscription = ""
        recordingStartTime = nil
        isProcessingStop = false
        // F5:中断路径同样清掉超时哨兵,避免悬挂 Task 在已停录后再 stopAndSave。
        maxDurationGuard?.cancel()
        maxDurationGuard = nil
        errorMessage = String(localized: "录音被来电/Siri 等打断,本次录音未保存。请重新录。", locale: AppLanguageManager.currentLocale)
    }

    // MARK: - 录音

    func startRecording() {
        // B5:上一轮 stopAndSave 还没跑完(commit + AI Task 启动期间),
        // 这时再按 mic 会让 audioEngine 状态机错乱。直接 bail。
        if isProcessingStop { return }
        // 已经在录音中重复 start 也直接 bail——VoiceCaptureService.startCapturing
        // 头部的 guard 也会兜住,但这里早 return 不浪费精力。
        if isRecording { return }

        // P2 改:延后权限请求。首次按下时如未授权,弹系统对话框;授权决定前先 bail,
        // 用户授予后再次按下才真正录。已永久拒绝则给提示引导去 设置。
        guard VoiceCaptureService.hasAllPermissions else {
            Task { [weak self] in
                let granted = await VoiceCaptureService.requestPermissions()
                if !granted {
                    await MainActor.run {
                        // E1.6:被拒后 alert 给"打开设置"快速入口。
                        self?.showsPermissionSettingsButton = true
                        self?.errorMessage = String(localized: "需要麦克风和语音识别权限。请到 设置 → SiteNote 打开。", locale: AppLanguageManager.currentLocale)
                    }
                }
            }
            return
        }
        partialTranscription = ""
        dismissUndoToast()
        recordingStartTime = Date()

        do {
            try voice.startCapturing(
                onPartialResult: { [weak self] partial in
                    self?.partialTranscription = partial
                },
                onAudioLevel: { [weak self] level in
                    self?.currentAudioLevel = level
                }
            )
            isRecording = true

            // F5 (R2-P2-20):启动超时哨兵。3 分钟到点还在录 → 强制结束 + 提示。
            // 注意:stopAndSave 入口会 cancel 这个 Task,正常松手不会触发。
            maxDurationGuard?.cancel()
            let cap = maxRecordingDuration
            maxDurationGuard = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(cap * 1_000_000_000))
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let self else { return }
                    guard self.isRecording else { return }
                    self.errorMessage = String(
                        localized: "录音已自动结束(超过 3 分钟)。",
                        locale: AppLanguageManager.currentLocale
                    )
                }
                // 在主线程触发自动收尾(stopAndSave 是 async 主线程方法)。
                await self?.stopAndSave()
            }
        } catch let error as VoiceCaptureService.VoiceError {
            errorMessage = error.errorDescription
            recordingStartTime = nil
        } catch {
            errorMessage = error.localizedDescription
            recordingStartTime = nil
        }
    }

    /// 松开录音:立即保存(含已暂存照片)。不再弹 DeadlineSheet。
    ///
    /// **延迟优化**:松手后立即 commit(用 partial + 缓存的上次位置),
    /// 真定位/天气/双语回退/AI polish 全部走后台 Task 补齐。
    /// 用户看到 undo toast 几乎无延迟。
    func stopAndSave() async {
        // B5:进入门闸,等 commitDirectly 启完 AI Task 后才放下一轮 startRecording。
        isProcessingStop = true
        defer { isProcessingStop = false }

        // F5:取消超时哨兵——正常松手停录无需让它再起作用。
        maxDurationGuard?.cancel()
        maxDurationGuard = nil

        let capturedAt = Date()
        let duration = recordingStartTime.map { capturedAt.timeIntervalSince($0) } ?? 0
        recordingStartTime = nil

        let result = voice.stopCapturing()
        isRecording = false
        currentAudioLevel = 0

        if duration < minRecordingDuration {
            if let path = result.audioRelativePath,
               let url = VoiceCaptureService.absoluteURL(forRelative: path) {
                try? FileManager.default.removeItem(at: url)
            }
            partialTranscription = ""
            return
        }

        let initialTranscription = result.transcription
        partialTranscription = initialTranscription

        // E1.4:STT 引擎抽风(突然 unavailable / 内部 error)→ result.recognitionFailed = true。
        // 给用户提示:音频已保留可重试,而不是默默吞掉 30 秒录音。
        // 还是会 commit 这条 note(transcription 空,但 audio 有),
        // 用户在详情页可以点"重新识别"或自己改字。
        if result.recognitionFailed {
            errorMessage = String(
                localized: "识别引擎抽风,音频已保留,请稍后再分析或手动输入。",
                locale: AppLanguageManager.currentLocale
            )
        }

        // 用上次成功的位置做占位(瞬时,不等网络)。真定位/天气在后台补。
        let cachedLoc = LocationService.lastSuccessfulLocation()

        // 中文日期解析,猜不出则 inbox 待分类。
        let suggested = ChineseDateParser.parseDeadline(from: initialTranscription)
        let deadline: Deadline = suggested ?? .inbox

        let photos = stagedPhotos
        stagedPhotos = []

        commitDirectly(
            capturedAt: capturedAt,
            transcription: initialTranscription,
            audioRelativePath: result.audioRelativePath,
            location: cachedLoc,
            isLocationFallback: cachedLoc != nil,
            weather: nil,
            deadline: deadline,
            photos: photos,
            siteTag: nil,
            isHazard: false,
            templateName: nil,
            checkedItems: [],
            contractClauseRef: nil,
            floorPlanRef: nil,
            floorPlanX: nil,
            floorPlanY: nil
        )

        // 后台补齐:双语回退转写 / 实时 GPS / 天气。
        guard let noteID = lastSave?.noteID else { return }
        let audioPath = result.audioRelativePath
        // B3:把后台 enrich Task 加进 enrichTasks[noteID] 数组,撤销时能一起 cancel。
        // 显式 Task<Void, Never>:`self?.method()` 返回 Void? 会让闭包推断为 Task<Void?, Never>,
        // 塞不进 `[Task<Void, Never>]`。手动 guard let self,Task 的返回类型就是 Void。
        let bgTask: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.enrichNoteAfterCommit(
                noteID: noteID,
                audioPath: audioPath,
                initialTranscription: initialTranscription,
                usedCachedLocation: cachedLoc != nil
            )
        }
        enrichTasks[noteID, default: []].append(bgTask)
    }

    /// 后台补齐:双语回退转写、实时 GPS、天气。失败静默降级。
    /// E1.3:严格串行——双语回退 → polish。回退失败时不动 transcription,
    /// commitDirectly 里那条 polish Task 自己负责把 polish 应用上去(基于原文)。
    /// 双语回退成功时,对替代语言识别结果再做一次 polish 并写回。
    private func enrichNoteAfterCommit(
        noteID: UUID,
        audioPath: String?,
        initialTranscription: String,
        usedCachedLocation: Bool
    ) async {
        // 双语回退(E1.5:加了语言判定,只接受 dominant 语言匹配的回退结果)
        var improvedTranscription: String? = nil
        if let audioPath,
           ChineseDateParser.transcriptionLikelyWrongLanguage(initialTranscription) {
            let primary = UserDefaults.standard.string(forKey: SettingsKeys.speechLanguage) ?? "zh-CN"
            let alt = primary == "zh-CN" ? "en-US" : "zh-CN"
            let altResult = await VoiceCaptureService.retranscribe(
                audioRelativePath: audioPath,
                alternateLocale: alt
            )
            // E1.5:只看长度会被英文回退把中文音节解成长串英文垃圾骗过。
            // 用 NSLinguisticTagger 判主语言,只在主语言与目标语言匹配时采纳。
            if Self.shouldAcceptAlternateTranscription(
                altResult: altResult,
                originalResult: initialTranscription,
                expectedLocale: alt
            ) {
                improvedTranscription = altResult
            }
        }

        // 实时 GPS
        let freshLoc = try? await location.getCurrentLocation()

        // 天气
        var weatherInfo: WeatherService.Weather?
        if let freshLoc {
            weatherInfo = try? await weather.fetch(
                latitude: freshLoc.latitude,
                longitude: freshLoc.longitude
            )
        }

        updateNoteEnrichment(
            noteID: noteID,
            transcription: improvedTranscription,
            location: freshLoc,
            weather: weatherInfo
        )

        // 如果双语回退改写了转写,重新跑一次 AI polish(commitDirectly 里那次是基于旧转写)。
        // E1.3:严格串行——上面 await 已经完成 GPS / 天气写入,这里再 await polish。
        // Engineer:全面禁 AI(包括双语重试 polish)。
        if let improvedTranscription {
            let isEngineer = await MainActor.run { UserProfileManager.shared.current == .engineer }
            let aiEnabled = !isEngineer && AIToggle.featureEnabled(SettingsKeys.aiPolishEnabled)
            if aiEnabled, !improvedTranscription.isEmpty {
                do {
                    let polished = try await AIService.shared.polishTranscription(improvedTranscription)
                    if polished != improvedTranscription {
                        applyPolishedTranscription(noteID: noteID, polished: polished)
                    }
                } catch {
                    #if DEBUG
                    print("[SiteNote] AI polish (bilingual retry) failed: \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }

    /// E1.5:判断双语回退结果是否值得采纳。
    /// 只看长度 (`altResult.count > original.count`) 会被以下情况骗过:
    /// 把中文音节强行解成英文长串("nihao" → "knee how" 之类),字数变多但内容是垃圾。
    /// 用 NSLinguisticTagger 判 dominant language;若与目标 locale 匹配才采纳。
    static func shouldAcceptAlternateTranscription(
        altResult: String,
        originalResult: String,
        expectedLocale: String
    ) -> Bool {
        let trimmed = altResult.trimmingCharacters(in: .whitespacesAndNewlines)
        // 太短 / 比原文还短 → 直接拒。
        guard trimmed.count >= 4, trimmed.count > originalResult.count else { return false }

        let tagger = NSLinguisticTagger(tagSchemes: [.language], options: 0)
        tagger.string = trimmed
        let dominant = tagger.dominantLanguage ?? ""
        // expectedLocale 形如 "en-US" / "zh-CN"。取前两位主语言码。
        let expectedPrefix = String(expectedLocale.prefix(2)).lowercased()
        let dominantPrefix = String(dominant.prefix(2)).lowercased()
        // zh / yue 都算中文。
        if expectedPrefix == "zh" {
            return dominantPrefix == "zh" || dominant.lowercased().hasPrefix("yue")
        }
        return dominantPrefix == expectedPrefix
    }

    /// 把后台拿到的更准字段写回已保存的 note。若 note 已被撤销就无操作。
    private func updateNoteEnrichment(
        noteID: UUID,
        transcription: String?,
        location: LocationService.Location?,
        weather: WeatherService.Weather?
    ) {
        // B3:Task 已被撤销路径取消的话直接 bail。
        if Task.isCancelled { return }
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == noteID })
        guard let note = try? ctx.fetch(descriptor).first else { return }
        // B3:note 已被撤销(soft delete)也不写。
        guard note.deletedAt == nil else { return }

        if let transcription {
            // E1.3:双语回退采纳时,只覆盖 `transcription`(可编辑/AI 改写层)。
            // `transcriptionOriginal` 是 STT 第一遍的法律/证据层,Note.init 已经写过,
            // 这里**不再触碰**——保留"原文"按钮里能看到原始 STT。
            note.transcription = transcription
        }
        if let location {
            note.latitude = location.latitude
            note.longitude = location.longitude
            note.locationAddress = location.address
        }
        if let weather {
            note.weatherSummary = weather.summary
            note.temperatureCelsius = weather.temperature
            note.weatherCode = weather.code
        }
        try? ctx.save() // B6:落盘后台 enrich 字段。
    }

    // MARK: - 拍照

    /// 加一张刚拍/选完的照片到暂存区。
    func stagePhoto(_ image: UIImage) {
        stagedPhotos.append(image)
    }

    /// 把暂存照片直接保存为 photo-only note。
    func savePhotosOnly() {
        let photos = stagedPhotos
        guard !photos.isEmpty else { return }
        stagedPhotos = []

        Task {
            // 先试实时定位,失败再回退到上次位置。明确记录是否回退,避免重复调用。
            let primary = try? await location.getCurrentLocation()
            let loc: LocationService.Location? = primary ?? LocationService.lastSuccessfulLocation()
            let isFallback = primary == nil && loc != nil

            var weatherInfo: WeatherService.Weather?
            if let loc {
                weatherInfo = try? await weather.fetch(
                    latitude: loc.latitude,
                    longitude: loc.longitude
                )
            }

            commitDirectly(
                capturedAt: Date(),
                transcription: "",
                audioRelativePath: nil,
                location: loc,
                isLocationFallback: isFallback,
                weather: weatherInfo,
                deadline: .inbox,
                photos: photos,
                siteTag: nil,
                isHazard: false,
                templateName: nil,
                checkedItems: [],
                contractClauseRef: nil,
                floorPlanRef: nil,
                floorPlanX: nil,
                floorPlanY: nil
            )
        }
    }

    /// 丢弃所有暂存照片(用户反悔)。
    func clearStagedPhotos() {
        stagedPhotos = []
    }

    /// 从暂存区移除单张照片。越界时静默忽略。
    func removeStagedPhoto(at index: Int) {
        guard stagedPhotos.indices.contains(index) else { return }
        stagedPhotos.remove(at: index)
    }

    // MARK: - Undo toast 操作

    /// 撤销最近一次保存(删 note + 文件)。
    func undoLastSave() {
        guard let snapshot = lastSave, let ctx = modelContext else { return }
        let id = snapshot.noteID

        // B3:先取消所有还在跑的 AI enrich Task,避免它们 fetch 到已删/未删的瞬态写回。
        cancelEnrichTasks(for: id)

        let descriptor = FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == id })
        if let matches = try? ctx.fetch(descriptor), let note = matches.first {
            NotificationService.shared.cancel(for: note)
            ctx.delete(note)
            try? ctx.save() // B6:撤销立刻落盘,防止 AI Task 漏判 deletedAt。
        }

        if let audioPath = snapshot.audioRelativePath,
           let url = VoiceCaptureService.absoluteURL(forRelative: audioPath) {
            try? FileManager.default.removeItem(at: url)
        }
        for photoPath in snapshot.photoRelativePaths {
            if let url = PhotoStorage.absoluteURL(forRelative: photoPath) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        dismissUndoToast()
    }

    /// UndoToast 上用户点 🚨 标隐患后调用:把 note.isHazard 置 true,重排推送(hazard schedule),关 toast。
    func markLastSaveAsHazard() {
        guard let snapshot = lastSave, let ctx = modelContext else { return }
        let id = snapshot.noteID
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == id })
        if let note = try? ctx.fetch(descriptor).first {
            note.isHazard = true
            try? ctx.save() // B6:用户主动操作的字段必须立即落盘。
            NotificationService.shared.schedule(for: note)
        }
        dismissUndoToast()
    }

    // v1.2 大减负:convertLastSaveToDiary() 已删 —— 日志模式整体下架。

    /// 用户点 toast 顶行时调用:返回当前已保存的 note,让 RecordView 跳详情页。
    /// 注意:不再删除 note,不再弹 DeadlineSheet。详情页里用户自己改。
    /// 调用方应在 append 到 navigation path 之后,再调 `dismissUndoToast()` 关掉 toast。
    func fetchLastSavedNote() -> Note? {
        guard let snapshot = lastSave, let ctx = modelContext else { return nil }
        let id = snapshot.noteID
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == id })
        return try? ctx.fetch(descriptor).first
    }

    /// 让 UI 可以从外部关闭 toast(比如跳详情页前先关)。
    func dismissToastManually() {
        dismissUndoToast()
    }

    // MARK: - 核心 commit

    private func commitDirectly(
        capturedAt: Date,
        transcription: String,
        audioRelativePath: String?,
        location: LocationService.Location?,
        isLocationFallback: Bool,
        weather: WeatherService.Weather?,
        deadline: Deadline,
        photos: [UIImage],
        siteTag: String?,
        isHazard: Bool,
        templateName: String?,
        checkedItems: [String],
        contractClauseRef: String?,
        floorPlanRef: String? = nil,
        floorPlanX: Double? = nil,
        floorPlanY: Double? = nil
    ) {
        let photoPaths = PhotoStorage.save(photos)

        let note = Note(
            transcription: transcription,
            createdAt: capturedAt,
            deadline: deadline,
            dueDate: deadline.dueDate(from: capturedAt),
            audioFilePath: audioRelativePath,
            photoPaths: photoPaths,
            latitude: location?.latitude,
            longitude: location?.longitude,
            locationAddress: location?.address,
            weatherSummary: weather?.summary,
            temperatureCelsius: weather?.temperature,
            weatherCode: weather?.code,
            siteTag: siteTag,
            isHazard: isHazard,
            templateName: templateName,
            checkedItems: checkedItems,
            contractClauseRef: contractClauseRef,
            floorPlanRef: floorPlanRef,
            floorPlanX: floorPlanX,
            floorPlanY: floorPlanY
        )
        modelContext?.insert(note)
        // B6:insert 后立刻显式落盘。autosave 也会落,但同 task 的 polish 一秒后回来
        // 改这条 note,在 autosave 触发前 app 被挂起 → polish 改动丢失。显式 save 缩短脏窗口。
        try? modelContext?.save()
        NotificationService.shared.schedule(for: note)

        // GPS 学习:若保存时已有 siteTag + 坐标,把这条样本喂给 centroid。
        // Phase A 用这个数据推荐工地(用户不标也能学到常去的地方)。
        if let siteTag, let lat = location?.latitude, let lng = location?.longitude {
            SiteCentroidsStorage.observe(siteName: siteTag, latitude: lat, longitude: lng)
        }

        #if DEBUG
        print("""
        [SiteNote] Committed note:
          transcription: \(transcription.isEmpty ? "(空)" : transcription)
          audio: \(audioRelativePath ?? "nil") photos: \(photoPaths.count)
          deadline: \(deadline.rawValue) hazard: \(isHazard)
          site: \(siteTag ?? "nil") template: \(templateName ?? "nil")
        """)
        #endif

        lastSave = LastSaveSnapshot(
            noteID: note.id,
            summary: summaryText(for: transcription, photoCount: photoPaths.count),
            audioRelativePath: audioRelativePath,
            photoRelativePaths: photoPaths
        )
        // 通知列表高亮这条新记录(跨 tab)。
        HighlightTracker.shared.markJustAdded(note.id)
        startUndoCountdown()

        // AI 链:polish → classify。两步串行共用一个 Task。
        // 两个独立开关,任一关闭那步跳过。默认全 on。
        // 任一开关都先过 AI 总开关(P1-5);总开关关闭则两步全部跳过。
        //
        // Engineer profile:**全部禁用**——用户明确要求"工程师版本去掉所有 AI 分析"。
        // 转写就是录音原文,不做纠错;没有 deadline/分类建议。
        //
        // v1.2 AI 精简:omni-classify / LogEntry 抽取链全下架,只剩 polish。
        let isEngineer = UserProfileManager.shared.current == .engineer
        let polishEnabled = !isEngineer && AIToggle.featureEnabled(SettingsKeys.aiPolishEnabled)

        if polishEnabled, !transcription.isEmpty {
            let noteID = note.id
            // Task 句柄存到 enrichTasks。undoLastSave 删 note 前 cancel,
            // 避免 polish 回写到已删的 note。
            let task: Task<Void, Never> = Task { [weak self] in
                guard let self else { return }
                if !Task.isCancelled {
                    do {
                        let polished = try await AIService.shared.polishTranscription(transcription)
                        if !Task.isCancelled, polished != transcription {
                            self.applyPolishedTranscription(noteID: noteID, polished: polished)
                        }
                    } catch {
                        // Apple Intelligence 不可用时静默退化(polishTranscription 已经返回原文)。
                        #if DEBUG
                        print("[SiteNote] AI polish unavailable/failed: \(error.localizedDescription)")
                        #endif
                    }
                }
            }
            enrichTasks[noteID, default: []].append(task)
        }
    }

    /// 取消并清空指定 note 的所有 enrich Task。
    /// undoLastSave 调用,确保 AI 不会写回已撤销的 note。
    private func cancelEnrichTasks(for noteID: UUID) {
        if let tasks = enrichTasks[noteID] {
            for t in tasks { t.cancel() }
        }
        enrichTasks[noteID] = nil
    }

    /// AI polish 完成后调用,把对应 Note 的 transcription 更新为修复版。
    private func applyPolishedTranscription(noteID: UUID, polished: String) {
        // B3:Task 已 cancel 不写。
        if Task.isCancelled { return }
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.id == noteID }
        )
        if let note = try? ctx.fetch(descriptor).first {
            // B3:note 已被撤销(soft delete)也不写。
            guard note.deletedAt == nil else { return }
            note.transcription = polished
            try? ctx.save() // B6:polish 是关键内容字段,显式落盘。
            #if DEBUG
            print("[SiteNote] AI polish applied to \(noteID.uuidString.prefix(8))")
            #endif
        }
    }

    /// 把任意 AI 错误压缩成 < 30 字的中文短原因,给 AIStatusBar 红字行用。
    /// 网络/认证/限额是最常见三类,其他归到"暂时不可用"。
    static func aiFailureReason(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("api key") || msg.contains("unauthorized") || msg.contains("401") {
            return String(localized: "Key 失效或缺失", locale: AppLanguageManager.currentLocale)
        }
        if msg.contains("rate") || msg.contains("quota") || msg.contains("429") {
            return String(localized: "配额/频率限制", locale: AppLanguageManager.currentLocale)
        }
        if msg.contains("network") || msg.contains("offline") || msg.contains("timeout")
            || msg.contains("timed out") || msg.contains("hostname") {
            return String(localized: "网络不可用", locale: AppLanguageManager.currentLocale)
        }
        if msg.contains("model") && msg.contains("unavailable") {
            return String(localized: "模型不可用", locale: AppLanguageManager.currentLocale)
        }
        return String(localized: "暂时不可用", locale: AppLanguageManager.currentLocale)
    }

    private func summaryText(for transcription: String, photoCount: Int) -> String {
        if !transcription.isEmpty {
            let prefix = String(transcription.prefix(20))
            return transcription.count > 20 ? "\(prefix)…" : prefix
        }
        if photoCount > 0 {
            return String(localized: "\(photoCount) 张照片", locale: AppLanguageManager.currentLocale)
        }
        return String(localized: "已保存", locale: AppLanguageManager.currentLocale)
    }

    private func startUndoCountdown() {
        undoTask?.cancel()
        undoSecondsRemaining = undoSeconds

        undoTask = Task { [weak self] in
            guard let self else { return }
            while self.undoSecondsRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.undoSecondsRemaining -= 1
                }
            }
            await MainActor.run {
                self.lastSave = nil
                self.undoSecondsRemaining = 0
            }
        }
    }

    private func dismissUndoToast() {
        undoTask?.cancel()
        undoTask = nil
        lastSave = nil
        undoSecondsRemaining = 0
    }
}
