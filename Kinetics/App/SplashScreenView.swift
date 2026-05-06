import SwiftUI

// MARK: - SplashScreenView

struct SplashScreenView: View {

    var onComplete: () -> Void

    // Skeleton animation states
    @State private var skeletonScale: CGFloat = 0.7
    @State private var skeletonOpacity: Double = 0
    @State private var skeletonBlur: CGFloat = 20
    @State private var glowOpacity: Double = 0
    @State private var glowPulse: Bool = false

    // Scan line
    @State private var scanLineY: CGFloat = -300
    @State private var scanLineOpacity: Double = 0

    // Text
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 30
    @State private var letterSpacing: CGFloat = 2

    // Tagline
    @State private var taglineOpacity: Double = 0

    // Exit
    @State private var exitOpacity: Double = 1

    var body: some View {
        ZStack {
            Color(hex: "#0D0D0D").ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    // Glow halo behind skeleton
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(hex: "#00C2FF").opacity(glowPulse ? 0.22 : 0.12),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 180
                            )
                        )
                        .frame(width: 360, height: 360)
                        .opacity(glowOpacity)
                        .animation(
                            glowOpacity > 0
                                ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                                : .default,
                            value: glowPulse
                        )

                    // Skeleton image
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .colorMultiply(Color(hex: "#00C2FF"))
                        .opacity(skeletonOpacity)
                        .scaleEffect(skeletonScale)
                        .blur(radius: skeletonBlur)

                    // Scan line sweep
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color(hex: "#00C2FF").opacity(0.6),
                                    Color(hex: "#39FF14").opacity(0.4),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 260, height: 8)
                        .offset(y: scanLineY)
                        .opacity(scanLineOpacity)
                        .clipped()
                }
                .frame(height: 280)

                // KINETICS wordmark
                VStack(spacing: 8) {
                    Text("KINETICS")
                        .font(.system(size: 32, weight: .black))
                        .kerning(letterSpacing)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "#00C2FF"), Color(hex: "#39FF14")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .opacity(textOpacity)
                        .offset(y: textOffset)

                    Text("AI PERFORMANCE COACH")
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(3)
                        .foregroundColor(Color(hex: "#00C2FF").opacity(0.6))
                        .opacity(taglineOpacity)
                }
                .padding(.top, 16)

                Spacer()
            }
        }
        .opacity(exitOpacity)
        .onAppear { runSequence() }
    }

    private func runSequence() {
        // 1. Skeleton materializes from blur
        withAnimation(.easeOut(duration: 0.9)) {
            skeletonOpacity = 1
            skeletonScale = 1
            skeletonBlur = 0
        }

        // 2. Glow fades in and starts pulsing
        withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
            glowOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            glowPulse = true
        }

        // 3. Scan line sweeps top to bottom
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            scanLineOpacity = 1
            withAnimation(.easeInOut(duration: 0.55)) {
                scanLineY = 130
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeOut(duration: 0.2)) {
                scanLineOpacity = 0
            }
        }

        // 4. KINETICS text slides up
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.85)) {
            textOpacity = 1
            textOffset = 0
            letterSpacing = 8
        }

        // 5. Tagline fades in
        withAnimation(.easeOut(duration: 0.4).delay(1.2)) {
            taglineOpacity = 1
        }

        // 6. Everything fades out
        withAnimation(.easeIn(duration: 0.45).delay(2.1)) {
            exitOpacity = 0
        }

        // 7. Notify parent
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.65) {
            onComplete()
        }
    }
}
