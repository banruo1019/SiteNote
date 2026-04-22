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

    private var modelContext: ModelContext?
    private var recordingStartTime: Date?
    private var undoTask: Task<Void, Never>?

    private let voice = VoiceCaptureService()
    private let location = LocationService()
    private let weather = WeatherService()

    private let minRecordingDuration: TimeInterval = 0.5
    /// Undo toast 倒计时总秒数。加长到 5 秒是为了工地戴手套用户有足够时间反应。
    private let undoSeconds = 5

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - 录音

    func startRecording() {
        guard VoiceCaptureService.hasAllPermissions else {
            errorMessage = VoiceCaptureService.VoiceError.notAuthorized.errorDescription
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
        } catch let error as VoiceCaptureService.VoiceError {
            errorMessage = error.errorDescription
            recordingStartTime = nil
        } catch {
            errorMessage = error.localizedDescription
            recordingStartTime = nil
        }
    }

    /// 下滑取消录音:停止但**不保存**,音频文件删掉。不影响已暂存照片。
    /// 用于 RecordView 的下滑取消手势。
    func cancelRecording() {
        guard isRecording else { return }
        let result = voice.stopCapturing()
        isRecording = false
        currentAudioLevel = 0
        recordingStartTime = nil
        partialTranscription = ""
        // 把已写盘的音频文件删掉——这条录音整个作废
        if let path = result.audioRelativePath,
           let url = VoiceCaptureService.absoluteURL(forRelative: path) {
            try? FileManager.default.removeItem(at: url)
        }
        print("[SiteNote] 用户下滑取消了录音")
    }

    /// 松开录音:立即保存(含已暂存照片)。不再弹 DeadlineSheet。
    ///
    /// - Parameter asDiary: 日志模式。true 时:
    ///   - 强制 `deadline = .archive`,永不提醒
    ///   - 保存后 `isDiaryRecord = true`(在 commitDirectly 里设)
    ///   - 跳过中文日期猜测和 omni-classify AI 链,只跑 polish + LogEntry 抽取
    ///
    /// **延迟优化**:松手后立即 commit(用 partial + 缓存的上次位置),
    /// 真定位/天气/双语回退/AI polish 全部走后台 Task 补齐。
    /// 用户看到 undo toast 几乎无延迟。
    func stopAndSave(asDiary: Bool = false) async {
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

        // 用上次成功的位置做占位(瞬时,不等网络)。真定位/天气在后台补。
        let cachedLoc = LocationService.lastSuccessfulLocation()

        // 日志模式直接归档,不猜日期;普通模式走中文日期解析。
        let deadline: Deadline
        if asDiary {
            deadline = .archive
        } else {
            let suggested = ChineseDateParser.parseDeadline(from: initialTranscription)
            deadline = suggested ?? .inbox
        }

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
            floorPlanY: nil,
            asDiary: asDiary
        )

        // 后台补齐:双语回退转写 / 实时 GPS / 天气。
        guard let noteID = lastSave?.noteID else { return }
        let audioPath = result.audioRelativePath
        Task { [weak self] in
            await self?.enrichNoteAfterCommit(
                noteID: noteID,
                audioPath: audioPath,
                initialTranscription: initialTranscription,
                usedCachedLocation: cachedLoc != nil
            )
        }
    }

    /// 后台补齐:双语回退转写、实时 GPS、天气。失败静默降级。
    private func enrichNoteAfterCommit(
        noteID: UUID,
        audioPath: String?,
        initialTranscription: String,
        usedCachedLocation: Bool
    ) async {
        // 双语回退
        var improvedTranscription: String? = nil
        if let audioPath,
           ChineseDateParser.transcriptionLikelyWrongLanguage(initialTranscription) {
            let primary = UserDefaults.standard.string(forKey: SettingsKeys.speechLanguage) ?? "zh-CN"
            let alt = primary == "zh-CN" ? "en-US" : "zh-CN"
            let altResult = await VoiceCaptureService.retranscribe(
                audioRelativePath: audioPath,
                alternateLocale: alt
            )
            if altResult.count > initialTranscription.count {
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
        if let improvedTranscription {
            let aiEnabled = UserDefaults.standard.object(forKey: "settings.aiPolishEnabled") as? Bool ?? true
            if aiEnabled, !improvedTranscription.isEmpty {
                do {
                    let polished = try await AIService.shared.polishTranscription(improvedTranscription)
                    if polished != improvedTranscription {
                        applyPolishedTranscription(noteID: noteID, polished: polished)
                    }
                } catch {
                    print("[SiteNote] AI polish (bilingual retry) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 把后台拿到的更准字段写回已保存的 note。若 note 已被撤销就无操作。
    private func updateNoteEnrichment(
        noteID: UUID,
        transcription: String?,
        location: LocationService.Location?,
        weather: WeatherService.Weather?
    ) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == noteID })
        guard let note = try? ctx.fetch(descriptor).first else { return }

        if let transcription {
            note.transcription = transcription
            note.transcriptionOriginal = transcription
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

        let descriptor = FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == id })
        if let matches = try? ctx.fetch(descriptor), let note = matches.first {
            NotificationService.shared.cancel(for: note)
            ctx.delete(note)
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

    /// UndoToast 上用户点 [今天][3天][本周][归档] 之一后调用。
    /// 更新最近保存的 note 的 deadline + 重排推送。完成后关 toast。
    func classifyLastSave(to newDeadline: Deadline) {
        guard let snapshot = lastSave, let ctx = modelContext else { return }
        let id = snapshot.noteID
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == id })
        if let note = try? ctx.fetch(descriptor).first {
            note.deadline = newDeadline
            note.dueDate = newDeadline.dueDate(from: note.createdAt)
            NotificationService.shared.schedule(for: note)
        }
        dismissUndoToast()
    }

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
        floorPlanY: Double? = nil,
        asDiary: Bool = false
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
        // 日志模式:提前在 commit 时就标 isDiaryRecord,不等 AI 抽取回填。
        // 这样 Note 一落库就被 RecordView / BrowseView 的提醒过滤识别为"非提醒"。
        if asDiary {
            note.isDiaryRecord = true
        }
        modelContext?.insert(note)
        NotificationService.shared.schedule(for: note)

        // GPS 学习:若保存时已有 siteTag + 坐标,把这条样本喂给 centroid。
        // Phase A 用这个数据推荐工地(用户不标也能学到常去的地方)。
        if let siteTag, let lat = location?.latitude, let lng = location?.longitude {
            SiteCentroidsStorage.observe(siteName: siteTag, latitude: lat, longitude: lng)
        }

        print("""
        [SiteNote] Committed note:
          transcription: \(transcription.isEmpty ? "(空)" : transcription)
          audio: \(audioRelativePath ?? "nil") photos: \(photoPaths.count)
          deadline: \(deadline.rawValue) hazard: \(isHazard)
          site: \(siteTag ?? "nil") template: \(templateName ?? "nil")
        """)

        lastSave = LastSaveSnapshot(
            noteID: note.id,
            summary: summaryText(for: transcription, photoCount: photoPaths.count),
            audioRelativePath: audioRelativePath,
            photoRelativePaths: photoPaths
        )
        // 通知列表高亮这条新记录(跨 tab)。
        HighlightTracker.shared.markJustAdded(note.id)
        startUndoCountdown()

        // AI 链:polish → classify → 抽 LogEntry。三步串行共用一个 Task。
        // 三个独立开关,任一关闭那步跳过。默认全 on。
        let polishEnabled = UserDefaults.standard.object(forKey: "settings.aiPolishEnabled") as? Bool ?? true
        let classifyEnabled = UserDefaults.standard.object(forKey: "settings.aiOmniClassifyEnabled") as? Bool ?? true
        let extractEnabled = UserDefaults.standard.object(forKey: "settings.aiLogExtractEnabled") as? Bool ?? true

        if (polishEnabled || classifyEnabled || extractEnabled), !transcription.isEmpty {
            let noteID = note.id
            Task { [weak self] in
                // 1) polish(best-effort)
                if polishEnabled {
                    do {
                        let polished = try await AIService.shared.polishTranscription(transcription)
                        if polished != transcription {
                            self?.applyPolishedTranscription(noteID: noteID, polished: polished)
                        }
                    } catch {
                        print("[SiteNote] AI polish unavailable/failed: \(error.localizedDescription)")
                    }
                }
                // 2) omni-classify(GPS 规则 + AI 综合分类)→ 写建议 JSON 到 note,用户到详情页确认。
                // **日志模式跳过**:用户明示意图是日志,不用 AI 猜 deadline / hazard / 模板 / 条款。
                if classifyEnabled {
                    await self?.runClassificationIfNeeded(noteID: noteID)
                }
                // 3) LogEntry 抽取
                if extractEnabled {
                    await self?.extractAndIngestLogs(noteID: noteID)
                }
            }
        }
    }

    /// 从 noteID 拉出 Note,跑 Phase A+B 的 pipeline,结果写回 classificationJSON。
    /// 日志 note 也跑——但 pipeline 内部会把建议裁剪到只剩 site + subTags,
    /// 不会推 deadline/hazard/template/clause。
    private func runClassificationIfNeeded(noteID: UUID) async {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.id == noteID }
        )
        guard let note = try? ctx.fetch(descriptor).first else { return }
        await NoteClassificationPipeline.classify(note: note)
    }

    /// AI polish 完成后调用,把对应 Note 的 transcription 更新为修复版。
    private func applyPolishedTranscription(noteID: UUID, polished: String) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.id == noteID }
        )
        if let note = try? ctx.fetch(descriptor).first {
            note.transcription = polished
            print("[SiteNote] AI polish applied to \(noteID.uuidString.prefix(8))")
        }
    }

    /// 从指定 Note 重新抽 LogEntry 并落库。保存流程里被 polish 之后调。
    /// 失败静默——LogEntry 缺失不影响 Note 本身,用户回来手动改即可。
    private func extractAndIngestLogs(noteID: UUID) async {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.id == noteID }
        )
        guard let note = try? ctx.fetch(descriptor).first else { return }

        let drafts = await AIService.shared.extractLogEntries(from: note)
        guard !drafts.isEmpty else {
            print("[SiteNote] LogEntry extract: 0 条 for \(noteID.uuidString.prefix(8))")
            return
        }
        LogEntryIngestor.ingest(drafts: drafts, from: note, into: ctx)
        print("[SiteNote] LogEntry extract: \(drafts.count) 条 for \(noteID.uuidString.prefix(8))")
    }

    private func summaryText(for transcription: String, photoCount: Int) -> String {
        if !transcription.isEmpty {
            let prefix = String(transcription.prefix(20))
            return transcription.count > 20 ? "\(prefix)…" : prefix
        }
        if photoCount > 0 {
            return "\(photoCount) 张照片"
        }
        return "已保存"
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
