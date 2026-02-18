import SwiftUI

struct OverlayView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerBar
            messageArea
            footerBar
        }
        .padding(10)
        .frame(minWidth: 460, idealWidth: 500, maxWidth: 540)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.22), lineWidth: 0.8)
        )
        .padding(6)
    }

    private var headerBar: some View {
        HStack {
            Label(model.agentName, systemImage: "waveform")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.messages) { message in
                        messageBubble(message)
                    }
                    liveTranscriptBubble
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 2)
                .padding(.top, 2)
                .padding(.bottom, 0)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: model.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: model.messages.last?.text) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: model.transcript) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .assistant { Spacer(minLength: 24) }
            Text(message.text)
                .font(.subheadline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    message.role == .user ? .blue.opacity(0.20) : .white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            if message.role == .user { Spacer(minLength: 24) }
        }
        .id(message.id)
    }

    @ViewBuilder
    private var liveTranscriptBubble: some View {
        if let live = model.liveTranscript {
            HStack {
                Text(live)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 24)
            }
            .id("live-transcript")
        } else if model.messages.isEmpty {
            Text("(press \u{2303}\u{2325} Space and speak)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
    }

    private var footerBar: some View {
        HStack {
            Spacer()
            Text("Channel: openclaw-vox")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if model.liveTranscript != nil {
            proxy.scrollTo("live-transcript", anchor: .bottom)
        } else if let last = model.messages.last?.id {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }
}
