//
//  OpenPlantSessionsBanner.swift
//  SiteNote
//
//  RecordView 顶部的"开启中机械" 提示条。只在有未闭合 plant session 时出现。
//  设计目标:提醒用户"挖机还在场",让他口头说"挖机走了"或点按钮手动关 session。
//  不在 session 刚开的前 15 分钟显示(避免"刚开又提醒"的干扰)。
//

import SwiftUI
import SwiftData

struct OpenPlantSessionsBanner: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var openSessions: [LogEntry]

    init() {
        let plantRaw = LogKind.plant.rawValue
        _openSessions = Query(
            filter: #Predicate<LogEntry> { e in
                e.kindRaw == plantRaw
                    && e.endAt == nil
                    && e.deletedAt == nil
            },
            sort: [SortDescriptor(\LogEntry.startAt)]
        )
    }

    var body: some View {
        // 每 30 秒刷新一次"已 X" 时长文本。
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let visible = openSessions.filter {
                timeline.date.timeIntervalSince($0.startAt) > 15 * 60
            }
            if visible.isEmpty {
                EmptyView()
            } else {
                card(now: timeline.date, sessions: visible)
            }
        }
    }

    private func card(now: Date, sessions: [LogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.red)
                Text("开启中")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Ink.red)
                Text("\(sessions.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.red)
                Spacer()
                Text("说「XX 走了」或点结束")
                    .font(.system(size: 10))
                    .foregroundStyle(Ink.fgDim)
            }
            ForEach(sessions) { s in
                row(session: s, now: now)
            }
        }
        .padding(12)
        .background(Ink.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Ink.red.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func row(session: LogEntry, now: Date) -> some View {
        HStack(spacing: 10) {
            Text("🚜")
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text(session.subject)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.fg)
                Text("已 \(durationString(now.timeIntervalSince(session.startAt)))")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
                    .monospacedDigit()
            }
            Spacer()
            Button {
                closeSession(session, at: now)
            } label: {
                Text("结束")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Ink.fg)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func closeSession(_ session: LogEntry, at time: Date) {
        session.endAt = time
        // confirmedByUser 顺便置 true,避免已操作的还挂着"待确认"状态。
        session.userConfirmed = true
    }

    private func durationString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h == 0 { return "\(m) 分钟" }
        return "\(h)h \(m)m"
    }
}
