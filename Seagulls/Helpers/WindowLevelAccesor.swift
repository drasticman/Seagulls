//
//  WindowLevelAccesor.swift
//  Seagulls
//
//  Created by Andy Bader on 2/18/26.
//

import SwiftUI
import AppKit

struct WindowLevelAccessor: NSViewRepresentable {
    let level: NSWindow.Level

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.level = level
            view.window?.collectionBehavior.insert(.fullScreenAuxiliary)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.level = level
            nsView.window?.collectionBehavior.insert(.fullScreenAuxiliary)
        }
    }
}
