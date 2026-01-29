//
//  WebSocketManager.swift
//  webRTCAudioCall
//
//  Created by Sumit Raj Chingari on 29/01/26.
//

import Foundation

final class WebSocketManager: NSObject {

    private var socket: URLSessionWebSocketTask?
    var onMessage: ((String) -> Void)?

    func connect() {
        let url = URL(string: "wss://3305980e7d9d.ngrok-free.app")!
        socket = URLSession.shared.webSocketTask(with: url)
        socket?.resume()
        receive()
        print("🔌 WebSocket connected")
    }

    func send(text: String) {
        socket?.send(.string(text)) { error in
            if let error = error {
                print("❌ Send error:", error)
            }
        }
    }

    private func receive() {
        socket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    print("📩 WS:", text)
                    self?.onMessage?(text)
                }
            case .failure(let error):
                print("❌ Receive error:", error)
            }
            self?.receive()
        }
    }
    
    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
    }
}

