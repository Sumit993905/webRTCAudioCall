//
//  WebRTCManager.swift
//  webRTCAudioCall
//
//  Created by Sumit Raj Chingari on 29/01/26.
//

import Foundation
import WebRTC
import AVFoundation
import Combine

final class WebRTCManager: NSObject, ObservableObject {

    @Published var callState = "Idle"
    private let socket = WebSocketManager()


    private var peerConnection: RTCPeerConnection!
    private var factory: RTCPeerConnectionFactory!
    private var audioTrack: RTCAudioTrack!

    override init() {
        super.init()
        setupAudioSession()
        setupFactory()
        setupPeerConnection()
        setupAudioTrack()
        setupSocket()
    }

    private func setupSocket() {
        socket.connect()

        socket.onMessage = { [weak self] text in
            self?.handleSignal(text)
        }
    }


    // MARK: - Audio Session
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat)
        try? session.setActive(true)
    }

    // MARK: - Factory
    private func setupFactory() {
        RTCInitializeSSL()
        factory = RTCPeerConnectionFactory()
    }

    // MARK: - PeerConnection
    private func setupPeerConnection() {
        let config = RTCConfiguration()
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
        ]

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        peerConnection = factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )
    }

    // MARK: - Audio Track
    private func setupAudioTrack() {
        let source = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        audioTrack = factory.audioTrack(with: source, trackId: "audio0")
        peerConnection.add(audioTrack, streamIds: ["stream0"])
    }

    // MARK: - Call Control
    @MainActor
    func startCall() {
        callState = "Calling..."

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true"],
            optionalConstraints: nil
        )

        peerConnection.offer(for: constraints) { sdp, _ in
            guard let sdp = sdp else { return }
            self.peerConnection.setLocalDescription(sdp)

            let msg = SignalMessage(
                type: "offer",
                sdp: sdp.sdp,
                candidate: nil,
                sdpMid: nil,
                sdpMLineIndex: nil
            )

            let data = try! JSONEncoder().encode(msg)
            self.socket.send(text: String(data: data, encoding: .utf8)!)
            print("📤 Offer sent")
        }
    }
    
    @MainActor
    private func handleSignal(_ text: String) {

        guard
            let data = text.data(using: .utf8),
            let msg = try? JSONDecoder().decode(SignalMessage.self, from: data)
        else { return }

        switch msg.type {

        case "offer":
            guard let sdp = msg.sdp else { return }

            let offer = RTCSessionDescription(type: .offer, sdp: sdp)
            peerConnection.setRemoteDescription(offer)

            peerConnection.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { [unowned self] answer, _ in
                guard let answer = answer else { return }

                self.peerConnection.setLocalDescription(answer)

                let reply = SignalMessage(
                    type: "answer",
                    sdp: answer.sdp,
                    candidate: nil,
                    sdpMid: nil,
                    sdpMLineIndex: nil
                )

                let data = try! JSONEncoder().encode(reply)
                socket.send(text: String(decoding: data, as: UTF8.self))
            }

        case "answer":
            guard let sdp = msg.sdp else { return }

            let answer = RTCSessionDescription(type: .answer, sdp: sdp)
            peerConnection.setRemoteDescription(answer)
            callState = "Connected 🎧"

        case "ice":
            guard
                let candidate = msg.candidate,
                let sdpMid = msg.sdpMid,
                let index = msg.sdpMLineIndex
            else { return }

            let ice = RTCIceCandidate(
                sdp: candidate,
                sdpMLineIndex: Int32(index),
                sdpMid: sdpMid
            )

            peerConnection.add(ice)

        default:
            break
        }
    }



    func endCall() {
        callState = "Call Ended"

        socket.onMessage = nil
        socket.disconnect()

        peerConnection.close()
        peerConnection = nil
    }
    
}

extension WebRTCManager : RTCPeerConnectionDelegate {
    
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didGenerate candidate: RTCIceCandidate) {

        let msg = SignalMessage(
            type: "ice",
            sdp: nil,
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: Int(candidate.sdpMLineIndex)
        )

        let data = try! JSONEncoder().encode(msg)
        socket.send(text: String(data: data, encoding: .utf8)!)
        print("❄️ ICE sent")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("ICE state:", stateChanged.rawValue)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        
    }
    
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        
    }
    

    
    
}

