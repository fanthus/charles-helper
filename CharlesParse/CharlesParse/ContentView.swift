import SwiftUI
import UniformTypeIdentifiers

enum ParseState {
    case idle
    case loading
    case success(ChlsParseResponse, URL)
    case error(String)
}

struct ContentView: View {
    @State private var state: ParseState = .idle
    @State private var selectedPartIndex = 0
    @State private var selectedTab = 0
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            bottomBar
        }
        .frame(minWidth: 720, minHeight: 480)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack {
            Text(fileTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if case .loading = state {
                ProgressView()
                    .controlSize(.small)
            }

            Button("打开…") {
                openFilePanel()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            dropZone
        case .loading:
            dropZone
                .overlay {
                    ProgressView("正在解析…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("重新选择文件") { openFilePanel() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        case .success(let response, _):
            resultView(response: response)
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )

            VStack(spacing: 8) {
                Image(systemName: "doc.badge.arrow.up")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("拖入 .chls 文件")
                    .font(.title3)
                Text("或点击右上角「打开…」")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func resultView(response: ChlsParseResponse) -> some View {
        if response.parts.isEmpty {
            Text("未找到 application/x-gzip 段")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                if response.parts.count > 1 {
                    List(response.parts, selection: $selectedPartIndex) { part in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("段 #\(part.index + 1)")
                                .font(.headline)
                            Text("\(part.gzipSize) 字节 gzip")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(part.index)
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)
                }

                VStack(spacing: 0) {
                    Picker("视图", selection: $selectedTab) {
                        Text("解压文本").tag(0)
                        Text("表单字段").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(12)

                    if let part = currentPart(in: response) {
                        if selectedTab == 0 {
                            TextEditor(text: .constant(part.decompressedText))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                        } else {
                            Table(part.fieldRows) {
                                TableColumn("字段") { row in
                                    Text(row.key)
                                        .textSelection(.enabled)
                                }
                                TableColumn("值") { row in
                                    Text(row.value)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            if let part = currentPartFromState() {
                Text("gzip \(part.gzipSize) 字节 · 解压 \(part.decompressedText.utf8.count) 字节")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("复制文本") { copyDecompressedText() }
                .disabled(currentPartFromState() == nil)
            Button("复制字段 JSON") { copyFieldsJSON() }
                .disabled(currentPartFromState() == nil)
            Button("导出 gzip…") { exportGzip() }
                .disabled(currentPartFromState() == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var fileTitle: String {
        switch state {
        case .idle, .loading:
            return "Charles CHLS 解析"
        case .success(_, let url):
            return url.lastPathComponent
        case .error:
            return "解析失败"
        }
    }

    private func currentPart(in response: ChlsParseResponse) -> ChlsGzipPart? {
        response.parts.first { $0.index == selectedPartIndex }
            ?? response.parts.first
    }

    private func currentPartFromState() -> ChlsGzipPart? {
        guard case .success(let response, _) = state else { return nil }
        return currentPart(in: response)
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "chls") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选择 Charles 会话文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        parseFile(url: url)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            DispatchQueue.main.async {
                parseFile(url: url)
            }
        }
        return true
    }

    private func parseFile(url: URL) {
        guard url.pathExtension.lowercased() == "chls" else {
            state = .error("请选择 .chls 文件")
            return
        }
        state = .loading
        selectedPartIndex = 0
        Task {
            do {
                let response = try await PythonRunner.parse(chlsURL: url)
                await MainActor.run {
                    if let first = response.parts.first {
                        selectedPartIndex = first.index
                    }
                    state = .success(response, url)
                }
            } catch {
                await MainActor.run {
                    state = .error(error.localizedDescription)
                }
            }
        }
    }

    private func copyDecompressedText() {
        guard let part = currentPartFromState() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(part.decompressedText, forType: .string)
    }

    private func copyFieldsJSON() {
        guard let part = currentPartFromState() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(part.fieldsJSON, forType: .string)
    }

    private func exportGzip() {
        guard let part = currentPartFromState(), let data = part.gzipData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gz") ?? .data]
        panel.nameFieldStringValue = "payload.gz"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }
}

#Preview {
    ContentView()
}
