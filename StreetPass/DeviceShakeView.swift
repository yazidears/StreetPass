import SwiftUI

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

struct DeviceShakeView: UIViewRepresentable {
    func makeUIView(context: Context) -> ShakeReportingView {
        let view = ShakeReportingView()
        return view
    }

    func updateUIView(_ uiView: ShakeReportingView, context: Context) {}

    class ShakeReportingView: UIView {
        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            becomeFirstResponder()
        }

        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            super.motionEnded(motion, with: event)
            if motion == .motionShake {
                NotificationCenter.default.post(name: .deviceDidShake, object: nil)
            }
        }
    }
}
