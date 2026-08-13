import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CollectionExportPreview: Equatable {
    let requestedItemCount: Int
    let sourceCount: Int
    let requiredBytes: UInt64
    let requiredFileCount: Int
    let filenames: [String]
    let warnings: [String]
}

struct CollectionExportPresentation: Identifiable, Equatable {
    var id: UUID { request.requestID }
    let requestURL: URL
    let request: Tools950Interop.CollectionRequest
    let preview: CollectionExportPreview
}

struct CollectionExportOutcome: Equatable {
    let resultingImage: Tools950Interop.Source
    let resolvedVolumePath: String
    let importedFileCount: Int
    let sourceSHA256s: [String]
    let warnings: [String]
}

enum CollectionImageCapacity {
    // Verified against freshly formatted S950 floppy images. Both formats use
    // 1,024-byte allocation blocks; filesystem metadata consumes the balance.
    static let lowDensityUsableBytes: UInt64 = 0x031c * 1_024
    static let highDensityUsableBytes: UInt64 = 0x063b * 1_024

    static func usableBytes(for preset: FormatPreset) -> UInt64? {
        switch preset {
        case .s900Low: lowDensityUsableBytes
        case .s900High: highDensityUsableBytes
        default: nil
        }
    }

    static func fits(requiredBytes: UInt64, preset: FormatPreset) -> Bool {
        usableBytes(for: preset).map { requiredBytes <= $0 } ?? false
    }
}

struct CollectionExportSheet: View {
    let presentation: CollectionExportPresentation
    let onExport: (URL, FormatPreset) -> Void
    let onCancel: () -> Void

    @State private var density: FormatPreset = .s900High
    @State private var destinationURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.suiteAmber)
                VStack(alignment: .leading, spacing: 3) {
                    Text("EXPORT COLLECTION TO FRESH IMG")
                        .font(SuiteFont.medium(15)).tracking(2.1)
                    Text("EDIT950 re-read every source and verified the exact selected native files.")
                        .font(SuiteFont.regular(11))
                        .foregroundStyle(Color.suiteUnit)
                }
            }

            GroupBox("Verified exact selection") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                    GridRow {
                        Text("Sources").foregroundStyle(Color.suiteUnit)
                        Text("\(presentation.preview.sourceCount) IMG file(s)")
                    }
                    GridRow {
                        Text("Requested").foregroundStyle(Color.suiteUnit)
                        Text("\(presentation.preview.requestedItemCount) collected entries")
                    }
                    GridRow {
                        Text("Result").foregroundStyle(Color.suiteUnit)
                        Text("\(presentation.preview.requiredFileCount) unique P9/S9 files · \(Int64(presentation.preview.requiredBytes).formattedByteCount)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Exact native files") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(presentation.preview.filenames, id: \.self) { filename in
                            Text(filename).font(SuiteFont.regular(11))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(150, CGFloat(max(1, presentation.preview.filenames.count)) * 19))
            }

            if !presentation.preview.warnings.isEmpty {
                GroupBox("Source information") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(presentation.preview.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "info.circle.fill")
                                .foregroundStyle(Color.suiteBlue)
                        }
                    }
                }
            }

            Picker("S950 density", selection: $density) {
                Text("Low density · 800 KB")
                    .tag(FormatPreset.s900Low)
                    .disabled(!fits(.s900Low))
                Text("High density · 1.6 MB")
                    .tag(FormatPreset.s900High)
                    .disabled(!fits(.s900High))
            }
            .pickerStyle(.radioGroup)

            if !fits(.s900Low), fits(.s900High) {
                Label(
                    "This collection needs High Density; it exceeds the 796 KB native capacity of a fresh Low Density IMG.",
                    systemImage: "externaldrive.badge.exclamationmark"
                )
                .font(SuiteFont.regular(10))
                .foregroundStyle(Color.suiteUnit)
            }

            HStack(spacing: 10) {
                Text(destinationURL?.path ?? "No fresh IMG destination selected")
                    .lineLimit(1)
                    .foregroundStyle(destinationURL == nil ? .secondary : .primary)
                Spacer()
                Button("CHOOSE NEW IMG…") { chooseDestination() }
                    .buttonStyle(SuiteSecondaryButtonStyle())
            }

            Label(
                "Only the listed files are copied; P9 sample dependencies are not added automatically. The destination must not already exist. EDIT950 formats a temporary image, checks real free blocks and directory slots, imports samples before programs, re-exports every native file for byte comparison, then publishes the IMG atomically.",
                systemImage: "checkmark.shield.fill"
            )
            .font(SuiteFont.regular(10))
            .foregroundStyle(Color.suiteUnit)

            HStack {
                Spacer()
                Button("CANCEL", role: .cancel) { onCancel() }
                    .buttonStyle(SuiteSecondaryButtonStyle())
                Button("EXPORT AND VERIFY") {
                    guard let destinationURL else { return }
                    onExport(destinationURL, density)
                }
                .buttonStyle(SuitePrimaryButtonStyle(role: .neutral))
                .disabled(destinationURL == nil || !fits(density))
            }
        }
        .padding(22)
        .frame(width: 700)
        .interactiveDismissDisabled()
    }

    private func fits(_ preset: FormatPreset) -> Bool {
        CollectionImageCapacity.fits(
            requiredBytes: presentation.preview.requiredBytes,
            preset: preset
        )
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.title = "Create Collection S950 IMG"
        panel.prompt = "Choose"
        panel.nameFieldStringValue = "FIND950 COLLECTION.img"
        panel.allowedContentTypes = [UTType(filenameExtension: "img") ?? .data]
        if panel.runModal() == .OK, let url = panel.url {
            destinationURL = url
        }
    }
}
