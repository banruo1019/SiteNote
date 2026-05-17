//
//  DateFormatters.swift
//  SiteNote
//
//  集中缓存 DateFormatter 实例。原本散落在 RecordView / PMCalendarView /
//  EngineerScheduleView / EngineerReportsView 里每次调用 new DateFormatter()
//  ——在大列表里反复创建是真实的 CPU 浪费(DateFormatter 创建成本 ~ 一次 cold
//  init,大列表 60 帧/秒 × N 行 = 上百次)。集中后:
//  - 单一来源,可以一次性 review locale/format 决策
//  - 实例化只发生一次(static let lazy initialization)
//  - 调用点更短(`Formatters.hourMinute.string(from: d)` vs 4 行 setup)
//
//  Locale 处理:
//  - 时间(HH:mm)用 Locale.current,因为时间格式不随 app 内语言切换
//  - 日期(月份名、星期等)用 AppLanguageManager.currentLocale,跟界面语言一致
//  - 系统语言切换后 formatter 会过期(locale 缓存在实例里)。为了简单,
//    我们只在 app 启动时 init,语言切换后用户必须重启 app(已有提示)。
//

import Foundation

enum Formatters {
    /// "HH:mm" — 24 小时制时间,locale 跟系统(不随 app 语言切)。
    static let hourMinute: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "HH:mm"
        return f
    }()

    /// "yyyy 五月" 风格(本地化模板 yMMMM),跟 app 语言。
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguageManager.currentLocale
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f
    }()

    /// "周三 5 月 17" 风格(本地化模板 EEEEMMMd),跟 app 语言。
    static let weekdayMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguageManager.currentLocale
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f
    }()

    /// "5 月 17" 风格(本地化模板 MMMd),跟 app 语言。
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguageManager.currentLocale
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    /// "17 May" 英文短日期(用于 SVR 报告行右侧 trailing label)。
    static let dayMonthShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "d MMM"
        return f
    }()
}
