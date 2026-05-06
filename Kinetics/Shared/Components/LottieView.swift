import SwiftUI
import Lottie

struct LottieView: UIViewRepresentable {
    let filename: String
    var loopMode: LottieLoopMode = .loop
    var animationSpeed: CGFloat = 1.0
    var onComplete: (() -> Void)?

    @Binding var play: Bool

    init(
        filename: String,
        loopMode: LottieLoopMode = .loop,
        speed: CGFloat = 1.0,
        play: Binding<Bool> = .constant(true),
        onComplete: (() -> Void)? = nil
    ) {
        self.filename = filename
        self.loopMode = loopMode
        self.animationSpeed = speed
        self._play = play
        self.onComplete = onComplete
    }

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView()
        view.animation = LottieAnimation.named(filename, bundle: Bundle.main)
        view.loopMode = loopMode
        view.animationSpeed = animationSpeed
        view.contentMode = .scaleAspectFit
        view.backgroundBehavior = .pauseAndRestore
        if play {
            view.play { finished in
                if finished { onComplete?() }
            }
        }
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        uiView.loopMode = loopMode
        uiView.animationSpeed = animationSpeed
        if play && !uiView.isAnimationPlaying {
            uiView.play { finished in
                if finished { onComplete?() }
            }
        } else if !play && uiView.isAnimationPlaying {
            uiView.stop()
        }
    }
}

extension LottieView {
    static func confetti(play: Binding<Bool> = .constant(true)) -> LottieView {
        LottieView(filename: "confetti", loopMode: .playOnce, play: play)
    }

    static func fireStreak() -> LottieView {
        LottieView(filename: "fireStreak", loopMode: .loop)
    }

    static func heartbeat() -> LottieView {
        LottieView(filename: "heartbeat", loopMode: .loop)
    }

    static func locationPin() -> LottieView {
        LottieView(filename: "locationPin", loopMode: .loop)
    }

    static func runAnimation() -> LottieView {
        LottieView(filename: "runAnimation", loopMode: .loop)
    }
}
