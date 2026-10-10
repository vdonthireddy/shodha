import SwiftUI
import AppKit

struct AvatarView: View {
    @ObservedObject var appState: AppState
    var onToggleDialog: () -> Void
    
    var body: some View {
        ZStack {
            // Animated Sound Ripple Waves when speaking
            if appState.isSpeaking {
                Circle()
                    .stroke(Color.cyan.opacity(appState.wavePhase == 1.0 ? 0.3 : 0.7), lineWidth: 2.5)
                    .frame(width: 66, height: 66)
                    .scaleEffect(appState.wavePhase == 1.0 ? 1.35 : 1.1)
            }
            
            // Outer shadow ring
            Circle()
                .fill(Color.black.opacity(0.18))
                .frame(width: 66, height: 66)
                .blur(radius: 6)
                .offset(y: 4)
            
            // Avatar Body
            Group {
                if let customImage = appState.activeAvatarImage {
                    Image(nsImage: customImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: appState.isSpeaking
                                            ? [.cyan, .purple]
                                            : [.white.opacity(0.85), .white.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: appState.isSpeaking ? 3.0 : 2.0
                                )
                        )
                } else {
                    CuteMascotView(appState: appState)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: appState.isSpeaking
                                            ? [.yellow, .pink]
                                            : [.white.opacity(0.85), .white.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: appState.isSpeaking ? 3.0 : 2.0
                                )
                        )
                }
            }
            .scaleEffect(appState.isHovering ? 1.06 : (appState.isSpeaking ? 1.03 : 1.0))
            
            // Speaking indicator badge or Mute badge
            if appState.isMuted {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(3.5)
                    .background(Color.red.opacity(0.85))
                    .clipShape(Circle())
                    .offset(x: 22, y: 22)
            } else if appState.isSpeaking {
                Image(systemName: "waveform")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(3.5)
                    .background(Color.cyan.opacity(0.9))
                    .clipShape(Circle())
                    .offset(x: 22, y: 22)
            }
        }
        .frame(width: 80, height: 80)
        .contentShape(Circle())
        .onHover { hovering in
            appState.isHovering = hovering
        }
        .contextMenu {
            Button(appState.isDialogVisible ? "Hide Echo Box" : "Show Echo Box") {
                onToggleDialog()
            }
            Divider()
            Button("🌟 Cute Buddy Mascot") {
                appState.selectAvatar(id: nil)
            }
            Button("📷 Add Photos from Mac...") {
                appState.promptChoosePhotos()
            }
            Divider()
            Button("🔊 Replay Last Words") {
                appState.replayLastText()
            }
            Button(appState.isMuted ? "Unmute Voice" : "Mute Voice") {
                appState.isMuted.toggle()
            }
            Divider()
            Button("Quit Shodha") {
                NSApp.terminate(nil)
            }
        }
    }
}
