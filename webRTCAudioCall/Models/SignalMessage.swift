//
//  SignalMessage.swift
//  webRTCAudioCall
//
//  Created by Sumit Raj Chingari on 29/01/26.
//

import Foundation

struct SignalMessage: Codable {
    let type: String
    let sdp: String?
    let candidate: String?
    let sdpMid: String?
    let sdpMLineIndex: Int?
}

