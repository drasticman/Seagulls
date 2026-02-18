//
//  HelpView.swift
//  Seagulls
//
//  Created by Andy Bader on 2/17/26.
//

import SwiftUI

struct HelpView: View {
    @State private var attributedText = AttributedString("")

    var body: some View {
        ScrollView {
            Text(attributedText)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            loadRTF()
        }
    }

    private func loadRTF() {
        guard let url = Bundle.main.url(forResource: "SeagullsHelp", withExtension: "rtf"),
              let data = try? Data(contentsOf: url),
              let nsAttr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              )
        else { return }

        attributedText = AttributedString(nsAttr)
    }
}
