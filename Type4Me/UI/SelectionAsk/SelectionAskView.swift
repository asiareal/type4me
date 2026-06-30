import AppKit
import SwiftUI

struct SelectionAskView: View {
    let state: SelectionAskState
    let onClose: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(red: 0.96, green: 0.95, blue: 0.93))

            VStack(spacing: 0) {
                header
                Divider().opacity(0.5)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        questionSection
                        answerSection
                    }
                    .padding(.horizontal, 34)
                    .padding(.vertical, 26)
                }
            }
        }
        .padding(10)
    }

    private var header: some View {
        HStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                Text(L("随便问", "Ask Anything"))
                    .font(.system(size: 24, weight: .bold))
            }
            .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .frame(height: 74)
    }

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "questionmark.bubble")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                Text(state.question.isEmpty ? L("正在识别问题...", "Recognizing question...") : state.question)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.18))
                Spacer()
                copyButton(text: state.selectedText, systemImage: "doc.on.doc")
                    .disabled(state.selectedText.isEmpty)
            }

            HStack(alignment: .top, spacing: 14) {
                Rectangle()
                    .fill(Color(red: 0.78, green: 0.76, blue: 0.72))
                    .frame(width: 2)
                Text(state.selectedText.isEmpty ? L("正在读取选中文本...", "Reading selected text...") : state.selectedText)
                    .font(.system(size: 18))
                    .foregroundStyle(Color(red: 0.48, green: 0.48, blue: 0.48))
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
            .padding(.leading, 34)
        }
    }

    private var answerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                Text(L("回答", "Answer"))
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                if let answer = answerText {
                    copyButton(text: answer, systemImage: "doc.on.doc")
                }
            }
            .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
            .padding(.horizontal, 24)
            .frame(height: 52)

            Divider()

            Group {
                switch state.phase {
                case .idle, .loading:
                    loadingView
                case .answered(let markdown):
                    markdownView(markdown)
                case .error(let message):
                    errorView(message)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
        )
    }

    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(L("正在思考...", "Thinking..."))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(red: 0.42, green: 0.42, blue: 0.42))
        }
        .frame(minHeight: 220, alignment: .center)
        .frame(maxWidth: .infinity)
    }

    private func markdownView(_ markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(MarkdownRenderer.displayBlocks(from: markdown).enumerated()), id: \.offset) { _, block in
                Text(MarkdownRenderer.attributedString(from: block))
                    .font(.system(size: 19))
                    .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.16))
                    .lineSpacing(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TF.settingsAccentRed)
            Text(message)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(red: 0.42, green: 0.18, blue: 0.15))
                .textSelection(.enabled)
        }
        .frame(minHeight: 180, alignment: .topLeading)
    }

    private var answerText: String? {
        if case .answered(let answer) = state.phase {
            return answer
        }
        return nil
    }

    private func copyButton(text: String, systemImage: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(red: 0.46, green: 0.46, blue: 0.46))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }
}
