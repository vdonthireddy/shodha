import SwiftUI

struct CuteMascotView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        ZStack {
            // Background gradient bubble
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.38, green: 0.45, blue: 0.98),
                            Color(red: 0.65, green: 0.40, blue: 0.95),
                            Color(red: 0.96, green: 0.48, blue: 0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Subtle inner glow
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
            
            // Mascot Face elements
            VStack(spacing: 2) {
                // Little antennae sparkle at the top
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.yellow.opacity(0.95))
                    .shadow(color: .yellow.opacity(0.6), radius: 3)
                    .offset(y: -2)
                
                // Eyes & Blush
                HStack(spacing: 16) {
                    // Left Eye & Blush
                    VStack(spacing: 2) {
                        EyeView(isBlinking: appState.isBlinking)
                        Circle()
                            .fill(Color(red: 1.0, green: 0.5, blue: 0.6).opacity(0.7))
                            .frame(width: 8, height: 4)
                    }
                    
                    // Right Eye & Blush
                    VStack(spacing: 2) {
                        EyeView(isBlinking: appState.isBlinking)
                        Circle()
                            .fill(Color(red: 1.0, green: 0.5, blue: 0.6).opacity(0.7))
                            .frame(width: 8, height: 4)
                    }
                }
                .offset(y: 1)
                
                // Mouth
                if appState.isSpeaking {
                    // Animated talking mouth driven by wavePhase
                    Ellipse()
                        .fill(Color.white)
                        .frame(width: 10, height: appState.wavePhase == 1.0 ? 10 : 6)
                        .overlay(
                            Ellipse()
                                .fill(Color(red: 0.9, green: 0.3, blue: 0.4))
                                .frame(width: 6, height: appState.wavePhase == 1.0 ? 6 : 3)
                                .offset(y: 1.5)
                        )
                        .offset(y: 1)
                } else {
                    // Cute resting smile
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 5, y: 5))
                    }
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 10, height: 5)
                    .offset(y: 1)
                }
            }
        }
    }
}

private struct EyeView: View {
    let isBlinking: Bool
    
    var body: some View {
        ZStack {
            if isBlinking {
                // Closed eye line
                Capsule()
                    .fill(Color.white)
                    .frame(width: 9, height: 2)
            } else {
                // Open sparkling eye
                Circle()
                    .fill(Color(red: 0.12, green: 0.1, blue: 0.25))
                    .frame(width: 9, height: 9)
                    .overlay(
                        // Eye glint highlight
                        Circle()
                            .fill(Color.white)
                            .frame(width: 3.5, height: 3.5)
                            .offset(x: -2, y: -2)
                    )
            }
        }
        .frame(width: 9, height: 9)
    }
}
