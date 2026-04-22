//
//  SearchBarButton.swift
//  SiteNote
//
//  全局搜索的入口按钮——放在每个 tab 标题行 TodayBriefButton 旁边。
//  Tap → 弹 GlobalSearchView sheet。
//

import SwiftUI

struct SearchBarButton: View {
    @State private var showsSearch: Bool = false

    var body: some View {
        Button {
            showsSearch = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Ink.fgDim)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsSearch) {
            GlobalSearchView()
        }
    }
}
