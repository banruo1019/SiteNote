//
//  LogEntryChipSection.swift
//  SiteNote
//
//  Note 详情页的 "AI 识别" 卡片。
//  显示 AI 从 transcription 抽出的 LogEntry,用户可 tap 修改 / 全部确认 / 删除。
//  这是 LogEntry 用户触达的第一道 UI——没有这里,AI 抽错了用户永远看不到。
//

import SwiftUI
import SwiftData

/// 展示某条 Note 关联的所有 LogEntry(软删除以外)。
/// 用 @Query 驱动,entry 落库/编辑后自动刷新。
struct LogEntryChipSection: View {
    let note: Note
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [LogEntry]
    @State private var editing: LogEntry?

    init(note: Note) {
        self.note = note
        let noteID = note.id
        _entries = Query(
            filter: #Predicate<LogEntry> {
                $0.sourceNoteID == noteID && $0.deletedAt == nil
            },
            sort: [SortDescriptor(\LogEntry.createdAt)]
        )
    }

    var body: some View {
        if entries.isEmpty {
            EmptyView()
        } else {
            card
                .sheet(item: $editing) { entry in
                    LogEntryEditSheet(entry: entry) { deleted in
                        if deleted {
                            entry.deletedAt = Date()
                        }
                    }
                }
        }
    }

    private var unconfirmedCount: Int {
        entries.filter { !$0.userConfirmed }.count
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().overlay(Ink.line)
            VStack(spacing: 6) {
                ForEach(entries) { entry in
                    chipRow(entry)
                }
            }
            if unconfirmedCount > 0 {
                Divider().overlay(Ink.line).padding(.top, 2)
                HStack {
                    Spacer()
                    Button {
                        confirmAll()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("全部确认")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Ink.fg)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Ink.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Ink.line, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.fgDim)
            Text("AI 识别")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)
            Spacer()
            if unconfirmedCount > 0 {
                Text("⚠ \(unconfirmedCount) 待确认")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Ink.red)
            } else {
                Text("\(entries.count) 条 · 已确认")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.dim)
            }
        }
    }

    private func chipRow(_ entry: LogEntry) -> some View {
        Button {
            editing = entry
        } label: {
            HStack(spacing: 10) {
                Text(iconFor(entry))
                    .font(.system(size: 15))
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryLabel(entry))
                        .font(.system(size: 14, weight: entry.userConfirmed ? .regular : .medium))
                        .foregroundStyle(Ink.fg)
                    if let sub = secondaryLabel(entry), !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.fgDim)
                    }
                }

                Spacer()

                if entry.confidence < 0.7 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.red)
                }
                if !entry.userConfirmed {
                    Circle()
                        .fill(Ink.red)
                        .frame(width: 6, height: 6)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconFor(_ entry: LogEntry) -> String {
        switch entry.kind {
        case .person:   return entry.isAbsent ? "🚫" : "👥"
        case .plant:    return "🚜"
        case .delivery: return "📦"
        case .visitor:  return "🧑"
        case .event:    return "⚠️"
        }
    }

    /// "水工 ×4" / "挖机 · 开启中" / "钢筋" / "监理" / "停电"
    private func primaryLabel(_ e: LogEntry) -> String {
        switch e.kind {
        case .person:
            if e.isAbsent { return "\(e.subject) · 缺席" }
            if let q = e.quantity, q > 0 { return "\(e.subject) ×\(q)" }
            return e.subject
        case .plant:
            if e.endAt == nil {
                return "\(e.subject) · 开启中"
            }
            if e.startAt == e.endAt {
                return "\(e.subject) · 孤儿记录"
            }
            let startStr = e.startAtExplicit ? timeString(e.startAt) : "—"
            let endStr = e.endAt.map(timeString) ?? "—"
            if let duration = e.duration, e.startAtExplicit {
                return "\(e.subject) · \(startStr)–\(endStr) · \(Self.durationString(duration))"
            }
            return "\(e.subject) · \(startStr)–\(endStr)"
        case .delivery, .visitor, .event:
            return e.subject
        }
    }

    /// 附注:缺席原因 / plant 孤儿说明 / event 详情。
    private func secondaryLabel(_ e: LogEntry) -> String? {
        if let n = e.note, !n.isEmpty { return n }
        if e.kind == .delivery || e.kind == .visitor || e.kind == .event {
            return e.startAtExplicit ? timeString(e.startAt) : "未标时间"
        }
        return nil
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func durationString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h == 0 { return "\(m)m" }
        return "\(h)h \(m)m"
    }

    private func confirmAll() {
        for e in entries where !e.userConfirmed {
            e.userConfirmed = true
        }
    }
}

// MARK: - 编辑 sheet

/// 修改 LogEntry 的单条信息。字段按 kind 动态显示(person 才有 quantity/absent,plant 才有 endAt)。
struct LogEntryEditSheet: View {
    @Bindable var entry: LogEntry
    var onClose: (_ deleted: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsDeleteConfirm: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("类型", selection: kindBinding) {
                        ForEach(LogKind.allCases, id: \.self) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("主语") {
                    TextField("如 水工 / 挖机 / 钢筋", text: $entry.subject)
                        .font(.system(size: DesignTokens.FontSize.body))
                }

                if entry.kind == .person {
                    Section("人员") {
                        Toggle("缺席", isOn: $entry.isAbsent)
                        if !entry.isAbsent {
                            Stepper(value: quantityBinding, in: 0...99) {
                                HStack {
                                    Text("数量")
                                    Spacer()
                                    Text("\(entry.quantity ?? 0)")
                                        .foregroundStyle(Ink.fgDim)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }

                Section("时间") {
                    // 开始时间:没说就"—",点"+ 添加"展开 DatePicker;已有则 DatePicker + "×"。
                    if entry.startAtExplicit {
                        HStack {
                            DatePicker("开始", selection: $entry.startAt)
                            Button {
                                entry.startAtExplicit = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Ink.fgDim)
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        Button {
                            entry.startAtExplicit = true
                        } label: {
                            HStack {
                                Text("开始")
                                Spacer()
                                Text("—")
                                    .foregroundStyle(Ink.fgDim)
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Ink.accent)
                            }
                        }
                    }

                    // 结束时间 + 总时长(只 plant)
                    if entry.kind == .plant {
                        if let _ = entry.endAt {
                            HStack {
                                DatePicker("结束", selection: Binding(
                                    get: { entry.endAt ?? entry.startAt },
                                    set: { entry.endAt = $0 }
                                ))
                                Button {
                                    entry.endAt = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Ink.fgDim)
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            Button {
                                entry.endAt = Date()
                            } label: {
                                HStack {
                                    Text("结束")
                                    Spacer()
                                    Text("未结束")
                                        .foregroundStyle(Ink.fgDim)
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Ink.accent)
                                }
                            }
                        }

                        // 总时长:两端都有 → 算实际;只有开始 → 实时"已运行"。
                        HStack {
                            Text("总时长")
                                .foregroundStyle(Ink.fgDim)
                            Spacer()
                            Text(plantDurationLabel)
                                .font(.system(.body, design: .default).monospacedDigit())
                                .foregroundStyle(Ink.fg)
                        }
                    }
                }

                Section("附加说明") {
                    TextField("原因 / 备注", text: noteBinding, axis: .vertical)
                        .font(.system(size: DesignTokens.FontSize.body))
                        .lineLimit(1...4)
                }

                Section {
                    Button(role: .destructive) {
                        showsDeleteConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("删除这条")
                        }
                    }
                }
            }
            .industrialForm()
            .navigationTitle("编辑日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onClose(false)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        entry.userConfirmed = true
                        onClose(false)
                        dismiss()
                    }
                    .bold()
                }
            }
            .alert("删除这条记录?", isPresented: $showsDeleteConfirm) {
                Button("删除", role: .destructive) {
                    onClose(true)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这条 AI 识别记录会软删,不影响原始速记。")
            }
        }
    }

    private var kindBinding: Binding<LogKind> {
        Binding(
            get: { entry.kind },
            set: { entry.kind = $0 }
        )
    }

    private var quantityBinding: Binding<Int> {
        Binding(
            get: { entry.quantity ?? 0 },
            set: { entry.quantity = $0 > 0 ? $0 : nil }
        )
    }

    /// 机械总时长文本。三态:已闭合 → "6h 45m";只开始 → "已运行 2h 10m";没开始 → "—"。
    private var plantDurationLabel: String {
        guard entry.kind == .plant, entry.startAtExplicit else { return "—" }
        if let end = entry.endAt {
            let interval = end.timeIntervalSince(entry.startAt)
            return LogEntryChipSection.durationString(interval)
        }
        // 开着的 session:实时算(用户每次进详情页看到的时间)
        let interval = Date().timeIntervalSince(entry.startAt)
        return "已运行 " + LogEntryChipSection.durationString(interval)
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { entry.note ?? "" },
            set: { entry.note = $0.isEmpty ? nil : $0 }
        )
    }
}
