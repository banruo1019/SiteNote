//
//  SearchBarButton.swift
//  SiteNote
//
//  全局搜索的入口按钮——放在每个 tab 标题行齿轮按钮旁边。
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
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Ink.fgDim)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("搜索")
        .sheet(isPresented: $showsSearch) {
            GlobalSearchView()
        }
    }
}
