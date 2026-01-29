import Foundation
import WebRTC
import AVFoundation
import Combine

final class WebRTCManager: NSObject, ObservableObject {

    // MARK: - UI State
    @Published var callState = "Idle"

    // MARK: - Signaling
    private let socket = WebSocketManager()

    // MARK: - Call State Flags
    private var isCaller = false
    private var remoteSDPSet = false
    private var pendingICE: [RTCIceCandidate] = []

    // MARK: - WebRTC Core
    private var peerConnection: RTCPeerConnection!
    private var factory: RTCPeerConnectionFactory!
    private var audioTrack: RTCAudioTrack!

    // MARK: - Init
    override init() {
        super.init()
        setupAudioSession()
        setupFactory()
        setupPeerConnection()
        setupAudioTrack()
        setupSocket()
    }

    // MARK: - WebSocket
    private func setupSocket() {
        socket.connect()

        socket.onMessage = { [unowned self] text in
            DispatchQueue.main.async {
                self.handleSignal(text)
            }
        }
    }

    // MARK: - Audio Session
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker]
        )
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
        let source = factory.audioSource(
            with: RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: nil
            )
        )

        audioTrack = factory.audioTrack(with: source, trackId: "audio0")
        peerConnection.add(audioTrack, streamIds: ["stream0"])
    }

    // MARK: - Caller Only
    @MainActor
    func startCall() {
        guard !isCaller else { return }

        isCaller = true
        callState = "Calling…"

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true"],
            optionalConstraints: nil
        )

        peerConnection.offer(for: constraints) { [unowned self] sdp, _ in
            guard let sdp = sdp else { return }

            self.peerConnection.setLocalDescription(sdp)
            self.sendSignal(type: "offer", sdp: sdp.sdp)

            print("📤 Offer sent")
        }
    }

    // MARK: - Signaling Handler
    @MainActor
    private func handleSignal(_ text: String) {

        guard
            let data = text.data(using: .utf8),
            let msg = try? JSONDecoder().decode(SignalMessage.self, from: data)
        else { return }

        switch msg.type {

        // ---------- OFFER (callee) ----------
        case "offer":
            guard !isCaller, let sdp = msg.sdp else { return }

            let offer = RTCSessionDescription(type: .offer, sdp: sdp)

            peerConnection.setRemoteDescription(offer) { _ in
                self.remoteSDPSet = true
                self.flushPendingICE()
            }

            let constraints = RTCMediaConstraints(
                mandatoryConstraints: ["OfferToReceiveAudio": "true"],
                optionalConstraints: nil
            )

            peerConnection.answer(for: constraints) { [unowned self] answer, _ in
                guard let answer = answer else { return }

                self.peerConnection.setLocalDescription(answer)
                self.sendSignal(type: "answer", sdp: answer.sdp)

                print("📤 Answer sent")
            }

        // ---------- ANSWER (caller) ----------
        case "answer":
            guard isCaller, let sdp = msg.sdp else { return }

            let answer = RTCSessionDescription(type: .answer, sdp: sdp)

            peerConnection.setRemoteDescription(answer) { _ in
                self.remoteSDPSet = true
                self.flushPendingICE()
                self.callState = "Connected 🎧"
            }

        // ---------- ICE ----------
        case "ice":
            guard
                let c = msg.candidate,
                let mid = msg.sdpMid,
                let index = msg.sdpMLineIndex
            else { return }

            let ice = RTCIceCandidate(
                sdp: c,
                sdpMLineIndex: Int32(index),
                sdpMid: mid
            )

            if remoteSDPSet {
                peerConnection.add(ice)
            } else {
                pendingICE.append(ice)
            }

        default:
            break
        }
    }

    // MARK: - ICE Helpers
    private func flushPendingICE() {
        pendingICE.forEach { peerConnection.add($0) }
        pendingICE.removeAll()
    }

    private func sendSignal(
        type: String,
        sdp: String? = nil,
        candidate: String? = nil,
        mid: String? = nil,
        index: Int? = nil
    ) {
        let msg = SignalMessage(
            type: type,
            sdp: sdp,
            candidate: candidate,
            sdpMid: mid,
            sdpMLineIndex: index
        )

        let data = try! JSONEncoder().encode(msg)
        socket.send(text: String(decoding: data, as: UTF8.self))
    }

    // MARK: - End Call
    func endCall() {
        callState = "Call Ended"
        socket.onMessage = nil
        socket.disconnect()
        peerConnection.close()
        peerConnection = nil
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCManager: RTCPeerConnectionDelegate {

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didGenerate candidate: RTCIceCandidate) {

        sendSignal(
            type: "ice",
            candidate: candidate.sdp,
            mid: candidate.sdpMid,
            index: Int(candidate.sdpMLineIndex)
        )

        print("❄️ ICE sent")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didChange newState: RTCIceConnectionState) {
        print("ICE state:", newState.rawValue)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didRemove stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didOpen dataChannel: RTCDataChannel) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
}
