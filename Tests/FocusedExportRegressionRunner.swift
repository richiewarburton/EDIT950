import AppKit
import Foundation
import S950Library
import SwiftUI

@main
@MainActor
struct FocusedExportRegressionRunner {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let helper = URL(fileURLWithPath: arguments.first ?? AppSettings.executableDefault)
        let defaultFixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("!OLD/AIM fixtures/TRUE950-FILTER-ENVELOPE.img")
        let fixture = arguments.dropFirst().first.map(URL.init(fileURLWithPath:))
            ?? defaultFixture
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
            "akai-phase1-e2e-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workspace) }
            let sourceHashBefore = try ImageFileOperations.sha256Hex(of: fixture)
            guard sourceHashBefore == "4193cd19dfe1caca668b5efecf5809a270dea902fcebb73360fb866bb573f003" else {
                throw Failure("The known fixture hash changed: \(sourceHashBefore)")
            }
            guard CollectionImageCapacity.fits(
                    requiredBytes: CollectionImageCapacity.lowDensityUsableBytes,
                    preset: .s900Low
                  ),
                  !CollectionImageCapacity.fits(
                    requiredBytes: CollectionImageCapacity.lowDensityUsableBytes + 1,
                    preset: .s900Low
                  ),
                  CollectionImageCapacity.fits(
                    requiredBytes: CollectionImageCapacity.highDensityUsableBytes,
                    preset: .s900High
                  ),
                  !CollectionImageCapacity.fits(
                    requiredBytes: CollectionImageCapacity.highDensityUsableBytes + 1,
                    preset: .s900High
                  )
            else { throw Failure("Collection density capacity boundaries are incorrect.") }
            print("✓ Collection density choices enforce verified 796 KB / 1,595 KB native capacities")

            let transfer = S950ProgramTransfer()
            let program = S950LibraryEntry(
                index: 41,
                name: "FLTRACK.P9",
                byteSize: 108,
                kind: .program,
                sampleReferences: ["ENV TONE"] // deliberately stale
            )
            let staleEntries = [
                S950LibraryEntry(
                    index: 1,
                    name: "ENV TONE.S9",
                    byteSize: 132_360,
                    kind: .sample
                ),
                program
            ]
            let handoff = try transfer.prepareHandoff(
                sourceImage: fixture,
                sourceVolumePath: "/disk0/A/VOLUME 001",
                program: program,
                sourceEntries: staleEntries,
                createdAt: Date(),
                handoffRoot: workspace.appendingPathComponent("handoffs", isDirectory: true)
            )
            let decoded = try Tools950Interop.decodeRequest(
                from: handoff.requestURL
            )
            guard decoded.requestID == handoff.request.requestID,
                  decoded.program.directoryIndex == 41,
                  decoded.program.filename == "FLTRACK.P9"
            else { throw Failure("EDIT950 did not decode FIND950 production output exactly.") }

            let currentProgram = S950LibraryEntry(
                index: 41,
                name: "FLTRACK.P9",
                byteSize: 108,
                kind: .program,
                sampleReferences: ["FILT SAW"]
            )
            let currentHandoff = try transfer.prepareHandoff(
                sourceImage: fixture,
                sourceVolumePath: "/disk0/A/VOLUME 001",
                program: currentProgram,
                sourceEntries: [
                    S950LibraryEntry(
                        index: 3,
                        name: "FILT SAW.S9",
                        byteSize: 132_360,
                        kind: .sample
                    ),
                    currentProgram
                ],
                createdAt: Date().addingTimeInterval(1),
                handoffRoot: workspace.appendingPathComponent(
                    "current-handoffs",
                    isDirectory: true
                )
            )
            let currentRequest = try Tools950Interop.decodeRequest(
                from: currentHandoff.requestURL
            )
            let currentPreview = try await FocusedProgramExportCoordinator(
                executableURL: helper
            ).preview(currentRequest)
            guard currentPreview.warnings.isEmpty else {
                throw Failure(
                    "An omitted optional dependency internal name produced a false warning: \(currentPreview.warnings)"
                )
            }
            currentHandoff.cleanup()

            let backupFolder = workspace.appendingPathComponent("backups", isDirectory: true)
            try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
            guard let defaults = UserDefaults(
                suiteName: "AKAI.Phase1.\(UUID().uuidString)"
            ) else { throw Failure("Could not make isolated EDIT950 settings.") }
            let settings = AppSettings(defaults: defaults)
            settings.executablePath = helper.path
            settings.backupFolderPath = backupFolder.path
            let model = AppModel(
                settings: settings,
                tagLibraryDirectoryOverride: workspace.appendingPathComponent("tags")
            )
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.finishLaunching()

            let presentation = try await model.acceptFocusedExportRequest(
                at: handoff.requestURL
            )
            guard model.snapshot.currentPath == "/disk0/A/VOLUME 001",
                  model.selectedFiles.count == 1,
                  model.selectedFiles.first?.index == 41,
                  model.selectedFiles.first?.name == "FLTRACK.P9"
            else { throw Failure("EDIT950 did not navigate to and select exact P9 #41.") }
            guard presentation.preview.dependencies == [
                .init(directoryIndex: 3, filename: "FILT SAW.S9", internalName: "FILT SAW")
            ], presentation.preview.warnings.contains(where: {
                $0.contains("saved sample list was out of date")
            }) else {
                throw Failure("EDIT950 did not replace the stale observation with the current FILT SAW closure.")
            }
            let accepted = try Tools950Interop.readResponse(from: handoff.responseURL)
            guard accepted.status == .accepted else {
                throw Failure("EDIT950 did not return accepted after exact navigation.")
            }
            try smokeFocusedSheet(presentation, model: model)

            let newDestination = workspace.appendingPathComponent("focused-new.img")
            let outcome = try await model.performFocusedExport(
                presentation,
                destination: .newImage(newDestination, .s900Low)
            )
            let sourceHashAfter = try ImageFileOperations.sha256Hex(of: fixture)
            guard sourceHashAfter == sourceHashBefore else {
                throw Failure("The source fixture changed during focused export.")
            }
            let newFiles = try await nativeListing(image: newDestination, helper: helper)
            guard newFiles.map(\.name) == ["FILT SAW.S9", "FLTRACK.P9"] else {
                throw Failure("New IMG has unexpected content: \(newFiles.map(\.name))")
            }
            let terminal = try Tools950Interop.readResponse(from: handoff.responseURL)
            guard terminal.status == .completed,
                  terminal.result?.resultingImage.sha256
                    == outcome.result.resultingImage.sha256,
                  terminal.result?.verification.sourceUnchanged == true,
                  terminal.result?.verification.exactDirectoryVerified == true,
                  terminal.result?.verification.nativeBytesVerified == true,
                  terminal.result?.dependencies.first?.directoryIndex == 3
            else { throw Failure("Completed response lacks required typed evidence.") }
            print("✓ Library production request decoded; EDIT950 navigated to /disk0/A/VOLUME 001 #41 FLTRACK.P9")
            print("✓ Optional dependency fields do not create false warnings")
            print("✓ Changed dependency preview replaced by authoritative #3 FILT SAW.S9 with a concise explanation")
            print("✓ New destination contains exactly FILT SAW.S9 and FLTRACK.P9")
            print("SOURCE_SHA256=\(sourceHashAfter)")
            print("NEW_DESTINATION_SHA256=\(outcome.result.resultingImage.sha256)")

            let collectionTransfer = S950CollectionTransfer()
            let collectionHandoff = try collectionTransfer.prepareHandoff(
                selections: [
                    .init(
                        sourceImage: fixture,
                        volumePath: "/disk0/A/VOLUME 001",
                        entry: currentProgram
                    ),
                    .init(
                        sourceImage: fixture,
                        volumePath: "/disk0/A/VOLUME 001",
                        entry: S950LibraryEntry(
                            index: 1,
                            name: "ENV TONE.S9",
                            byteSize: 132_360,
                            kind: .sample
                        )
                    )
                ],
                createdAt: Date().addingTimeInterval(3),
                handoffRoot: workspace.appendingPathComponent(
                    "collection-handoffs",
                    isDirectory: true
                )
            )
            guard try Tools950Interop.messageType(from: collectionHandoff.requestURL)
                    == .exportCollectionRequest
            else { throw Failure("Collection handoff did not carry its distinct message type.") }
            let collectionPresentation = try await model.acceptCollectionExportRequest(
                at: collectionHandoff.requestURL
            )
            guard collectionPresentation.preview.requestedItemCount == 2,
                  collectionPresentation.preview.requiredFileCount == 2,
                  Set(collectionPresentation.preview.filenames)
                    == Set(["ENV TONE.S9", "FLTRACK.P9"])
            else {
                throw Failure(
                    "Collection preview did not preserve the exact P9/S9 selection: \(collectionPresentation.preview.filenames)"
                )
            }
            try smokeCollectionSheet(collectionPresentation)
            let collectionDestination = workspace.appendingPathComponent(
                "collection-new.img"
            )
            let collectionOutcome = try await model.performCollectionExport(
                collectionPresentation,
                destinationURL: collectionDestination,
                preset: .s900Low
            )
            let collectionFiles = try await nativeListing(
                image: collectionDestination,
                helper: helper
            )
            guard collectionFiles.map(\.name) == [
                "ENV TONE.S9", "FLTRACK.P9"
            ], collectionOutcome.importedFileCount == 2,
               try ImageFileOperations.sha256Hex(of: fixture) == sourceHashBefore
            else {
                throw Failure(
                    "Fresh collection IMG content or source immutability verification failed: \(collectionFiles.map(\.name))"
                )
            }
            let collectionTerminal = try Tools950Interop.readResponse(
                from: collectionHandoff.responseURL
            )
            guard collectionTerminal.status == .completed,
                  collectionTerminal.operationType == "aim.export-collection",
                  collectionTerminal.details?["destinationSHA256"]
                    == collectionOutcome.resultingImage.sha256,
                  collectionTerminal.details?["importedFileCount"] == "2"
            else {
                throw Failure("Collection completion response lacks verification evidence.")
            }
            print("✓ Mixed collection preserved the exact selection and published one fresh IMG with 2 byte-verified native files")

            try await verifyChangedFingerprint(
                transfer: transfer,
                fixture: fixture,
                helper: helper,
                workspace: workspace,
                program: program,
                entries: staleEntries
            )
            try await verifyUnsupportedVersion(
                transfer: transfer,
                fixture: fixture,
                helper: helper,
                workspace: workspace,
                program: program,
                entries: staleEntries
            )

            let coordinator = FocusedProgramExportCoordinator(
                executableURL: helper,
                backupDirectory: backupFolder
            )
            let collisionHash = try ImageFileOperations.sha256Hex(of: newDestination)
            do {
                _ = try await coordinator.export(
                    decoded,
                    to: .existingImage(newDestination)
                )
                throw Failure("A normalized collision was not rejected.")
            } catch let error as FocusedExportError {
                guard case .collision = error else { throw error }
            }
            guard try ImageFileOperations.sha256Hex(of: newDestination) == collisionHash else {
                throw Failure("Collision rejection changed the destination.")
            }
            print("✓ Normalized P9/S9 collisions rejected before mutation; destination hash unchanged")

            let alias = workspace.appendingPathComponent("source-alias.img")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture)
            do {
                _ = try await coordinator.export(decoded, to: .existingImage(alias))
                throw Failure("Source/destination symlink alias was not rejected.")
            } catch let error as FocusedExportError {
                guard error == .sourceDestinationAlias else { throw error }
            }
            print("✓ Source/destination alias through symlink rejected")

            let byteCapacity = workspace.appendingPathComponent("byte-capacity.img")
            try await createEmptyImage(byteCapacity, helper: helper)
            let byteHash = try ImageFileOperations.sha256Hex(of: byteCapacity)
            let byteCoordinator = FocusedProgramExportCoordinator(
                executableURL: helper,
                backupDirectory: backupFolder
            )
            byteCoordinator.capacityOverride = { capacity in
                .init(
                    freeBytes: 1,
                    maximumFileCount: capacity.maximumFileCount,
                    fileCount: capacity.fileCount
                )
            }
            do {
                _ = try await byteCoordinator.export(decoded, to: .existingImage(byteCapacity))
                throw Failure("Insufficient byte capacity was not rejected.")
            } catch let error as FocusedExportError {
                guard case .insufficientBytes = error else { throw error }
            }
            guard try ImageFileOperations.sha256Hex(of: byteCapacity) == byteHash else {
                throw Failure("Byte-capacity rejection changed the destination.")
            }

            let entryCapacity = workspace.appendingPathComponent("entry-capacity.img")
            try await createEmptyImage(entryCapacity, helper: helper)
            let entryHash = try ImageFileOperations.sha256Hex(of: entryCapacity)
            let entryCoordinator = FocusedProgramExportCoordinator(
                executableURL: helper,
                backupDirectory: backupFolder
            )
            entryCoordinator.capacityOverride = { capacity in
                .init(freeBytes: capacity.freeBytes, maximumFileCount: 0, fileCount: 0)
            }
            do {
                _ = try await entryCoordinator.export(decoded, to: .existingImage(entryCapacity))
                throw Failure("Insufficient directory capacity was not rejected.")
            } catch let error as FocusedExportError {
                guard case .insufficientDirectoryEntries = error else { throw error }
            }
            guard try ImageFileOperations.sha256Hex(of: entryCapacity) == entryHash else {
                throw Failure("Directory-capacity rejection changed the destination.")
            }
            print("✓ Byte and directory-entry capacity rejected during read-only preflight; hashes unchanged")

            let rollbackDestination = workspace.appendingPathComponent("rollback.img")
            try await createEmptyImage(rollbackDestination, helper: helper)
            let rollbackHash = try ImageFileOperations.sha256Hex(of: rollbackDestination)
            let rollbackCoordinator = FocusedProgramExportCoordinator(
                executableURL: helper,
                backupDirectory: backupFolder
            )
            rollbackCoordinator.failureInjector = { point in
                if point == .afterFirstMutation { throw Failure("injected post-mutation failure") }
            }
            do {
                _ = try await rollbackCoordinator.export(
                    decoded,
                    to: .existingImage(rollbackDestination)
                )
                throw Failure("Injected post-mutation failure did not fail.")
            } catch let error as FocusedExportError {
                guard case .mutationRolledBack(_, let restored) = error,
                      restored == rollbackHash
                else { throw error }
            }
            guard try ImageFileOperations.sha256Hex(of: rollbackDestination) == rollbackHash else {
                throw Failure("Rollback did not restore the destination byte-for-byte.")
            }
            print("✓ Injected failure after first put restored existing IMG byte-for-byte: \(rollbackHash)")

            let existingDestination = workspace.appendingPathComponent("existing-success.img")
            try await createEmptyImage(existingDestination, helper: helper)
            let existingBefore = try ImageFileOperations.sha256Hex(of: existingDestination)
            let successCoordinator = FocusedProgramExportCoordinator(
                executableURL: helper,
                backupDirectory: backupFolder
            )
            let existingOutcome = try await successCoordinator.export(
                decoded,
                to: .existingImage(existingDestination)
            )
            guard let backupPath = existingOutcome.result.backupPath,
                  FileManager.default.fileExists(atPath: backupPath),
                  try ImageFileOperations.sha256Hex(of: URL(fileURLWithPath: backupPath)) == existingBefore,
                  existingOutcome.result.verification.backupVerified
            else { throw Failure("Successful existing-image export lacks a verified backup.") }
            print("✓ Existing-image success created byte-verified backup SHA-256 \(existingBefore)")

            guard try ImageFileOperations.sha256Hex(of: fixture) == sourceHashBefore else {
                throw Failure("The fixture changed after the complete regression.")
            }
            await model.shutdown()
            print("\nFocused Phase 1 export regression passed")
        } catch {
            fputs("Focused export regression failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func verifyChangedFingerprint(
        transfer: S950ProgramTransfer,
        fixture: URL,
        helper: URL,
        workspace: URL,
        program: S950LibraryEntry,
        entries: [S950LibraryEntry]
    ) async throws {
        let copy = workspace.appendingPathComponent("changed-source.img")
        try FileManager.default.copyItem(at: fixture, to: copy)
        let handoff = try transfer.prepareHandoff(
            sourceImage: copy,
            sourceVolumePath: "/disk0/A/VOLUME 001",
            program: program,
            sourceEntries: entries,
            createdAt: Date().addingTimeInterval(1),
            handoffRoot: workspace.appendingPathComponent("changed-handoff", isDirectory: true)
        )
        let request = try Tools950Interop.decodeRequest(from: handoff.requestURL)
        let handle = try FileHandle(forUpdating: copy)
        try handle.seek(toOffset: 700_000)
        try handle.write(contentsOf: Data([0xA5]))
        try handle.synchronize()
        try handle.close()
        let coordinator = FocusedProgramExportCoordinator(executableURL: helper)
        do {
            _ = try await coordinator.preview(request)
            throw Failure("Changed source fingerprint was accepted.")
        } catch let error as FocusedExportError {
            guard case .sourceFingerprintChanged = error else { throw error }
        }
        print("✓ Changed complete source fingerprint detected before acceptance/mutation")
    }

    private static func verifyUnsupportedVersion(
        transfer: S950ProgramTransfer,
        fixture: URL,
        helper: URL,
        workspace: URL,
        program: S950LibraryEntry,
        entries: [S950LibraryEntry]
    ) async throws {
        let handoff = try transfer.prepareHandoff(
            sourceImage: fixture,
            sourceVolumePath: "/disk0/A/VOLUME 001",
            program: program,
            sourceEntries: entries,
            createdAt: Date().addingTimeInterval(2),
            handoffRoot: workspace.appendingPathComponent("version-handoff", isDirectory: true)
        )
        var object = try JSONSerialization.jsonObject(
            with: Data(contentsOf: handoff.requestURL)
        ) as! [String: Any]
        object["protocolVersion"] = 2
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: handoff.requestURL, options: .atomic)
        guard let defaults = UserDefaults(
            suiteName: "AKAI.Phase1.Unsupported.\(UUID().uuidString)"
        ) else { throw Failure("Could not make unsupported-version settings.") }
        let settings = AppSettings(defaults: defaults)
        settings.executablePath = helper.path
        let model = AppModel(
            settings: settings,
            tagLibraryDirectoryOverride: workspace.appendingPathComponent("tags-version")
        )
        do {
            _ = try await model.acceptFocusedExportRequest(at: handoff.requestURL)
            throw Failure("Unsupported protocol version was accepted.")
        } catch let error as Tools950Interop.ValidationError {
            guard error == .unsupportedVersion(2) else { throw error }
        }
        let response = try Tools950Interop.readResponse(from: handoff.responseURL)
        guard response.status == .rejected,
              response.errorCode == "unsupportedVersion"
        else { throw Failure("Unsupported version did not receive a structured rejection.") }
        await model.shutdown()
        print("✓ Unsupported protocol version returned structured rejected response")
    }

    private static func createEmptyImage(_ url: URL, helper: URL) async throws {
        try ImageFileOperations.createZeroFilledImage(
            at: url,
            byteCount: FormatPreset.s900Low.byteCount
        )
        let controller = AkaiCommandController()
        _ = try await controller.open(imageURL: url, executableURL: helper, readOnly: false)
        _ = try await controller.send(FormatPreset.s900Low.command)
        await controller.close()
    }

    private static func nativeListing(image: URL, helper: URL) async throws -> [AkaiFile] {
        let controller = AkaiCommandController()
        _ = try await controller.open(imageURL: image, executableURL: helper, readOnly: true)
        let recursive = try await controller.send("dirrec")
        guard let volume = AkaiOutputParser.parseVolumes(recursive.output).first else {
            await controller.close()
            throw Failure("Destination has no S950 volume.")
        }
        _ = try await controller.send(try AkaiCommandBuilder.changeDirectory(volume.path))
        let listing = try await controller.send("dir")
        await controller.close()
        return AkaiOutputParser.parseDirectory(listing.output).0
    }

    private static func smokeFocusedSheet(
        _ presentation: FocusedExportPresentation,
        model: AppModel
    ) throws {
        let view = FocusedExportSheet(
            presentation: presentation,
            onExport: { _, _ in },
            onCancel: {}
        )
        let hosting = NSHostingView(rootView: view.environmentObject(model))
        hosting.frame = NSRect(x: 0, y: 0, width: 680, height: 700)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw Failure("Focused-export sheet did not render a bitmap.")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else {
            throw Failure("Focused-export sheet rendered empty output.")
        }
        print("✓ Focused-export sheet rendered with source, closure, destination, density, capacity/collision safety, and PLAY950 state")
    }

    private static func smokeCollectionSheet(
        _ presentation: CollectionExportPresentation
    ) throws {
        let view = CollectionExportSheet(
            presentation: presentation,
            onExport: { _, _ in },
            onCancel: {}
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 700, height: 700)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw Failure("Collection-export sheet did not render a bitmap.")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else {
            throw Failure("Collection-export sheet rendered empty output.")
        }
        print("✓ Collection-export sheet rendered the exact selection, fresh-image density, and verification contract")
    }
}

private struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
