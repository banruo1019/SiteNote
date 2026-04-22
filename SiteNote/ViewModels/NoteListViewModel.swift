//
//  NoteListViewModel.swift
//  SiteNote
//
//  把一组 Note 按 "待分类 / 待处理 / 备忘 / 已完成" 四栏分组。纯逻辑,便于测试。
//

import Foundation

/// 列表行的紧迫程度。按距今天时长分档,颜色染行背景。
enum Urgency: Equatable {
    /// 已过截止日。红。
    case overdue
    /// 24 小时以内到期。红。
    case day
    /// 3 天以内到期。橙。
    case threeDays
    /// 1 周以内到期。黄。
    case week
    /// 1 周以后才到期。绿。
    case future
}

/// 首页列表的分组逻辑。
struct NoteListViewModel {

    /// 四栏分组结果。
    struct Sections: Equatable {
        /// `.inbox` 档的未完成 note——用户还没决定 deadline,顶部红色提示。
        var inbox: [Note]
        /// 未完成、有截止的 note,按紧迫程度(逾期→今天→未来)然后 dueDate 升序。
        var pending: [Note]
        /// `.archive` 档的未完成 note——按 createdAt 降序(用户明确"只是记录")。
        var archived: [Note]
        /// 已完成——按 createdAt 降序。
        var done: [Note]
    }

    /// 把 notes 分到四栏。
    func partition(_ notes: [Note], now: Date = Date()) -> Sections {
        var inbox: [Note] = []
        var pending: [Note] = []
        var archived: [Note] = []
        var done: [Note] = []

        for note in notes {
            if note.isDone {
                done.append(note)
            } else if note.deadline == .inbox {
                inbox.append(note)
            } else if note.deadline == .archive {
                archived.append(note)
            } else {
                pending.append(note)
            }
        }

        inbox.sort { $0.createdAt > $1.createdAt }
        pending.sort { $0.dueDate < $1.dueDate }
        archived.sort { $0.createdAt > $1.createdAt }
        done.sort { $0.createdAt > $1.createdAt }

        return Sections(inbox: inbox, pending: pending, archived: archived, done: done)
    }

    /// 判断一条未完成速记的紧迫程度(只对 pending 段有意义)。
    func urgency(for note: Note, now: Date = Date()) -> Urgency {
        if note.dueDate < now { return .overdue }
        let delta = note.dueDate.timeIntervalSince(now)
        let day: TimeInterval = 86_400
        if delta <= day { return .day }
        if delta <= 3 * day { return .threeDays }
        if delta <= 7 * day { return .week }
        return .future
    }

    /// 生成相对时间字符串,如 "今天 14:23" / "昨天" / "3 天前"。
    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "今天 " + f.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            return "昨天"
        }
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: date),
            to: cal.startOfDay(for: now)
        ).day ?? 0
        if days > 0 && days <= 30 {
            return "\(days) 天前"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
