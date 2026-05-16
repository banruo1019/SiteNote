//
//  Note.swift
//  SiteNote
//
//  一条工地速记的数据模型。SwiftData 负责持久化。
//

import Foundation
import SwiftData

/// 到期日期的五档选择。录音默认进 `inbox` 待用户分类。
enum Deadline: String, Codable, CaseIterable {
    /// 默认值:用户还未分类,不推送,顶部红点提醒"有 X 条待分类"。
    case inbox
    case today
    case threeDays
    case thisWeek
    /// 只想记下来,永不提醒(备忘)。
    case archive

    /// 面向用户的显示名。
    var displayName: String {
        switch self {
        case .inbox: return String(localized: "待分类", locale: AppLanguageManager.currentLocale)
        case .today: return String(localized: "今天", locale: AppLanguageManager.currentLocale)
        case .threeDays: return String(localized: "3 天内", locale: AppLanguageManager.currentLocale)
        case .thisWeek: return String(localized: "7 天内", locale: AppLanguageManager.currentLocale)
        case .archive: return String(localized: "只是记录", locale: AppLanguageManager.currentLocale)
        }
    }

    /// 是否应该排推送。inbox 和 archive 都不排。
    var shouldSchedule: Bool {
        switch self {
        case .inbox, .archive: return false
        case .today, .threeDays, .thisWeek: return true
        }
    }

    /// 根据选择算出具体到期日(当天 23:59:59)。
    /// - Parameter base: 参考时间(通常是 note 的 createdAt)。
    /// - Returns: 具体到期日;`inbox` / `archive` 返回 100 年后,调度器据此跳过。
    func dueDate(from base: Date = Date()) -> Date {
        let cal = Calendar.current
        let endOfBase = cal.date(bySettingHour: 23, minute: 59, second: 59, of: base) ?? base
        switch self {
        case .inbox, .archive:
            return cal.date(byAdding: .year, value: 100, to: base) ?? base
        case .today:
            return endOfBase
        case .threeDays:
            return cal.date(byAdding: .day, value: 3, to: endOfBase) ?? endOfBase
        case .thisWeek:
            return cal.date(byAdding: .day, value: 7, to: endOfBase) ?? endOfBase
        }
    }
}

/// 一条工地速记。承载"语音转文字 + 原始录音 + 位置 + 天气 + 到期提醒"。
///
/// 使用方式：
/// - 由 `HomeView` 触发录音后写入。
/// - `NotificationService` 根据 `dueDate` 和 `deadline != .archive` 排推送。
/// - 详情页（任务 3）通过 `audioFilePath` 回放原始音频。
@Model
final class Note {
    /// 稳定唯一标识。本地通知 identifier 用它。
    var id: UUID = UUID()

    /// **原始** 语音识别文本。创建后**永不修改**。法律/EOT 证据层。
    /// AI polish 和用户编辑都不会改这个字段。
    var transcriptionOriginal: String = ""

    /// 当前显示/编辑的文本。初始化时 = transcriptionOriginal;
    /// AI polish 完成后覆盖此字段(但 original 保留);用户在详情页编辑也改此字段。
    /// 用于所有 UI 展示、PDF 导出、分享等。
    var transcription: String = ""

    /// 创建时间。由 `init` 自动填充。
    var createdAt: Date = Date()

    /// `Deadline` 的原始字符串值。SwiftData 存 String 比存自定义枚举更稳。
    /// 通过 `deadline` 计算属性读写。
    var deadlineRaw: String = Deadline.threeDays.rawValue

    /// 根据 `deadline` 和创建时间算出的具体到期日。
    var dueDate: Date = Date()

    /// 是否已完成。完成后推送被取消。
    var isDone: Bool = false

    /// 原始录音文件的相对路径（相对于 App 的 Documents 目录），例如 "audio/ABC123.m4a"。
    /// 录音失败或用户关闭录音时为 `nil`。
    var audioFilePath: String?

    /// 附带照片的相对路径数组。第一版（任务 1）恒为空。
    var photoPaths: [String] = []

    /// 位置纬度。
    var latitude: Double?

    /// 位置经度。
    var longitude: Double?

    /// 反向地理编码出来的可读地址。
    var locationAddress: String?

    /// 天气的一行人类可读摘要，例如 "22°C 小雨"。
    var weatherSummary: String?

    /// 气温（摄氏）。为 EOT（工期延误主张）分析保留原始数据。
    var temperatureCelsius: Double?

    /// WMO 天气编码（0=晴、61=雨 等）。为 EOT 逻辑保留。
    var weatherCode: Int?

    /// 最近一次分享的时间（任务 5 用）。
    var lastSharedAt: Date?

    /// 所属工地标签（如 "悉尼 Olympic Park"）。`nil` 表示未分类。
    /// 标签列表由用户在设置页管理。
    var siteTag: String?

    /// 分派给的联系人名字(任务 7 用)。`nil` 表示未分派。
    /// 每次分派都会更新 `lastSharedAt`。
    var assignedTo: String?

    /// 是否标记为"隐患"(任务 8):OHS 合规相关,推送标题会加 🚨 前缀。
    var isHazard: Bool = false

    /// 应用的巡检模板名(任务 3)。`nil` 表示未使用模板。
    var templateName: String?

    /// 本次巡检中已勾选的模板项。未勾选的可视为"漏项"。
    var checkedItems: [String] = []

    /// 引用的合同条款(任务 19),例如 "Clause 34.2 EOT"。
    /// 内容由用户在设置页预置或手打。
    var contractClauseRef: String?

    /// 任务 15:关联的工地平面图名字。`nil` 表示未标注。
    var floorPlanRef: String?
    /// 任务 15:在平面图上的 x 坐标,归一化到 0-1。
    var floorPlanX: Double?
    /// 任务 15:在平面图上的 y 坐标,归一化到 0-1。
    var floorPlanY: Double?

    /// 软删时间戳。非空表示在垃圾桶里。nil 表示"活着"。
    /// 主列表查询需要过滤 `deletedAt == nil`,垃圾桶反之。
    var deletedAt: Date?

    /// 非工地的其他标签,多选。比如 ["开会", "紧急", "公司事务"]。
    /// 和 `siteTag` 正交:一条 note 既可以有工地又可以有多个其他标签。
    var otherTags: [String] = []

    /// **[Deprecated v1.2 AI 精简]** 字段保留仅为 SwiftData schema 兼容。
    /// 永远 nil,不再有 AI 写入。
    var classificationJSON: String? = nil

    /// **[Deprecated v1.2 AI 精简]** 同上。永远 false。
    var classificationConfirmed: Bool = false

    /// **[Deprecated v1.2]** legacy 字段,字段保留仅为 SwiftData schema 兼容
    /// (删字段会让老用户 ModelContainer 初始化失败)。永远保持 false,
    /// 所有调用方已清掉。
    var isDiaryRecord: Bool = false

    /// 到期选择。映射到 `deadlineRaw` 存储。非法值降级到 `.threeDays`。
    var deadline: Deadline {
        get { Deadline(rawValue: deadlineRaw) ?? .threeDays }
        set { deadlineRaw = newValue.rawValue }
    }

    /// 创建一条新速记。
    init(
        transcription: String,
        createdAt: Date = Date(),
        deadline: Deadline,
        dueDate: Date,
        isDone: Bool = false,
        audioFilePath: String? = nil,
        photoPaths: [String] = [],
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationAddress: String? = nil,
        weatherSummary: String? = nil,
        temperatureCelsius: Double? = nil,
        weatherCode: Int? = nil,
        lastSharedAt: Date? = nil,
        siteTag: String? = nil,
        assignedTo: String? = nil,
        isHazard: Bool = false,
        templateName: String? = nil,
        checkedItems: [String] = [],
        contractClauseRef: String? = nil,
        floorPlanRef: String? = nil,
        floorPlanX: Double? = nil,
        floorPlanY: Double? = nil
    ) {
        self.id = UUID()
        self.transcriptionOriginal = transcription
        self.transcription = transcription
        self.createdAt = createdAt
        self.deadlineRaw = deadline.rawValue
        self.dueDate = dueDate
        self.isDone = isDone
        self.audioFilePath = audioFilePath
        self.photoPaths = photoPaths
        self.latitude = latitude
        self.longitude = longitude
        self.locationAddress = locationAddress
        self.weatherSummary = weatherSummary
        self.temperatureCelsius = temperatureCelsius
        self.weatherCode = weatherCode
        self.lastSharedAt = lastSharedAt
        self.siteTag = siteTag
        self.assignedTo = assignedTo
        self.isHazard = isHazard
        self.templateName = templateName
        self.checkedItems = checkedItems
        self.contractClauseRef = contractClauseRef
        self.floorPlanRef = floorPlanRef
        self.floorPlanX = floorPlanX
        self.floorPlanY = floorPlanY
    }
}
