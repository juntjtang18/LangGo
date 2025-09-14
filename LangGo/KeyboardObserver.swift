import Combine
import UIKit

final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        let willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        let willHide   = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)

        Publishers.Merge(willChange, willHide)
            .compactMap { note -> (CGRect, TimeInterval, UIView.AnimationOptions)? in
                guard
                    let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                    let dur = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
                    let curveRaw = note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int
                else { return nil }
                let opts = UIView.AnimationOptions(rawValue: UInt(curveRaw << 16))
                return (end, dur, opts)
            }
            .sink { [weak self] endFrame, duration, options in
                guard let self = self else { return }
                let window = UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                    .first

                // Convert to the key window’s coords for accuracy (handles rotation, split view, etc.)
                let inWindow = window?.convert(endFrame, from: nil) ?? endFrame
                let maxY = window?.bounds.maxY ?? UIScreen.main.bounds.maxY
                let overlap = max(0, maxY - inWindow.minY)  // distance from bottom to keyboard top

                UIView.animate(withDuration: duration, delay: 0, options: options) {
                    self.height = overlap
                }
            }
            .store(in: &cancellables)
    }
}
