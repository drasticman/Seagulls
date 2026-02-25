//
//  StreamDeckCommands.swift
//  Seagulls
//
//  Created by Andy Bader on 2/18/26.
//

import Foundation

extension Notification.Name {
    static let sdStartWorkflow = Notification.Name("sdStartWorkflow")
    static let sdTrustFirstUntrusted = Notification.Name("sdTrustFirstUntrusted")
    static let sdTrustByName = Notification.Name("sdTrustByName") // userInfo["name"] as String
    static let sdTrustByUUID = Notification.Name("sdTrustByUUID") // userInfo["uuid"]: String
    static let sdOpenSettings = Notification.Name("sdOpenSettings")
    static let sdShowMain = Notification.Name("sdShowMain")
}

