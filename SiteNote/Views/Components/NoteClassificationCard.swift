//
//  NoteClassificationCard.swift
//  SiteNote
//
//  Note 详情页的 "AI 建议" 卡片。与 `LogEntryChipSection` 并列,同样的设计语言。
//  职责:展示 `NoteClassificationPipeline` 写入的 `note.classificationJSON`,
//        提供 "全部确认" / "忽略" / 单项编辑(暂留 future)。
//
//  可见条件:
//    - note.classificationJSON 非空
//    - note.classificationConfirmed == false
//
//  Phase C 的视觉体现:
//    - 每条建议展示**理由**("GPS 距 50m"、"明说'赶紧'")
//    - 置信度 >= 0.85 显示"◉"(可信)
//    - 置信度 0.7–0.85 显示"◎"(建议)
//    - 置信度 < 0.7 显示"○"(参考),这种情况 AI 一般不应该给出(已被 pipeline 丢弃低于 0.5 的)
//

import SwiftUI
import SwiftData

struct NoteClassificationCard: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let suggestion = decoded, !suggestion.isEmpty, !note.classificationConfirmed {
            card(suggestion)
        } else {
            EmptyView()
        }
    }

    private var decoded: NoteClassificationSuggestion? {
        guard let json = note.classificationJSON,
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(NoteClassificationSuggestion.self, from: data)
    }

    private func card(_ s: NoteClassificationSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(s)
            Divider().overlay(Ink.line)
            VStack(spacing: 8) {
                if let x = s.site { row(icon: "building.2.fill", label: "工地", field: x.value, suggestion: x) }
                if let x = s.deadline {
                    row(icon: "calendar", label: "到期",
                        field: Deadline(rawValue: x.value)?.displayName ?? x.value,
                        suggestion: x)
                }
                if let x = s.subTags {
                    row(icon: "tag.fill", label: "分类",
                        field: x.value.joined(separator: " · "),
                        suggestion: x)
                }
                if let x = s.hazard, x.value {
                    row(icon: "exclamationmark.triangle.fill", label: "隐患",
                        field: "标记为隐患",
                        suggestion: x,
                        tint: Ink.red)
                }
                if let x = s.clause {
                    row(icon: "doc.text", label: "合同条款", field: x.value, suggestion: x)
                }
            }
            Divider().overlay(Ink.line).padding(.top, 2)
            actionButtons(s)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Ink.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Ink.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private func header(_ s: NoteClassificationSuggestion) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.accent)
            Text("AI 建议")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Ink.accent)
            Spacer()
            Text("\(countTotal(s)) 项 · \(s.highConfidenceCount) 可信")
                .font(.system(size: 11))
                .foregroundStyle(Ink.fgDim)
        }
    }

    /// 一条建议的单行 UI。左侧图标 + 字段名 + 值,右侧置信度/来源/理由。
    private func row<T: Codable>(
        icon: String,
        label: String,
        field: String,
        suggestion: FieldSuggestion<T>,
        tint: Color = Ink.fg
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Ink.fgDim)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.3)
                        .textCase(.uppercase)
                        .foregroundStyle(Ink.dim)
                    Text(field)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tint)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(confidenceGlyph(suggestion.confidence))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(confidenceColor(suggestion.confidence))
                    Text(sourceLabel(suggestion.source))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(sourceColor(suggestion.source))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(sourceColor(suggestion.source).opacity(0.1), in: Capsule())
                    Text("· \(suggestion.reasoning)")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func actionButtons(_ s: NoteClassificationSuggestion) -> some View {
        HStack(spacing: 10) {
            Button {
                NoteClassificationPipeline.dismiss(note: note)
            } label: {
                Text("忽略")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.fgDim)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(
                        Capsule().strokeBorder(Ink.line, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NoteClassificationPipeline.apply(suggestion: s, to: note)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("全部确认")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Ink.fg)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Formatting helpers

    private func countTotal(_ s: NoteClassificationSuggestion) -> Int {
        var n = 0
        if s.site != nil { n += 1 }
        if s.subTags != nil { n += 1 }
        if s.deadline != nil { n += 1 }
        if s.hazard != nil { n += 1 }
        if s.clause != nil { n += 1 }
        return n
    }

    private func confidenceGlyph(_ c: Double) -> String {
        switch c {
        case 0.85...: return "◉"     // 可信
        case 0.7...:  return "◎"     // 建议
        default:      return "○"     // 参考
        }
    }

    private func confidenceColor(_ c: Double) -> Color {
        switch c {
        case 0.85...: return Ink.green
        case 0.7...:  return Ink.accent
        default:      return Ink.dim
        }
    }

    private func sourceLabel(_ source: SuggestionSource) -> String {
        switch source {
        case .gps: return "GPS"
        case .ai:  return "AI"
        }
    }

    private func sourceColor(_ source: SuggestionSource) -> Color {
        switch source {
        case .gps: return Ink.accentBlue
        case .ai:  return Ink.accent
        }
    }
}
