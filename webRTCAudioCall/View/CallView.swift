//
//  CallView.swift
//  webRTCAudioCall
//
//  Created by Sumit Raj Chingari on 29/01/26.
//

import SwiftUI


struct CallView: View {

    @StateObject private var rtc = WebRTCManager()

    var body: some View {
        VStack(spacing: 25) {

            Text("WebRTC Audio Call")
                .font(.largeTitle)
                .bold()

            Text(rtc.callState)
                .foregroundColor(.gray)

            Button("Start Call") {
                rtc.startCall()
            }
            .buttonStyle(.borderedProminent)

            Button("End Call") {
                rtc.endCall()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}


#Preview {
    CallView()
}
