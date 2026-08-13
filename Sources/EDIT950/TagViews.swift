import AppKit
import SwiftUI

extension Color {
    init(s950Hex: String) {
        let clean = s950Hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(clean, radix: 16) ?? 0x4A90E2
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    var s950Hex: String {
        let color = NSColor(self).usingColorSpace(.sRGB)
            ?? NSColor(srgbRed: 0.43, green: 0.46, blue: 0.51, alpha: 1)
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}

struct TagChipsView: View {
    let tags: [LibraryTag]

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 5) {
                ForEach(tags) { tag in
                    HStack(spacing: 3) {
                        Circle()
                            .stroke(SuiteTagPalette.colour(for: tag.colorHex), lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                        Text(tag.name).lineLimit(1)
                    }
                    .font(SuiteFont.regular(9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.suiteSlab2, in: RoundedRectangle(cornerRadius: 3))
                }
            }
        }
    }
}

struct ImageTagMenuContent: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.tags.isEmpty {
            Button("Create a Tag…") { model.showTagManager = true }
        } else {
            ForEach(model.tags) { tag in
                Button {
                    model.toggleImageTag(tag)
                } label: {
                    Label(
                        tag.name,
                        systemImage: model.isImageTagAssigned(tag)
                            ? "checkmark.circle.fill" : "circle"
                    )
                }
            }
            Divider()
            Button("Edit Tags…") { model.showTagManager = true }
        }
    }
}

struct FileTagMenuContent: View {
    @EnvironmentObject private var model: AppModel
    let files: [AkaiFile]

    var body: some View {
        if model.tags.isEmpty {
            Button("Create a Tag…") { model.showTagManager = true }
        } else {
            ForEach(model.tags) { tag in
                Button {
                    model.toggleTag(tag, for: files)
                } label: {
                    Label(tag.name, systemImage: symbol(for: tag))
                }
            }
            Divider()
            Button("Edit Tags…") { model.showTagManager = true }
        }
    }

    private func symbol(for tag: LibraryTag) -> String {
        if model.isTagAssignedToAll(tag, files: files) {
            return "checkmark.circle.fill"
        }
        if model.isTagAssignedToAny(tag, files: files) {
            return "minus.circle.fill"
        }
        return "circle"
    }
}

struct TagManagerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("SHARED 950TOOLS TAGS").font(SuiteFont.medium(15)).tracking(2.4)
                Spacer()
                Button("ADD TAG") { model.addTag() }.buttonStyle(SuiteSecondaryButtonStyle())
            }
            if model.tags.isEmpty {
                ContentUnavailableView(
                    "No tags yet",
                    systemImage: "tag",
                    description: Text("Create shared tags for IMG disks, P9 programs and S9 samples.")
                )
            } else {
                List(model.tags) { tag in
                    HStack(spacing: 12) {
                        TagColourChooser(tag: tag)
                        TextField(
                            "Tag name",
                            text: Binding(
                                get: { tag.name },
                                set: { model.updateTag(tag, name: $0) }
                            )
                        )
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.suiteSlab)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            model.deleteTag(tag)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.suiteRed)
                    }
                    .padding(.vertical, 4)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Tags are shared with FIND950 and are never written into IMG, P9 or S9 files.")
                Text(model.tagLibraryFileURL.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(SuiteFont.regular(10))
            .foregroundStyle(Color.suiteUnit)
            HStack {
                Spacer()
                Button("DONE") { dismiss() }
                    .buttonStyle(SuitePrimaryButtonStyle(role: .neutral))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 390)
        .background(Color.suitePanel)
        .onDisappear { NSColorPanel.shared.orderOut(nil) }
    }
}

private struct TagColourChooser: View {
    @EnvironmentObject private var model: AppModel
    let tag: LibraryTag
    @State private var showingPalette = false

    var body: some View {
        Button { showingPalette.toggle() } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(SuiteTagPalette.colour(for: tag.colorHex))
                    .frame(width: 25, height: 18)
                    .overlay { RoundedRectangle(cornerRadius: 3).stroke(Color.suiteRule2) }
                Text("COLOUR")
            }
        }
        .buttonStyle(SuiteSecondaryButtonStyle())
        .popover(isPresented: $showingPalette, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(SuiteTagPalette.groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            SuiteSectionHeader(title: group.title)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 7), count: 10), spacing: 7) {
                                ForEach(group.colours, id: \.self) { hex in
                                    Button {
                                        model.updateTag(tag, colorHex: hex)
                                        showingPalette = false
                                    } label: {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(SuiteTagPalette.colour(for: hex))
                                            .frame(width: 32, height: 25)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(tag.colorHex.uppercased() == hex ? Color.suiteYellow : Color.suiteRule2, lineWidth: tag.colorHex.uppercased() == hex ? 3 : 1)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .help(hex)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .frame(width: 420, height: 360)
            .background(Color.suitePanel)
        }
    }
}
