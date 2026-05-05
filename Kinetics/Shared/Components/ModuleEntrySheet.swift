import SwiftUI

// MARK: - ModuleEntrySheet

/// Bottom sheet shown when the user taps a sport module card.
/// Presents two options before entering the module:
///   1. Start a live camera session.
///   2. Import and analyze a video from the photo library.
struct ModuleEntrySheet: View {

    let sport: SportType
    let onLiveSession: () -> Void
    let onAnalyzeVideo: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var accent: Color { Color.moduleColor(for: sport) }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(.white.opacity(0.18))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Sport identity row
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: sport.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(sport.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Choose how to train")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // Option 1: Live session
            Button(action: onLiveSession) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accent.opacity(0.14))
                            .frame(width: 40, height: 40)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start Live Session")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Real-time camera analysis")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.42))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.28))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.kineticsMidGray)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accent.opacity(0.18), lineWidth: 0.75)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            // Option 2: Analyze a video
            Button(action: onAnalyzeVideo) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.kineticsPurple.opacity(0.14))
                            .frame(width: 40, height: 40)
                        Image(systemName: "film.stack")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.kineticsPurple)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Analyze a Video")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Import from your photo library")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.42))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.28))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.kineticsMidGray)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.kineticsPurple.opacity(0.18), lineWidth: 0.75)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ModuleEntrySheet") {
    Color.kineticsBackground
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ModuleEntrySheet(
                sport: .striking,
                onLiveSession: {},
                onAnalyzeVideo: {}
            )
            .presentationDetents([.height(260)])
            .presentationBackground(Color.kineticsDark)
            .presentationCornerRadius(24)
        }
}
#endif
