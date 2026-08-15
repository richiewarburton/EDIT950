import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
struct InteractionRegressionRunner {
    static func main() async {
        do {
            try SuiteFontGate.registerFontsForSmokeTests()
        } catch {
            fputs("Interaction regression setup failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        let executablePath = CommandLine.arguments.dropFirst().first
            ?? AppSettings.executableDefault
        let retainedImagePath = CommandLine.arguments.dropFirst(2).first
        let markerFixturePath = ProcessInfo.processInfo.environment[
            "AKAI_MARKER_WAV_FIXTURE"
        ]
        let nativeLoopFixturePath = ProcessInfo.processInfo.environment[
            "AKAI_NATIVE_LOOP_S9_FIXTURE"
        ]
        let executable = URL(fileURLWithPath: executablePath)
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("akai-interaction-\(UUID().uuidString)", isDirectory: true)
        let image = workspace.appendingPathComponent("interaction.img")
        let hardDiskImage = workspace.appendingPathComponent("s950-hard-disk.img")
        let wav = workspace.appendingPathComponent("SELECTION.wav")
        let markerWAV = workspace.appendingPathComponent("MARKERS.wav")
        let nativeDirectory = workspace.appendingPathComponent("native", isDirectory: true)
        let markerDirectory = workspace.appendingPathComponent("markers-native", isDirectory: true)
        let copiedDirectory = workspace.appendingPathComponent("copied", isDirectory: true)
        let programBeforeNewSampleDirectory = workspace.appendingPathComponent(
            "program-before-new-sample",
            isDirectory: true
        )
        let programAfterNewSampleDirectory = workspace.appendingPathComponent(
            "program-after-new-sample",
            isDirectory: true
        )
        let audioEditor = workspace.appendingPathComponent(
            "Test Audio Editor.app",
            isDirectory: true
        )
        let seedingController = AkaiCommandController()
        let editorLaunchLog = workspace.appendingPathComponent("editor-launched")

        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: nativeDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: markerDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: copiedDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: programBeforeNewSampleDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: programAfterNewSampleDirectory,
                withIntermediateDirectories: true
            )
            try createTestApplication(at: audioEditor, launchLog: editorLaunchLog)
            defer { try? FileManager.default.removeItem(at: workspace) }
            try ImageFileOperations.createZeroFilledImage(
                at: image,
                byteCount: FormatPreset.s900Low.byteCount
            )
            try writeTestWAV(to: wav)
            if let markerFixturePath {
                try FileManager.default.copyItem(
                    at: URL(fileURLWithPath: markerFixturePath),
                    to: markerWAV
                )
            } else {
                try FileManager.default.copyItem(at: wav, to: markerWAV)
                try appendCueMarkers([500, 1_500], to: markerWAV)
            }

            _ = try await seedingController.open(
                imageURL: image,
                executableURL: executable,
                readOnly: false
            )
            _ = try await seedingController.send(FormatPreset.s900Low.command)
            _ = try await seedingController.send(
                try AkaiCommandBuilder.localDirectory(workspace.path)
            )
            _ = try await seedingController.send("wav2sample9 SELECTION.wav")
            let sampleListing = try await seedingController.send("dir")
            guard let sample = AkaiOutputParser.parseDirectory(sampleListing.output).0.first else {
                throw RegressionFailure("Could not seed an S9 sample.")
            }
            _ = try await seedingController.send(
                try AkaiCommandBuilder.localDirectory(nativeDirectory.path)
            )
            _ = try await seedingController.send(
                try AkaiCommandBuilder.exportNative(index: sample.index)
            )
            guard let nativeSample = try FileManager.default.contentsOfDirectory(
                at: nativeDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).first(where: { $0.pathExtension.caseInsensitiveCompare("s9") == .orderedSame }) else {
                throw RegressionFailure("Could not create the native S9 seed.")
            }
            let programSeed = nativeDirectory.appendingPathComponent("DELETEP9.P9")
            try FileManager.default.copyItem(at: nativeSample, to: programSeed)
            _ = try await seedingController.send(
                try AkaiCommandBuilder.importNative(filename: programSeed.lastPathComponent)
            )
            if let nativeLoopFixturePath {
                let source = URL(fileURLWithPath: nativeLoopFixturePath)
                let destination = nativeDirectory.appendingPathComponent(
                    source.lastPathComponent
                )
                try FileManager.default.copyItem(at: source, to: destination)
                _ = try await seedingController.send(
                    try AkaiCommandBuilder.importNative(
                        filename: destination.lastPathComponent
                    )
                )
            }
            await seedingController.close()

            guard let defaults = UserDefaults(
                suiteName: "EDIT950.InteractionRegression.\(UUID().uuidString)"
            ) else {
                throw RegressionFailure("Could not create isolated test settings.")
            }
            let standardDefaults = UserDefaults.standard
            let previousRecentImages = standardDefaults.object(
                forKey: "recentImages"
            )
            standardDefaults.set([image.path], forKey: "recentImages")
            defer {
                if let previousRecentImages {
                    standardDefaults.set(previousRecentImages, forKey: "recentImages")
                } else {
                    standardDefaults.removeObject(forKey: "recentImages")
                }
            }
            let settings = AppSettings(defaults: defaults)
            settings.executablePath = executable.path
            settings.backupBeforeDestructive = false
            settings.audioEditorPath = audioEditor.path
            let model = AppModel(
                settings: settings,
                tagLibraryDirectoryOverride: workspace.appendingPathComponent("tags")
            )
            let undoHistory = SuiteUndoCoordinator()
            let undoManager = undoHistory.manager
            model.undoManager = undoManager
            let suitePreferences = SuitePreferences(
                app: .edit,
                defaultInspectorVisible: false,
                defaults: defaults
            )
            guard suitePreferences.zoom == .oneHundred else {
                throw RegressionFailure("EDIT950 display zoom did not default to 100%.")
            }
            suitePreferences.zoomIn()
            guard suitePreferences.zoom == .oneHundredFifty else {
                throw RegressionFailure("Zoom In did not advance EDIT950 to 150%.")
            }
            suitePreferences.zoomIn()
            suitePreferences.zoomIn()
            guard suitePreferences.zoom == .twoHundred else {
                throw RegressionFailure("EDIT950 display zoom exceeded its 200% maximum.")
            }
            suitePreferences.zoomOut()
            guard suitePreferences.zoom == .oneHundredFifty else {
                throw RegressionFailure("Zoom Out did not return EDIT950 to 150%.")
            }
            let zoomedEditorSize = ExternalSampleEditSheet.presentationSize(
                for: suitePreferences.zoom
            )
            guard zoomedEditorSize == CGSize(width: 1_080, height: 630) else {
                throw RegressionFailure(
                    "The sample editor did not inherit EDIT950's 150% display zoom."
                )
            }
            let zoomedProgramEditorSize = P9EditorSheet.presentationSize(
                for: suitePreferences.zoom
            )
            guard zoomedProgramEditorSize
                    == CGSize(width: 1_860, height: 1_200) else {
                throw RegressionFailure(
                    "The program editor did not inherit EDIT950's 150% display zoom."
                )
            }
            suitePreferences.zoom = .oneHundred
            print("✓ Display, sample editor and program editor zoom from 50–200%")

            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.finishLaunching()
            NSApplication.shared.activate(ignoringOtherApps: true)
            let root = MainView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(suitePreferences)
                .frame(width: 1180, height: 760)
            let hostingView = NSHostingView(rootView: root)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(hostingView)
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKey()

            var openingScreenPNGs = Set<Data>()
            for zoom in SuiteZoomLevel.allCases {
                suitePreferences.zoom = zoom
                try await Task.sleep(nanoseconds: 80_000_000)
                hostingView.layoutSubtreeIfNeeded()
                guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
                    in: hostingView.bounds
                ) else {
                    throw RegressionFailure(
                        "The welcome screen could not be rendered at \(zoom.title) zoom."
                    )
                }
                hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]),
                      png.count > 1_000
                else {
                    throw RegressionFailure(
                        "The welcome screen was empty at \(zoom.title) zoom."
                    )
                }
                if let directory = ProcessInfo.processInfo.environment[
                    "EDIT950_WELCOME_SCREENSHOT_DIRECTORY"
                ], !directory.isEmpty {
                    try png.write(
                        to: URL(fileURLWithPath: directory, isDirectory: true)
                            .appendingPathComponent("welcome-\(zoom.title).png")
                    )
                }
                openingScreenPNGs.insert(png)
            }
            guard openingScreenPNGs.count == SuiteZoomLevel.allCases.count else {
                throw RegressionFailure(
                    "The welcome screen did not visibly respond at every zoom level."
                )
            }
            suitePreferences.zoom = .oneHundred
            print("✓ Fixed header remains visible while the welcome screen responds at every zoom")

            guard let recentTable = findTable(
                in: hostingView,
                expectedRowCount: 1,
                expectedColumnCount: 4
            ) else {
                throw RegressionFailure(
                    "The recent-image table could not be located for double-click testing."
                )
            }
            let recentRow = recentTable.rect(ofRow: 0)
            let doubleClickPoint = recentTable.convert(
                NSPoint(x: recentRow.midX, y: recentRow.midY),
                to: nil
            )
            guard let doubleClick = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: doubleClickPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 2,
                pressure: 1
            ) else {
                throw RegressionFailure("Could not create the recent-image double-click event.")
            }
            var openedRecentRow: Int?
            let doubleClickMonitor = NativeTableDoubleClickMonitor.Coordinator { row in
                openedRecentRow = row
                guard row == 0 else { return }
                model.openRecent(image)
            }
            doubleClickMonitor.hostView = hostingView
            guard doubleClickMonitor.processDoubleClick(doubleClick),
                  openedRecentRow == 0
            else {
                throw RegressionFailure(
                    "The recent-image table did not resolve its double-clicked row."
                )
            }
            var recentOpenAttempts = 0
            while model.session == nil && recentOpenAttempts < 100 {
                try await Task.sleep(nanoseconds: 20_000_000)
                recentOpenAttempts += 1
            }
            guard model.session != nil else {
                throw RegressionFailure(
                    "Double-clicking the recent IMG row did not load the image."
                )
            }
            print("✓ Double-clicking a recent IMG row loads the image")

            let dismissibleErrorText = "TEST FULL DISK ACCESS ERROR"
            model.report = OperationReport(
                title: "EDIT950",
                lines: [dismissibleErrorText, "Full Disk Access is required."],
                isError: true
            )
            try await Task.sleep(nanoseconds: 100_000_000)
            hostingView.layoutSubtreeIfNeeded()
            guard renderedText(in: hostingView).contains(where: {
                $0.contains(dismissibleErrorText)
            }) else {
                throw RegressionFailure(
                    "The dismissible operation-error panel was not rendered."
                )
            }
            model.dismissReport()
            try await Task.sleep(nanoseconds: 100_000_000)
            hostingView.layoutSubtreeIfNeeded()
            guard model.report == nil,
                  !renderedText(in: hostingView).contains(where: {
                    $0.contains(dismissibleErrorText)
                  })
            else {
                throw RegressionFailure(
                    "The operation-error panel did not disappear after dismissal."
                )
            }
            print("✓ Safe Eject errors dismiss without leaving an app-modal alert")

            try await Task.sleep(nanoseconds: 500_000_000)
            hostingView.layoutSubtreeIfNeeded()

            let markerOptions = ImportOptions(
                family: .s900,
                compressedS900: false,
                convertToMono: true,
                preserveSampleRate: true,
                collisionPolicy: .rename
            )
            let markerSourceInspection = try WAVService.inspect(
                markerWAV,
                options: markerOptions
            )
            let sourceMarkers = markerSourceInspection.cueSampleOffsets.sorted()
            guard sourceMarkers.count == 2, sourceMarkers[0] < sourceMarkers[1]
            else {
                throw RegressionFailure(
                    "The marker-WAV fixture does not contain exactly two valid cue markers."
                )
            }
            let crossingMap = try WAVService.zeroCrossings(in: markerWAV)
            guard !crossingMap.crossings.isEmpty,
                  let previousCrossing = crossingMap.previous(
                    before: Int(sourceMarkers[0])
                  ),
                  let nextCrossing = crossingMap.next(
                    after: Int(sourceMarkers[0])
                  ),
                  crossingMap.direction(at: previousCrossing.frame) != nil,
                  crossingMap.direction(at: nextCrossing.frame) != nil
            else {
                throw RegressionFailure(
                    "The supplied WAV did not expose navigable directed zero crossings."
                )
            }
            print("✓ Located previous/next WAV zero crossings with directions")
            let audition = SampleLoopAuditionController()
            audition.play(
                url: markerWAV,
                start: Int(sourceMarkers[0]),
                end: Int(sourceMarkers[1])
            )
            try await Task.sleep(nanoseconds: 100_000_000)
            guard audition.isPlaying, audition.errorMessage == nil else {
                throw RegressionFailure(
                    "The temporary WAV loop could not be auditioned: \(audition.errorMessage ?? "unknown error")"
                )
            }
            let bandwidthPreview = workspace.appendingPathComponent(
                "bandwidth-live-preview.wav"
            )
            let previewTask = Task.detached {
                try WAVService.resampleS950(
                    markerWAV,
                    to: bandwidthPreview,
                    conversion: S950BandwidthConversion(
                        bandwidth: 9_600,
                        mode: .antiAliased
                    )
                )
            }
            await Task.yield()
            guard audition.isPlaying else {
                throw RegressionFailure(
                    "Preparing a bandwidth preview stopped the active audition."
                )
            }
            let previewInspection = try await previewTask.value
            let previewMarkers = try WAVService.cueSampleOffsets(
                in: bandwidthPreview
            ).sorted()
            guard audition.isPlaying,
                  previewMarkers.count == 2,
                  previewMarkers[0] < previewMarkers[1],
                  Int64(previewMarkers[1]) <= previewInspection.frameCount
            else {
                throw RegressionFailure(
                    "The active audition did not survive bandwidth preview rendering with in-range loop markers."
                )
            }
            audition.updateIfPlaying(
                url: bandwidthPreview,
                start: Int(previewMarkers[0]),
                end: Int(previewMarkers[1])
            )
            guard audition.isPlaying, audition.errorMessage == nil else {
                throw RegressionFailure(
                    "The active audition did not switch to the new bandwidth preview."
                )
            }
            print("✓ Bandwidth preview rendering and swap preserve active audition")
            audition.updateIfPlaying(
                url: markerWAV,
                start: Int(sourceMarkers[0] + 1),
                end: Int(sourceMarkers[1])
            )
            guard audition.isPlaying, audition.errorMessage == nil else {
                throw RegressionFailure(
                    "The loop audition did not update after a loop-point change."
                )
            }
            audition.updateIfPlaying(
                url: markerWAV,
                mode: .loop,
                direction: .reverse,
                start: Int(sourceMarkers[0] + 1),
                end: Int(sourceMarkers[1])
            )
            guard audition.isPlaying, audition.errorMessage == nil else {
                throw RegressionFailure(
                    "Changing the live audition to reverse loop playback failed."
                )
            }
            audition.updateIfPlaying(
                url: markerWAV,
                mode: .alternatingLoop,
                direction: .normal,
                start: Int(sourceMarkers[0] + 2),
                end: Int(sourceMarkers[1] - 1)
            )
            guard audition.isPlaying, audition.errorMessage == nil else {
                throw RegressionFailure(
                    "Changing the live audition to alternating playback failed."
                )
            }
            audition.stop()
            guard !audition.isPlaying else {
                throw RegressionFailure("The loop audition did not stop.")
            }
            var oneShotEnded = false
            audition.onPlaybackEnded = { oneShotEnded = true }
            audition.playOneShot(url: markerWAV)
            guard audition.isPlaying, audition.errorMessage == nil else {
                throw RegressionFailure(
                    "The temporary WAV could not begin one-shot audition."
                )
            }
            var completionAttempts = 0
            while audition.isPlaying && completionAttempts < 100 {
                try await Task.sleep(nanoseconds: 20_000_000)
                completionAttempts += 1
            }
            guard !audition.isPlaying, oneShotEnded else {
                throw RegressionFailure(
                    "The one-shot audition did not stop at the end of the sample."
                )
            }
            print("✓ Auditioned the WAV as a live loop and a completing one-shot")
            try await model.importWAVs(
                [markerWAV],
                options: markerOptions,
                requestedNames: [
                    markerWAV.standardizedFileURL.path: "loopname"
                ]
            )
            guard let markerSample = model.snapshot.files.first(where: {
                $0.isSample
                    && ($0.name as NSString).deletingPathExtension
                        .caseInsensitiveCompare("LOOPNAME") == .orderedSame
            }) else {
                throw RegressionFailure(
                    "The two-marker WAV did not import into the disposable IMG."
                )
            }
            try await model.exportNativeFiles(
                [markerSample],
                to: markerDirectory,
                policy: .replace,
                revealInFinder: false
            )
            guard let markerNativeURL = try FileManager.default
                .contentsOfDirectory(
                    at: markerDirectory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                .first(where: {
                    $0.pathExtension.caseInsensitiveCompare("s9") == .orderedSame
                })
            else {
                throw RegressionFailure(
                    "The marker-derived S9 could not be exported for verification."
                )
            }
            let markerAttributes = try S9NativeSample.attributes(
                in: Data(contentsOf: markerNativeURL)
            )
            let expectedMarkerStart = UInt32(
                (Double(sourceMarkers[0]) * Double(markerAttributes.sampleLength)
                    / Double(markerSourceInspection.frameCount)).rounded()
            )
            let expectedMarkerEnd = UInt32(
                (Double(sourceMarkers[1]) * Double(markerAttributes.sampleLength)
                    / Double(markerSourceInspection.frameCount)).rounded()
            )
            guard markerAttributes.playbackMode == .oneShot,
                  markerAttributes.loopStart.map({
                      abs(Int64($0) - Int64(expectedMarkerStart)) <= 1
                  }) == true,
                  abs(Int64(markerAttributes.playbackEnd) - Int64(expectedMarkerEnd)) <= 1
            else {
                throw RegressionFailure(
                    "Ordinary WAV import did not retain both markers in a one-shot S9. "
                        + "Expected one-shot \(expectedMarkerStart)–\(expectedMarkerEnd); "
                        + "exported \(markerAttributes.playbackMode.title) "
                        + "\(markerAttributes.loopStart.map(String.init) ?? "nil")–\(markerAttributes.playbackEnd)."
                )
            }
            guard let storedMarkerStart = markerAttributes.loopStart else {
                throw RegressionFailure("The marker-derived S9 has no stored loop start.")
            }
            let storedMarkerEnd = markerAttributes.playbackEnd
            print("✓ Ordinary WAV import writes two marker positions while retaining one-shot mode")

            let markerWAVExportDirectory = workspace.appendingPathComponent(
                "markers-wav-export",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: markerWAVExportDirectory,
                withIntermediateDirectories: true
            )
            try await model.exportWAVs(
                [markerSample],
                to: markerWAVExportDirectory,
                policy: .replace
            )
            guard let exportedMarkerWAV = try FileManager.default
                .contentsOfDirectory(
                    at: markerWAVExportDirectory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                .first(where: {
                    $0.pathExtension.caseInsensitiveCompare("wav") == .orderedSame
                })
            else {
                throw RegressionFailure(
                    "Normal S9 export did not create a WAV for marker verification."
                )
            }
            let roundTripMarkers = try WAVService.cueSampleOffsets(
                in: exportedMarkerWAV
            )
            guard roundTripMarkers.count == 2,
                  roundTripMarkers[0] < roundTripMarkers[1]
            else {
                throw RegressionFailure(
                    "Normal S9-to-WAV export did not add its stored loop markers."
                )
            }
            let roundTripMarkerText = String(
                decoding: try Data(contentsOf: exportedMarkerWAV),
                as: UTF8.self
            )
            guard roundTripMarkerText.contains("Loop Start"),
                  roundTripMarkerText.contains("Loop End")
            else {
                throw RegressionFailure(
                    "Normal S9-to-WAV export did not label its loop markers."
                )
            }
            print("✓ Normal S9-to-WAV export adds labelled native loop markers")

            model.auditionSample(withIDs: Set([markerSample.id]))
            var observedTableAudition = false
            for _ in 0..<200 {
                if model.auditioningSampleID == markerSample.id {
                    observedTableAudition = true
                }
                if observedTableAudition,
                   model.auditioningSampleID == nil,
                   !model.operationActive {
                    break
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard observedTableAudition,
                  model.auditioningSampleID == nil,
                  !model.operationActive
            else {
                throw RegressionFailure(
                    "IMG-table cached one-shot audition did not start and finish playback."
                )
            }
            print("✓ IMG-table cached one-shot audition starts immediately and finishes")

            if let nativeLoopFixturePath {
                let nativeData = try Data(
                    contentsOf: URL(fileURLWithPath: nativeLoopFixturePath)
                )
                let nativeName = try S9NativeSample.internalName(in: nativeData)
                let nativeAttributes = try S9NativeSample.attributes(in: nativeData)
                guard nativeAttributes.playbackMode.requiresLoopMarkers,
                      let nativeLoopStart = nativeAttributes.loopStart,
                      let nativeLoopSample = model.snapshot.files.first(where: {
                          $0.isSample
                              && ($0.name as NSString).deletingPathExtension
                                  .caseInsensitiveCompare(nativeName)
                                  == .orderedSame
                      })
                else {
                    throw RegressionFailure(
                        "The native-loop S9 fixture was not imported as a looping sample."
                    )
                }
                model.openEditor(for: nativeLoopSample)
                for _ in 0..<50 where model.externalSampleEditSession == nil {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                guard let nativeEditSession = model.externalSampleEditSession
                else {
                    throw RegressionFailure(
                        "The native-loop S9 did not open in the sample editor."
                    )
                }
                let frameCount = nativeEditSession.originalInspection.frameCount
                func wavPosition(_ nativePosition: UInt32) -> UInt32 {
                    UInt32(
                        (Double(nativePosition) * Double(frameCount)
                            / Double(nativeAttributes.sampleLength)).rounded()
                    )
                }
                let expectedNativeCues = [
                    wavPosition(nativeLoopStart),
                    wavPosition(nativeAttributes.playbackEnd)
                ]
                let nativeCueData = try Data(
                    contentsOf: nativeEditSession.wavURL
                )
                let nativeMarkerText = String(
                    decoding: nativeCueData,
                    as: UTF8.self
                )
                guard nativeEditSession.originalInspection.cueSampleOffsets
                        == expectedNativeCues,
                      nativeMarkerText.contains("Loop Start"),
                      nativeMarkerText.contains("Loop End")
                else {
                    throw RegressionFailure(
                        "Native S9 loop points were not exposed as labelled WAV markers."
                    )
                }
                model.cancelExternalSampleEdit(nativeEditSession)
                for _ in 0..<40 where window.attachedSheet != nil {
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                print("✓ Native looping S9 opens with labelled WAV loop markers")
            }

            guard let program = model.snapshot.files.first(where: {
                $0.name.caseInsensitiveCompare("DELETEP9.P9") == .orderedSame
            }) else {
                throw RegressionFailure("The disposable image did not contain the P9 test entry.")
            }
            model.addTag()
            guard let sharedTag = model.tags.last else {
                throw RegressionFailure("EDIT950 could not create a shared tag.")
            }
            model.updateTag(sharedTag, name: "Regression", colorHex: "#CC5500")
            guard let regressionTag = model.tags.first(where: { $0.id == sharedTag.id }) else {
                throw RegressionFailure("The new shared tag was not persisted.")
            }
            model.toggleImageTag(regressionTag)
            model.toggleTag(regressionTag, for: [program])
            try await Task.sleep(nanoseconds: 50_000_000)
            guard model.tagsForCurrentImage().contains(where: { $0.id == regressionTag.id }),
                  model.tags(for: program).contains(where: { $0.id == regressionTag.id })
            else {
                throw RegressionFailure("IMG/P9 tag assignment was not immediately visible.")
            }
            guard undoManager.canUndo else {
                throw RegressionFailure("Tag assignment did not enable Undo.")
            }
            print("✓ Shared IMG and P9 tags are assignable and immediately enable Undo")
            undoManager.removeAllActions()
            guard let table = findFileTable(
                in: hostingView,
                expectedRowCount: model.snapshot.files.count
            ),
                  let row = model.snapshot.files.firstIndex(where: { $0.id == program.id })
            else {
                throw RegressionFailure("Could not locate the rendered file table.")
            }

            model.selection.removeAll()
            NativeFileTableSelection.select(
                program,
                modifiers: [],
                model: model,
                window: window
            )
            try await Task.sleep(nanoseconds: 150_000_000)
            guard model.selection.contains(program.id) else {
                throw RegressionFailure(
                    "A mouse click in the Name cell did not update the SwiftUI P9 selection "
                    + "(native selected row: \(table.selectedRow))."
                )
            }
            guard table.selectedRow == row,
                  window.firstResponder === table
            else {
                throw RegressionFailure(
                    "A Name-cell selection did not select and focus its native table row."
                )
            }
            guard let selectedRowView = table.rowView(
                atRow: row,
                makeIfNecessary: false
            ) else {
                throw RegressionFailure(
                    "The selected EDIT950 row was not rendered."
                )
            }
            let yellowRatio = suiteYellowPixelRatio(in: selectedRowView)
            guard selectedRowView.selectionHighlightStyle == .none,
                  yellowRatio > 0.8
            else {
                throw RegressionFailure(
                    "The selected EDIT950 row did not render as one clean FIND950 yellow highlight "
                        + "(yellow coverage: \(Int((yellowRatio * 100).rounded()))%)."
                )
            }
            guard model.canExport else {
                throw RegressionFailure(
                    "Export Selected remained disabled for a selected P9."
                )
            }
            if let sampleRow = model.snapshot.files.firstIndex(where: {
                $0.id != program.id
            }) {
                let secondFile = model.snapshot.files[sampleRow]
                NativeFileTableSelection.select(
                    secondFile,
                    modifiers: [.command],
                    model: model,
                    window: window
                )
                try await Task.sleep(nanoseconds: 150_000_000)
                guard model.selection.count == 2,
                      model.selection.contains(program.id),
                      table.selectedRowIndexes == IndexSet([row, sampleRow])
                else {
                    throw RegressionFailure(
                        "Command-click selection did not synchronize both table rows."
                    )
                }
                NativeFileTableSelection.select(
                    program,
                    modifiers: [],
                    model: model,
                    window: window
                )
                try await Task.sleep(nanoseconds: 150_000_000)
            }
            print("✓ Full-cell selection synchronizes, focuses and renders FIND950 yellow")

            model.fileSortOrder = [
                KeyPathComparator(\AkaiFile.name, order: .reverse)
            ]
            try await Task.sleep(nanoseconds: 200_000_000)
            hostingView.layoutSubtreeIfNeeded()
            let descendingNames = model.snapshot.files.map(\.name).sorted(by: >)
            guard model.displayedFiles.map(\.name) == descendingNames,
                  let sortedProgramRow = model.displayedFiles.firstIndex(
                    where: { $0.id == program.id }
                  )
            else {
                throw RegressionFailure("Name sorting did not reorder the rendered files.")
            }
            NativeFileTableSelection.select(
                program,
                modifiers: [],
                model: model,
                window: window
            )
            guard table.selectedRow == sortedProgramRow,
                  model.selection == [program.id]
            else {
                throw RegressionFailure(
                    "Sorted-row selection did not retain the P9 stable identity."
                )
            }
            model.fileSortOrder = [KeyPathComparator(\AkaiFile.type)]
            guard model.displayedFiles.map(\.type)
                    == model.snapshot.files.map(\.type).sorted()
            else {
                throw RegressionFailure("Type sorting did not order the rendered files.")
            }
            model.fileSortOrder = [KeyPathComparator(\AkaiFile.byteSize)]
            guard model.displayedFiles.map(\.byteSize)
                    == model.snapshot.files.map(\.byteSize).sorted()
            else {
                throw RegressionFailure("Size sorting did not order the rendered files.")
            }
            model.fileSortOrder = []
            try await Task.sleep(nanoseconds: 150_000_000)
            hostingView.layoutSubtreeIfNeeded()
            print("✓ Name, Type and Size sorting preserve stable row selection")

            let dragProvider = model.nativeDragProvider(for: program)
            let p9Type = UTType(filenameExtension: "p9") ?? .data
            let draggedName = try await loadedFilename(
                from: dragProvider,
                typeIdentifier: p9Type.identifier
            )
            guard dragProvider.suggestedName == "DELETEP9",
                  (draggedName as NSString).deletingPathExtension == "DELETEP9",
                  (draggedName as NSString).pathExtension
                    .caseInsensitiveCompare("p9") == .orderedSame
            else {
                throw RegressionFailure(
                    "The P9 drag provider suggested \(dragProvider.suggestedName ?? "nil") "
                        + "and produced \(draggedName)."
                )
            }
            print("✓ P9 drag provider exports one exact extension")

            guard let dragSample = model.snapshot.files.first(where: \.isSample)
            else {
                throw RegressionFailure(
                    "The disposable image did not contain an S9 for multi-file drag testing."
                )
            }
            model.selection = [program.id, dragSample.id]
            let dragFiles = model.nativeFilesForDrag(startingWith: program)
            guard Set(dragFiles.map(\.id)) == Set([program.id, dragSample.id])
            else {
                throw RegressionFailure(
                    "Starting a drag on a selected P9 did not preserve both selected native files."
                )
            }
            let batchExports = try await model.exportNativeFilesForDrag(dragFiles)
            guard batchExports.count == 2,
                  batchExports[program.id]?.lastPathComponent == program.name,
                  batchExports[dragSample.id]?.lastPathComponent == dragSample.name
            else {
                throw RegressionFailure(
                    "The multi-file drag export did not preserve both exact S9/P9 names."
                )
            }
            print("✓ Multi-file drag preparation exports every selected S9/P9 with exact names")

            let editedSample = markerSample
            model.openEditor(for: editedSample)
            for _ in 0..<50 where model.externalSampleEditSession == nil {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let editSession = model.externalSampleEditSession,
                  editSession.sourceFile.id == editedSample.id,
                  editSession.editorURL?.standardizedFileURL
                    == audioEditor.standardizedFileURL,
                  editSession.originalInspection.cueSampleOffsets
                    == [storedMarkerStart, storedMarkerEnd]
            else {
                throw RegressionFailure(
                    "Double-click routing did not open the selected sample editor."
                )
            }
            guard !FileManager.default.fileExists(atPath: editorLaunchLog.path)
            else {
                throw RegressionFailure(
                    "Opening the S9 edit dialogue also launched the external audio editor."
                )
            }
            for _ in 0..<40 where window.attachedSheet == nil {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let sampleSheet = window.attachedSheet,
                  let sampleSheetContent = sampleSheet.contentView
            else {
                throw RegressionFailure(
                    "The S9 external-editor sheet was not rendered."
                )
            }
            sampleSheetContent.layoutSubtreeIfNeeded()
            let compactSheetBounds = sampleSheetContent.bounds
            guard compactSheetBounds.width >= 710,
                  compactSheetBounds.height >= 410,
                  let compactSheetBitmap = sampleSheetContent
                    .bitmapImageRepForCachingDisplay(in: compactSheetBounds)
            else {
                throw RegressionFailure(
                    "The compact S9 workflow was not laid out at its 720×420 design size."
                )
            }
            sampleSheetContent.cacheDisplay(
                in: compactSheetBounds,
                to: compactSheetBitmap
            )
            guard (compactSheetBitmap.representation(
                using: .png,
                properties: [:]
            )?.count ?? 0) > 1_000,
                  editSession.originalAttributes.rootNote == 60,
                  editSession.originalAttributes.playbackDirection == .normal,
                  editSession.originalAttributes.playbackMode == .oneShot,
                  editSession.originalAttributes.loopStart == storedMarkerStart,
                  editSession.originalAttributes.playbackEnd == storedMarkerEnd
            else {
                throw RegressionFailure(
                    "The S9 editor did not preserve its playback settings or render its compact workflow. "
                        + "size=\(Int(compactSheetBounds.width))×\(Int(compactSheetBounds.height)), "
                        + "root=\(editSession.originalAttributes.rootNote), "
                        + "direction=\(editSession.originalAttributes.playbackDirection.title), "
                        + "mode=\(editSession.originalAttributes.playbackMode.title), "
                        + "loop=\(editSession.originalAttributes.loopStart.map(String.init) ?? "nil")–"
                        + "\(editSession.originalAttributes.playbackEnd)."
                )
            }
            guard ExternalSampleEditSheet.saveAsNewActionTitle
                == "SAVE AS NEW…" else {
                throw RegressionFailure(
                    "The sample editor did not expose its explicit Save As New action."
                )
            }
            let labelledMarkerData = try Data(contentsOf: editSession.wavURL)
            let labelledMarkerText = String(
                decoding: labelledMarkerData,
                as: UTF8.self
            )
            guard labelledMarkerText.contains("LIST"),
                  labelledMarkerText.contains("adtl"),
                  labelledMarkerText.contains("Loop Start"),
                  labelledMarkerText.contains("Loop End")
            else {
                throw RegressionFailure(
                    "The S9 edit WAV did not expose labelled loop markers to the audio editor."
                )
            }

            try await model.exportNativeFiles(
                [program],
                to: programBeforeNewSampleDirectory,
                policy: .replace,
                revealInFinder: false
            )
            model.report = nil
            guard let programBeforeURL = try FileManager.default
                .contentsOfDirectory(
                    at: programBeforeNewSampleDirectory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                .first(where: {
                    $0.pathExtension.caseInsensitiveCompare("p9") == .orderedSame
                })
            else {
                throw RegressionFailure(
                    "The P9 could not be captured before Save As New."
                )
            }
            let programBeforeNewSample = try Data(contentsOf: programBeforeURL)
            let imageBeforeNewSample = try Data(contentsOf: image)
            let fileCountBeforeNewSample = model.snapshot.fileCount
            let saveAsAttributes = S9SampleEditSettings(
                rootNote: min(127, editSession.originalAttributes.rootNote + 1),
                playbackMode: editSession.originalAttributes.playbackMode,
                playbackDirection: .reverse
            )
            let newSampleResult = try await model.performEditedS9Creation(
                editSession,
                requestedName: "LOOPCOPY",
                compressed: false,
                createBackup: true,
                attributes: saveAsAttributes
            )
            model.progress = nil
            guard let newSampleBackup = newSampleResult.backupURL,
                  try Data(contentsOf: newSampleBackup) == imageBeforeNewSample,
                  model.snapshot.fileCount == fileCountBeforeNewSample + 1,
                  model.snapshot.files.contains(where: {
                      $0.isSample
                          && sampleBaseName($0.name)
                              .caseInsensitiveCompare("LOOPNAME") == .orderedSame
                  }),
                  let savedNewSample = model.snapshot.files.first(where: {
                      $0.isSample
                          && sampleBaseName($0.name)
                              .caseInsensitiveCompare("LOOPCOPY") == .orderedSame
                  }),
                  newSampleResult.filename == savedNewSample.name,
                  model.selection == Set([savedNewSample.id])
            else {
                throw RegressionFailure(
                    "Save As New did not retain the original, add one verified S9 and select it."
                )
            }

            guard let currentProgram = model.snapshot.files.first(where: {
                $0.name.caseInsensitiveCompare(program.name) == .orderedSame
            }) else {
                throw RegressionFailure(
                    "The P9 disappeared while saving an edited sample as new."
                )
            }
            try await model.exportNativeFiles(
                [currentProgram],
                to: programAfterNewSampleDirectory,
                policy: .replace,
                revealInFinder: false
            )
            model.report = nil
            guard let programAfterURL = try FileManager.default
                .contentsOfDirectory(
                    at: programAfterNewSampleDirectory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                .first(where: {
                    $0.pathExtension.caseInsensitiveCompare("p9") == .orderedSame
                }),
                  try Data(contentsOf: programAfterURL)
                    == programBeforeNewSample
            else {
                throw RegressionFailure(
                    "Save As New changed an existing P9 reference."
                )
            }

            let imageAfterNewSample = try Data(contentsOf: image)
            var duplicateNameRejected = false
            do {
                _ = try await model.performEditedS9Creation(
                    editSession,
                    requestedName: "LOOPCOPY",
                    compressed: false,
                    createBackup: true,
                    attributes: saveAsAttributes
                )
            } catch {
                duplicateNameRejected = true
            }
            var invalidNameRejected = false
            do {
                _ = try await model.performEditedS9Creation(
                    editSession,
                    requestedName: "BAD NAME",
                    compressed: false,
                    createBackup: true,
                    attributes: saveAsAttributes
                )
            } catch {
                invalidNameRejected = true
            }
            guard duplicateNameRejected,
                  invalidNameRejected,
                  try Data(contentsOf: image) == imageAfterNewSample
            else {
                throw RegressionFailure(
                    "Save As New did not reject a collision or invalid S950 name before mutation."
                )
            }
            model.s9CreationAvailableBytesOverride = 1
            var insufficientSpaceRejected = false
            do {
                _ = try await model.performEditedS9Creation(
                    editSession,
                    requestedName: "LOOPFULL",
                    compressed: false,
                    createBackup: true,
                    attributes: saveAsAttributes
                )
            } catch AppError.insufficientSpace {
                insufficientSpaceRejected = true
            } catch {
                throw error
            }
            model.s9CreationAvailableBytesOverride = nil
            model.progress = nil
            guard insufficientSpaceRejected,
                  try Data(contentsOf: image) == imageAfterNewSample
            else {
                throw RegressionFailure(
                    "Save As New did not reject insufficient additional capacity before mutation."
                )
            }

            model.s9ReplacementVerificationMutator = { exportedData in
                var corrupted = exportedData
                if !corrupted.isEmpty {
                    corrupted[corrupted.count - 1] ^= 0x01
                }
                return corrupted
            }
            var forcedNewSampleVerificationFailed = false
            do {
                _ = try await model.performEditedS9Creation(
                    editSession,
                    requestedName: "LOOPFAIL",
                    compressed: false,
                    createBackup: true,
                    attributes: saveAsAttributes
                )
            } catch {
                forcedNewSampleVerificationFailed = true
            }
            model.s9ReplacementVerificationMutator = nil
            model.progress = nil
            guard forcedNewSampleVerificationFailed,
                  try Data(contentsOf: image) == imageAfterNewSample,
                  !model.snapshot.files.contains(where: {
                      $0.isSample
                          && sampleBaseName($0.name)
                              .caseInsensitiveCompare("LOOPFAIL") == .orderedSame
                  }),
                  model.snapshot.files.contains(where: {
                      $0.isSample
                          && sampleBaseName($0.name)
                              .caseInsensitiveCompare("LOOPNAME") == .orderedSame
                  }),
                  model.snapshot.files.contains(where: {
                      $0.isSample
                          && sampleBaseName($0.name)
                              .caseInsensitiveCompare("LOOPCOPY") == .orderedSame
                  })
            else {
                throw RegressionFailure(
                    "A forced Save As New verification failure did not restore the complete IMG."
                )
            }
            print("✓ Saved an edited S9 as a verified new sample while preserving its original and P9")
            print("✓ Rejected invalid and duplicate Save As New names before IMG mutation")
            print("✓ Rejected insufficient Save As New capacity before IMG mutation")
            print("✓ Restored the complete IMG after a forced Save As New verification failure")

            var replacementDismissedFromReadyState = false
            model.replaceEditedS9Sample(
                editSession,
                compressed: false,
                createBackup: true,
                attributes: S9SampleEditSettings(
                    rootNote: editSession.originalAttributes.rootNote,
                    playbackMode: .loop,
                    playbackDirection: .normal
                ),
                onSuccess: {
                    replacementDismissedFromReadyState =
                        !editSession.isSaving
                            && model.externalSampleEditSession?.id
                                == editSession.id
                }
            )
            var observedReplacement = false
            for _ in 0..<800 {
                if editSession.isSaving { observedReplacement = true }
                if !model.operationActive { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            for _ in 0..<80 where window.attachedSheet != nil {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard observedReplacement,
                  !model.operationActive,
                  !editSession.isSaving,
                  replacementDismissedFromReadyState,
                  model.externalSampleEditSession == nil,
                  window.attachedSheet == nil,
                  let replacedEditedSample = model.snapshot.files.first(where: {
                      $0.isSample
                          && ($0.name as NSString).deletingPathExtension
                              .caseInsensitiveCompare("LOOPNAME") == .orderedSame
                  })
            else {
                throw RegressionFailure(
                    "A backed-up loop-mode S9 replacement left its sample editor sheet open."
                )
            }
            print("✓ Backed-up loop-mode S9 replacement dismisses its editor without a mode change")

            let imageBeforeNoChangeReplace = try Data(contentsOf: image)
            try await model.prepareExternalSampleEdit(
                file: replacedEditedSample,
                editorURL: audioEditor
            )
            guard let unchangedEditSession = model.externalSampleEditSession,
                  try !model.editedS9HasChanges(
                    unchangedEditSession,
                    attributes: S9SampleEditSettings(
                        attributes: unchangedEditSession.originalAttributes
                    ),
                    loopPoints: nil,
                    bandwidthConversion: nil
                  )
            else {
                throw RegressionFailure(
                    "A freshly opened sample editor incorrectly reported an edit."
                )
            }
            var noChangeEditorDismissed = false
            model.replaceEditedS9Sample(
                unchangedEditSession,
                compressed: false,
                createBackup: true,
                attributes: S9SampleEditSettings(
                    attributes: unchangedEditSession.originalAttributes
                ),
                onSuccess: { noChangeEditorDismissed = true }
            )
            for _ in 0..<80 where window.attachedSheet != nil {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard noChangeEditorDismissed,
                  model.externalSampleEditSession == nil,
                  model.headerNotice?.title == "Nothing Changed",
                  try Data(contentsOf: image) == imageBeforeNoChangeReplace
            else {
                throw RegressionFailure(
                    "Replacing an unchanged sample did not close cleanly without mutating the IMG."
                )
            }
            print("✓ Replacing an unchanged S9 closes the editor and reports that nothing was written")

            model.selection = [replacedEditedSample.id]
            model.showSelectedFileInformation()
            for _ in 0..<100 where model.operationActive {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            let nativeInformation =
                model.fileInformation?.details.lowercased() ?? ""
            guard nativeInformation.contains("srate:"),
                  nativeInformation.contains("npitch:"),
                  nativeInformation.contains("pmode:"),
                  nativeInformation.contains("llen:")
            else {
                throw RegressionFailure(
                    "Native S9 information did not include sample rate, nominal pitch, playback mode and loop length."
                )
            }
            model.fileInformation = nil
            print("✓ Read native S9 sample-rate, pitch and loop attributes")

            try await model.exportNativeFiles(
                [program],
                to: copiedDirectory,
                policy: .rename,
                revealInFinder: false
            )
            let copiedNames = try FileManager.default.contentsOfDirectory(atPath: copiedDirectory.path)
            guard copiedNames == ["DELETEP9.P9"] else {
                throw RegressionFailure(
                    "The original P9 copy had an incorrect filename: \(copiedNames.joined(separator: ", "))."
                )
            }
            print("✓ Copied the original P9 with exactly one uppercase extension")

            try await model.delete(files: [program])
            try await Task.sleep(nanoseconds: 300_000_000)
            hostingView.layoutSubtreeIfNeeded()
            guard !model.snapshot.files.contains(where: { $0.name.uppercased().hasSuffix(".P9") }) else {
                throw RegressionFailure("The P9 entry remained after deletion.")
            }
            guard model.tags(for: program).isEmpty,
                  model.tagsForCurrentImage().contains(where: { $0.id == regressionTag.id })
            else {
                throw RegressionFailure(
                    "Deleting a P9 did not clear only its tag assignment."
                )
            }
            guard model.report == nil,
                  model.headerNotice?.title == "Files Deleted"
            else {
                throw RegressionFailure(
                    "Successful deletion used a blocking report instead of a header notice."
                )
            }
            guard undoManager.canUndo,
                  undoManager.undoActionName == "Delete Files"
            else {
                throw RegressionFailure("Verified P9 deletion did not enable Undo.")
            }
            undoManager.undo()
            for _ in 0..<200 where model.operationActive {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard model.snapshot.files.contains(where: {
                $0.name.caseInsensitiveCompare("DELETEP9.P9") == .orderedSame
            }), model.tags(for: program).contains(where: { $0.id == regressionTag.id }),
               undoManager.canRedo
            else {
                throw RegressionFailure(
                    "Undo did not restore the deleted P9 and its shared tag."
                )
            }
            undoManager.redo()
            for _ in 0..<200 where model.operationActive {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard !model.snapshot.files.contains(where: {
                $0.name.caseInsensitiveCompare("DELETEP9.P9") == .orderedSame
            }) else {
                throw RegressionFailure("Redo did not reapply the verified P9 deletion.")
            }
            print("✓ Deletion enables Undo; Undo/Redo restores and reapplies the IMG plus shared tags")
            print("✓ Successful deletion reports through the non-blocking header")
            print("✓ Deleted a rendered, selected P9 row without a SwiftUI environment crash")

            guard let sampleName = model.availableSampleNames.first else {
                throw RegressionFailure(
                    "The sample dropdown did not expose the S9 sample in the open volume."
                )
            }
            let staleDraftDocument = try model.prepareBlankP9Program(
                named: "DRAFTSAFE"
            )
            let blankBaseline = staleDraftDocument.program.keygroups[0]
            var importedProgram = staleDraftDocument.program
            importedProgram.keygroups[0].softSampleName = sampleName
            importedProgram.keygroups[0].lowKey = 36
            importedProgram.keygroups[0].highKey = 36
            let revisionBeforeImport = staleDraftDocument.editorRevision
            staleDraftDocument.replaceProgram(
                with: importedProgram,
                refreshEditor: true
            )
            guard staleDraftDocument.editorRevision > revisionBeforeImport,
                  !staleDraftDocument.applyKeygroupDraft(
                    blankBaseline,
                    baseline: blankBaseline,
                    at: 0
                  ),
                  staleDraftDocument.program.keygroups[0].softSampleName
                    == sampleName
            else {
                throw RegressionFailure(
                    "A stale editor draft replaced an externally imported first keygroup."
                )
            }
            print("✓ Stale editor drafts cannot overwrite an imported first keygroup")

            let newProgram = try model.prepareBlankP9Program(named: "test_space")
            guard newProgram.program.keygroups.count == 1,
                  newProgram.program.name == "TEST SPACE",
                  newProgram.source.filename == "TEST SPACE.P9"
            else {
                throw RegressionFailure(
                    "A new program did not canonicalize once or start with exactly one blank keygroup."
                )
            }
            var editedProgram = newProgram.program
            editedProgram.keygroups[0].softSampleName = sampleName
            editedProgram.keygroups[0].lowKey = 60
            editedProgram.keygroups[0].highKey = 60
            let duplicate = try editedProgram.appendKeygroup(copying: 0)
            editedProgram.keygroups[duplicate].lowKey = 61
            editedProgram.keygroups[duplicate].highKey = 61
            try editedProgram.deleteKeygroups(at: [0])
            newProgram.program = editedProgram

            try await model.performCreateP9InImage(newProgram)
            guard newProgram.source.isExistingImageProgram,
                  let storedProgram = model.snapshot.files.first(where: {
                      $0.name.caseInsensitiveCompare("TEST SPACE.P9") == .orderedSame
                  })
            else {
                throw RegressionFailure(
                    "The verified new P9 was not present in the destination volume."
                )
            }
            guard newProgram.program.keygroups.count == 1,
                  newProgram.program.keygroups[0].id == 0,
                  newProgram.program.keygroups[0].softSampleName == sampleName,
                  newProgram.program.keygroups[0].lowKey == 61,
                  newProgram.program.keygroups[0].highKey == 61
            else {
                throw RegressionFailure(
                    "Keygroup creation/deletion did not survive the verified P9 round trip."
                )
            }
            model.selection = [storedProgram.id]
            print("✓ Sample choices come from the current S950 volume")
            print("✓ Canonicalized an underscored P9 name once and byte-verified it after keygroup add/delete")

            var copiedProgram = newProgram.program
            copiedProgram.keygroups[0].softFilter = 37
            newProgram.replaceProgram(with: copiedProgram)
            let fileCountBeforeProgramCopy = model.snapshot.fileCount
            try await model.performSaveP9AsNewInImage(
                newProgram,
                requestedName: "TEST COPY"
            )
            guard newProgram.source.filename == "TEST COPY.P9",
                  newProgram.program.name == "TEST COPY",
                  newProgram.program.keygroups[0].softFilter == 37,
                  model.snapshot.fileCount == fileCountBeforeProgramCopy + 1,
                  model.snapshot.files.contains(where: {
                    $0.name.caseInsensitiveCompare("TEST SPACE.P9") == .orderedSame
                  }),
                  model.snapshot.files.contains(where: {
                    $0.name.caseInsensitiveCompare("TEST COPY.P9") == .orderedSame
                  })
            else {
                throw RegressionFailure(
                    "Saving an edited P9 as new did not preserve the original and verify the renamed copy."
                )
            }
            print("✓ Saved an edited P9 directly into the IMG as a verified renamed copy")

            let imageBeforeAbletonExport = try Data(contentsOf: image)
            let templateURL = URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath
            ).appendingPathComponent(
                "Sources/EDIT950/Resources/AKAI-S950-Sampler-Template.adg"
            )
            let abletonExport = try await model.performAbletonDrumRackExport(
                storedProgram,
                to: workspace,
                templateURL: templateURL
            )
            let exportedPreset = try AbletonDrumRackParser.parse(
                url: abletonExport.adgURL
            )
            guard abletonExport.sampleURLs.count == 1,
                  exportedPreset.samples.count == 1,
                  exportedPreset.samples[0].sourceNote == 61,
                  exportedPreset.samples[0].sourceName == sampleName,
                  exportedPreset.samples[0].detectedRootNote == 61,
                  exportedPreset.samples[0].sampleURL.standardizedFileURL
                    == abletonExport.sampleURLs[0].standardizedFileURL,
                  abletonExport.warnings.isEmpty,
                  try Data(contentsOf: image) == imageBeforeAbletonExport
            else {
                throw RegressionFailure(
                    "The P9-to-Ableton export did not round-trip as one matching, non-destructive Sampler pad."
                )
            }
            print("✓ Exported P9/S9 content as a verified, non-destructive Ableton Sampler rack")

            guard let currentSample = model.snapshot.files.first(where: {
                $0.isSample
                    && sampleBaseName($0.name)
                        .caseInsensitiveCompare(sampleName) == .orderedSame
            }) else {
                throw RegressionFailure(
                    "The disposable S9 disappeared before rename testing."
                )
            }
            model.toggleTag(regressionTag, for: [currentSample])
            guard model.tags(for: currentSample).contains(where: {
                $0.id == regressionTag.id
            }) else {
                throw RegressionFailure("The S9 tag assignment was not visible.")
            }
            try await model.performNativeRename(
                currentSample,
                requestedName: "RENAMED"
            )
            guard let renamedSample = model.snapshot.files.first(where: {
                $0.isSample
                    && sampleBaseName($0.name) == "RENAMED"
            }), let linkedProgram = model.snapshot.files.first(where: {
                $0.name.caseInsensitiveCompare("TEST SPACE.P9") == .orderedSame
            }) else {
                throw RegressionFailure(
                    "The transactional S9 rename did not create the expected sample and retain its linked P9."
                )
            }
            guard model.tags(for: currentSample).isEmpty,
                  model.tags(for: renamedSample).contains(where: {
                      $0.id == regressionTag.id
                  })
            else {
                throw RegressionFailure("The S9 tag did not follow its verified rename.")
            }
            model.openEditor(for: linkedProgram)
            for _ in 0..<100 where model.operationActive {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let linkedDocument = model.p9EditorDocument,
                  linkedDocument.program.keygroups[0].softSampleName == "RENAMED"
            else {
                throw RegressionFailure(
                    "The transactional S9 rename did not update the linked P9 reference."
                )
            }
            model.p9EditorDocument = nil
            model.selection = [renamedSample.id]
            print("✓ Renamed an S9 and byte-verified its updated linked P9")

            guard let programBeforeRename = model.snapshot.files.first(where: {
                $0.name.caseInsensitiveCompare("TEST SPACE.P9") == .orderedSame
            }) else {
                throw RegressionFailure(
                    "The linked P9 disappeared before program rename testing."
                )
            }
            model.toggleTag(regressionTag, for: [programBeforeRename])
            try await model.performNativeRename(
                programBeforeRename,
                requestedName: "RACKPROG"
            )
            guard let renamedProgram = model.snapshot.files.first(where: {
                $0.name.caseInsensitiveCompare("RACKPROG.P9") == .orderedSame
            }), !model.snapshot.files.contains(where: {
                $0.name.caseInsensitiveCompare("TEST SPACE.P9") == .orderedSame
            }) else {
                throw RegressionFailure(
                    "The transactional P9 rename did not replace the directory entry."
                )
            }
            guard model.tags(for: programBeforeRename).isEmpty,
                  model.tags(for: renamedProgram).contains(where: {
                      $0.id == regressionTag.id
                  })
            else {
                throw RegressionFailure("The P9 tag did not follow its verified rename.")
            }
            model.openEditor(for: renamedProgram)
            for _ in 0..<100 where model.operationActive {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard model.p9EditorDocument?.program.name == "RACKPROG" else {
                throw RegressionFailure(
                    "The transactional P9 rename did not update the internal program name."
                )
            }
            model.p9EditorDocument = nil
            print("✓ Renamed a P9 and byte-verified its internal program name")

            let imageBeforeReadOnlyExport = try Data(contentsOf: image)
            await model.shutdown()
            try await model.openImage(image, readOnly: true)
            guard let readOnlyProgram = model.snapshot.files.first(where: {
                $0.name.caseInsensitiveCompare("RACKPROG.P9") == .orderedSame
            }), model.session?.readOnly == true else {
                throw RegressionFailure(
                    "The renamed P9 was not available after reopening the IMG read-only."
                )
            }
            let readOnlyAbletonExport = try await model.performAbletonDrumRackExport(
                readOnlyProgram,
                to: workspace,
                templateURL: templateURL
            )
            let readOnlyPreset = try AbletonDrumRackParser.parse(
                url: readOnlyAbletonExport.adgURL
            )
            guard readOnlyPreset.samples.count == 1,
                  readOnlyPreset.samples[0].sourceNote == 61,
                  try Data(contentsOf: image) == imageBeforeReadOnlyExport
            else {
                throw RegressionFailure(
                    "Read-only P9-to-Ableton export failed or changed the IMG."
                )
            }
            print("✓ Exported P9/S9 content from a read-only IMG without changing it")

            try await model.createFormattedImage(
                at: hardDiskImage,
                preset: .s900Hard32
            )
            guard model.snapshot.volumes.count == 1,
                  model.snapshot.volumes[0].name == "VOLUME 001",
                  model.snapshot.currentPath == model.snapshot.volumes[0].path
            else {
                throw RegressionFailure(
                    "The S950 hard-disk formatter did not create and open its initial volume."
                )
            }
            print("✓ S950 32 MB formatting creates and opens VOLUME 001")

            await model.shutdown()
            window.orderOut(nil)
            if let retainedImagePath {
                let retainedImage = URL(fileURLWithPath: retainedImagePath)
                if FileManager.default.fileExists(atPath: retainedImage.path) {
                    try FileManager.default.removeItem(at: retainedImage)
                }
                try FileManager.default.copyItem(at: image, to: retainedImage)
                print("Retained disposable image: \(retainedImage.path)")
            }
            print("\nInteraction regression passed")
        } catch {
            await seedingController.close()
            fputs("Interaction regression failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func findFileTable(in view: NSView, expectedRowCount: Int) -> NSTableView? {
        if let table = view as? NSTableView,
           table.numberOfColumns >= 6,
           table.numberOfRows == expectedRowCount {
            return table
        }
        for subview in view.subviews {
            if let table = findFileTable(in: subview, expectedRowCount: expectedRowCount) {
                return table
            }
        }
        return nil
    }

    private static func findTable(
        in view: NSView,
        expectedRowCount: Int,
        expectedColumnCount: Int
    ) -> NSTableView? {
        if let table = view as? NSTableView,
           table.numberOfRows == expectedRowCount,
           table.numberOfColumns == expectedColumnCount {
            return table
        }
        for subview in view.subviews {
            if let table = findTable(
                in: subview,
                expectedRowCount: expectedRowCount,
                expectedColumnCount: expectedColumnCount
            ) {
                return table
            }
        }
        return nil
    }

    private static func suiteYellowPixelRatio(in view: NSView) -> Double {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return 0 }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var yellowPixels = 0
        var inspectedPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else { continue }
                inspectedPixels += 1
                if isSuiteYellow(color.cgColor) {
                    yellowPixels += 1
                }
            }
        }
        guard inspectedPixels > 0 else { return 0 }
        return Double(yellowPixels) / Double(inspectedPixels)
    }

    private static func isSuiteYellow(_ color: CGColor?) -> Bool {
        guard let color,
              let converted = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB)
        else { return false }
        return converted.redComponent > 0.9
            && converted.greenComponent > 0.65
            && converted.greenComponent < 0.9
            && converted.blueComponent < 0.5
            && converted.redComponent - converted.greenComponent > 0.1
            && converted.greenComponent - converted.blueComponent > 0.2
            && converted.alphaComponent > 0.95
    }

    private static func renderedText(in view: NSView) -> [String] {
        var result: [String] = []
        if let field = view as? NSTextField, !field.stringValue.isEmpty {
            result.append(field.stringValue)
        } else if let segmented = view as? NSSegmentedControl {
            for index in 0..<segmented.segmentCount {
                if let label = segmented.label(forSegment: index),
                   !label.isEmpty {
                    result.append(label)
                }
            }
        } else if let button = view as? NSButton, !button.title.isEmpty {
            result.append(button.title)
        }
        for subview in view.subviews {
            result.append(contentsOf: renderedText(in: subview))
        }
        return result
    }

    private static func sampleBaseName(_ filename: String) -> String {
        (filename as NSString).deletingPathExtension
            .uppercased()
            .replacingOccurrences(of: "_", with: " ")
    }

    private static func loadedFilename(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(
                forTypeIdentifier: typeIdentifier
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url.lastPathComponent)
                } else {
                    continuation.resume(
                        throwing: RegressionFailure(
                            "The native drag provider returned no file."
                        )
                    )
                }
            }
        }
    }

    private static func writeTestWAV(to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 44_100,
            channels: 1,
            interleaved: true
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_205),
              let samples = buffer.int16ChannelData?[0]
        else {
            throw RegressionFailure("Could not allocate the test WAV.")
        }
        buffer.frameLength = 2_205
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = Int16(sin(Double(frame) * 0.04) * 8_000)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        try file.write(from: buffer)
    }

    private static func appendCueMarkers(
        _ sampleOffsets: [UInt32],
        to wavURL: URL
    ) throws {
        var data = try Data(contentsOf: wavURL)
        guard data.count >= 12,
              Data(data[0..<4]) == Data("RIFF".utf8),
              Data(data[8..<12]) == Data("WAVE".utf8)
        else {
            throw RegressionFailure("The generated marker source is not RIFF/WAVE.")
        }
        var payload = Data()
        appendLittleEndian(UInt32(sampleOffsets.count), to: &payload)
        for (index, sampleOffset) in sampleOffsets.enumerated() {
            appendLittleEndian(UInt32(index + 1), to: &payload)
            appendLittleEndian(sampleOffset, to: &payload)
            payload.append(Data("data".utf8))
            appendLittleEndian(UInt32(0), to: &payload)
            appendLittleEndian(UInt32(0), to: &payload)
            appendLittleEndian(sampleOffset, to: &payload)
        }
        data.append(Data("cue ".utf8))
        appendLittleEndian(UInt32(payload.count), to: &data)
        data.append(payload)
        if !payload.count.isMultiple(of: 2) { data.append(0) }
        let riffSize = UInt32(data.count - 8)
        data[4] = UInt8(riffSize & 0xFF)
        data[5] = UInt8((riffSize >> 8) & 0xFF)
        data[6] = UInt8((riffSize >> 16) & 0xFF)
        data[7] = UInt8((riffSize >> 24) & 0xFF)
        try data.write(to: wavURL, options: .atomic)
    }

    private static func appendLittleEndian(
        _ value: UInt32,
        to data: inout Data
    ) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private static func createTestApplication(
        at url: URL,
        launchLog: URL
    ) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let executableDirectory = contents.appendingPathComponent(
            "MacOS",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: executableDirectory,
            withIntermediateDirectories: true
        )
        let executable = executableDirectory.appendingPathComponent(
            "Test Audio Editor"
        )
        try Data(
            "#!/bin/sh\n/usr/bin/touch '\(launchLog.path)'\nexit 0\n".utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let propertyList: [String: Any] = [
            "CFBundleIdentifier": "test.akai.interaction-audio-editor",
            "CFBundleName": "Test Audio Editor",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "Test Audio Editor"
        ]
        let propertyListData = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        try propertyListData.write(
            to: contents.appendingPathComponent("Info.plist")
        )
    }
}

private struct RegressionFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
