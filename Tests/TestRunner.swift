import AVFoundation
import Foundation

@main
struct TestRunner {
    private static var passed = 0
    private static var failed = 0
    private static let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    static func main() async {
        test("shared IMG, P9 and S9 tags use the FIND950-compatible store") {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
                "edit950-tags-\(UUID().uuidString)",
                isDirectory: true
            )
            defer { try? FileManager.default.removeItem(at: temporary) }
            let image = temporary.appendingPathComponent("COLLECTION.img")
            let firstStore = SharedTagLibrary(directoryURL: temporary)
            let secondStore = SharedTagLibrary(directoryURL: temporary)
            _ = try firstStore.bootstrap()
            let drums = LibraryTag(name: "Drums", colorHex: "#FF5500")
            let favourite = LibraryTag(name: "Favourite", colorHex: "#3388FF")
            _ = try firstStore.update { document in
                document.tags = [drums, favourite]
                document.set(true, tagID: drums.id, for: .image(image))
                document.set(
                    true,
                    tagID: favourite.id,
                    for: .entry(
                        imageURL: image,
                        volumePath: "/disk0/A/BREAKS",
                        kind: .program,
                        filename: "AMEN.P9"
                    )
                )
            }
            _ = try secondStore.update { document in
                document.set(
                    true,
                    tagID: drums.id,
                    for: .entry(
                        imageURL: image,
                        volumePath: "/disk0/A/BREAKS/",
                        kind: .sample,
                        filename: "amen.s9"
                    )
                )
            }
            let loaded = try firstStore.load()
            try expect(loaded.tags(for: .image(image)) == [drums])
            try expect(loaded.tags(for: .entry(
                imageURL: image,
                volumePath: "/disk0/A/BREAKS",
                kind: .program,
                filename: "amen.p9"
            )) == [favourite])
            try expect(loaded.tags(for: .entry(
                imageURL: image,
                volumePath: "/disk0/A/BREAKS",
                kind: .sample,
                filename: "AMEN.S9"
            )) == [drums])
        }

        test("shared sample tags follow verified rename identity and clear on deletion") {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
                "edit950-tag-mutation-\(UUID().uuidString)",
                isDirectory: true
            )
            defer { try? FileManager.default.removeItem(at: temporary) }
            let image = temporary.appendingPathComponent("COLLECTION.img")
            let store = SharedTagLibrary(directoryURL: temporary)
            _ = try store.bootstrap()
            let tag = LibraryTag(name: "Break", colorHex: "#AA33CC")
            let source = SharedTagTarget.entry(
                imageURL: image,
                volumePath: "/disk0/A/BREAKS",
                kind: .sample,
                filename: "AMEN.S9"
            )
            let renamed = SharedTagTarget.entry(
                imageURL: image,
                volumePath: "/disk0/A/BREAKS",
                kind: .sample,
                filename: "AMEN2.S9"
            )
            var document = try store.update {
                $0.tags = [tag]
                $0.set(true, tagID: tag.id, for: source)
            }
            document = try store.update { $0.moveAssignments(from: source, to: renamed) }
            try expect(document.tags(for: source).isEmpty)
            try expect(document.tags(for: renamed) == [tag])
            document = try store.update { $0.removeAssignments(for: [renamed]) }
            try expect(document.tags(for: renamed).isEmpty)
        }

        test("shared tag index exports and relocates without deleting its previous copy") {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
                "edit950-tag-location-\(UUID().uuidString)",
                isDirectory: true
            )
            defer { try? FileManager.default.removeItem(at: temporary) }
            let sourceDirectory = temporary.appendingPathComponent(
                "Source",
                isDirectory: true
            )
            let destinationDirectory = temporary.appendingPathComponent(
                "Destination",
                isDirectory: true
            )
            let exportURL = temporary.appendingPathComponent("950TOOLS-tags.json")
            let source = SharedTagLibrary(directoryURL: sourceDirectory)
            _ = try source.bootstrap()
            let tag = LibraryTag(name: "Archive", colorHex: "#22AA88")
            let expected = try source.update { $0.tags = [tag] }

            try source.export(to: exportURL)
            let exported = try JSONDecoder().decode(
                SharedTagDocument.self,
                from: Data(contentsOf: exportURL)
            )
            try expect(exported == expected)

            let relocated = try source.relocate(
                to: destinationDirectory,
                activateSharedLocation: false
            )
            let relocatedDocument = try relocated.load()
            try expect(relocatedDocument == expected)
            try expect(FileManager.default.fileExists(atPath: source.fileURL.path))
        }

        test("950TOOLS protocol v1 decodes a focused export request") {
            let json = #"""
            {
              "protocol": "com.e45recordings.akai-tools",
              "protocolVersion": 1,
              "messageType": "aim.export-program.request",
              "requestID": "6c860590-c45c-4809-bb23-d3233153f2ae",
              "createdAt": "2026-08-10T12:05:00Z",
              "sender": {
                "productID": "com.e45recordings.FIND950",
                "version": "0.2.0"
              },
              "response": {
                "path": "/Users/example/S950 Library/response.json",
                "expiresAt": "2026-08-10T18:35:00Z"
              },
              "source": {
                "path": "/Users/example/S950 Library/COLLECTION.img",
                "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
              },
              "program": {
                "volumePath": "/disk0/A/BREAKS",
                "directoryIndex": 7,
                "filename": "AMEN.P9",
                "internalName": "AMEN"
              },
              "observedDependencies": [
                { "directoryIndex": 8, "filename": "AMEN.S9", "internalName": "AMEN" }
              ],
              "openInTRUE950AfterExport": true
            }
            """#
            let referenceNow = ISO8601DateFormatter().date(
                from: "2026-08-10T12:10:00Z"
            )!
            let request = try Tools950Interop.decodeRequest(
                Data(json.utf8),
                now: referenceNow
            )
            try expect(request.messageType == .exportProgramRequest)
            try expect(request.program.directoryIndex == 7)
            try expect(request.observedDependencies?.map(\.filename) == ["AMEN.S9"])
            try expect(request.openInPLAY950AfterExport == true)
        }

        test("950TOOLS responses identify the running EDIT950 bundle") {
            let sender = Tools950Interop.responseSender(infoDictionary: [
                "CFBundleShortVersionString": "1.8.23",
                "CFBundleVersion": "41"
            ])
            try expect(sender.productID == "com.e45recordings.EDIT950")
            try expect(sender.version == "1.8.23")
            try expect(sender.build == "41")
        }

        test("950TOOLS protocol rejects unknown versions and incomplete export requests") {
            func request(version: Int, dependencies: String) -> Data {
                Data(#"""
                {
                  "protocol": "com.e45recordings.akai-tools",
                  "protocolVersion": \#(version),
                  "messageType": "aim.export-program.request",
                  "requestID": "6c860590-c45c-4809-bb23-d3233153f2ae",
                  "createdAt": "2026-08-10T12:05:00Z",
                  "sender": { "productID": "test.sender", "version": "1.0" },
                  "response": {
                    "path": "/tmp/response.json",
                    "expiresAt": "2026-08-10T18:35:00Z"
                  },
                  "source": {
                    "path": "/tmp/COLLECTION.img",
                    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                  },
                  "program": {
                    "volumePath": "/disk0/A/BREAKS",
                    "directoryIndex": 7,
                    "filename": "AMEN.P9"
                  }
                  \#(dependencies)
                }
                """#.utf8)
            }
            try expectThrows {
                _ = try Tools950Interop.decodeRequest(
                    request(version: 2, dependencies: #", "observedDependencies": []"#)
                )
            }
            try expectThrows {
                _ = try Tools950Interop.decodeRequest(request(version: 1, dependencies: ""))
            }
        }

        test("950TOOLS protocol enforces document, path, hash, array and field bounds") {
            try expectThrows {
                _ = try Tools950Interop.decodeRequest(
                    Data(repeating: UInt8(ascii: " "), count: 65_537)
                )
            }
            let base = #"""
            {
              "protocol":"com.e45recordings.akai-tools",
              "protocolVersion":1,
              "messageType":"aim.export-program.request",
              "requestID":"6c860590-c45c-4809-bb23-d3233153f2ae",
              "createdAt":"2026-08-10T12:05:00Z",
              "sender":{"productID":"test.sender","version":"1.0"},
              "response":{"path":"/tmp/response.json","expiresAt":"2026-08-10T18:35:00Z"},
              "source":{"path":"SOURCE_PATH","sha256":"SOURCE_HASH"},
              "program":{"volumePath":"/disk0/A/VOLUME 001","directoryIndex":41,"filename":"PROGRAM.P9"},
              "observedDependencies":DEPENDENCIES
              EXTRA
            }
            """#
            let validHash = String(repeating: "a", count: 64)
            func data(
                path: String = "/tmp/source.img",
                hash: String = validHash,
                dependencies: String = "[]",
                extra: String = ""
            ) -> Data {
                Data(base
                    .replacingOccurrences(of: "SOURCE_PATH", with: path)
                    .replacingOccurrences(of: "SOURCE_HASH", with: hash)
                    .replacingOccurrences(of: "DEPENDENCIES", with: dependencies)
                    .replacingOccurrences(of: "EXTRA", with: extra)
                    .utf8)
            }
            try expectThrows { _ = try Tools950Interop.decodeRequest(data(path: "relative.img")) }
            try expectThrows { _ = try Tools950Interop.decodeRequest(data(path: "/tmp/../source.img")) }
            try expectThrows { _ = try Tools950Interop.decodeRequest(data(hash: validHash.uppercased())) }
            try expectThrows { _ = try Tools950Interop.decodeRequest(data(extra: #", "command":"put EVIL.S9""#)) }
            let dependency = #"{"filename":"ONE.S9"}"#
            let dependencies = "[" + Array(repeating: dependency, count: 129).joined(separator: ",") + "]"
            try expectThrows {
                _ = try Tools950Interop.decodeRequest(data(dependencies: dependencies))
            }
        }

        test("AKAI command construction rejects unsafe local paths") {
            try expectThrows { _ = try AkaiCommandBuilder.localDirectory("/tmp/has space") }
            let local = try AkaiCommandBuilder.localDirectory("/tmp/safe")
            let directory = try AkaiCommandBuilder.changeDirectory("/disk0/A/DRUM SET")
            let importCommand = try AkaiCommandBuilder.importWAV(
                filename: "KICK.wav",
                options: ImportOptions(family: .s900, compressedS900: true)
            )
            let nativeImport = try AkaiCommandBuilder.importNative(filename: "KICK.S9")
            let nativeExport = try AkaiCommandBuilder.exportNative(index: 12)
            let wavExport = try AkaiCommandBuilder.exportWAV(index: 12)
            let fileInfo = try AkaiCommandBuilder.fileInformation(index: 12)
            let pathDelete = try AkaiCommandBuilder.delete(path: "PROGRAM ONE.P9")
            try expect(local == "lcd /tmp/safe")
            try expect(directory == "cd /disk0/A/DRUM_SET")
            try expect(importCommand == "wav2sample9c KICK.wav")
            try expect(nativeImport == "put KICK.S9")
            try expect(nativeExport == "geti 12")
            try expect(fileInfo == "infoi 12")
            try expect(pathDelete == "del PROGRAM_ONE.P9")
            try expect(AkaiCommandBuilder.modifiesImage(nativeImport))
            try expect(AkaiCommandBuilder.modifiesImage(pathDelete))
            try expect(AkaiCommandBuilder.modifiesImage("fixramnameall"))
            try expect(AkaiCommandBuilder.modifiesImage("formatharddisk9 32M"))
            try expect(!AkaiCommandBuilder.modifiesImage(nativeExport))
            try expect(!AkaiCommandBuilder.modifiesImage(wavExport))
            try expect(!AkaiCommandBuilder.modifiesImage("dir"))
        }

        test("prompt detection waits for a terminal AKAI prompt") {
            let partial = "working\n/disk0/A/VOLUME 001 > more"
            try expect(PromptDetector.terminalPromptRange(in: partial) == nil)
            let complete = "working\n/disk0/A/VOLUME 001 > "
            try expect(PromptDetector.promptPath(in: complete) == "/disk0/A/VOLUME 001")
            try expect(PromptDetector.responseBeforePrompt(complete) == "working")
        }

        test("df parser creates structured disks and partitions") {
            let output = try fixture("df.txt")
            let parsed = AkaiOutputParser.parseDF(output)
            try expect(parsed.0.count == 1)
            try expect(parsed.0[0].blockSize == 1024)
            try expect(parsed.0[0].totalBlocks == 800)
            try expect(parsed.0[0].freeBlocks == 752)
            try expect(parsed.1.count == 1)
            try expect(parsed.1[0].letter == "A")
        }

        test("directory parser handles spaces, compression and stable indexes") {
            let output = try fixture("ls.txt")
            let parsed = AkaiOutputParser.parseDirectory(output)
            let parsedAgain = AkaiOutputParser.parseDirectory(output)
            try expect(parsed.0.count == 3)
            try expect(parsed.0[1].index == 12)
            try expect(parsed.0[1].name == "LONG SAMPLE.S")
            try expect(parsed.0[1].compression == "65536")
            try expect(parsed.0[2].type == "Program")
            try expect(parsed.0.map(\.id) == parsedAgain.0.map(\.id))
            try expect(parsed.1 == 64)
            try expect(parsed.2 == 3)
        }

        test("native drag names omit the provider extension and preserve exact exported names") {
            try expect(NativeAkaiFileExport.dragSuggestedName(for: "SAMPLE.P9") == "SAMPLE")
            try expect(NativeAkaiFileExport.dragSuggestedName(for: "BASS.S9") == "BASS")
            try expect(NativeAkaiFileExport.isSupported("SAMPLE.P9"))
            try expect(!NativeAkaiFileExport.isSupported("SAMPLE.P9.p9"))

            let workspace = try temporaryDirectory("native-name")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let lowercase = workspace.appendingPathComponent("always.p9")
            try Data("program".utf8).write(to: lowercase)
            let normalized = try NativeAkaiFileExport.normalizeExportedFile(
                lowercase,
                expectedFilename: "SAMPLE.P9"
            )
            try expect(normalized.lastPathComponent == "SAMPLE.P9")
            try expect(FileManager.default.fileExists(atPath: normalized.path))
        }

        test("native S9 collision renaming changes only the internal ten-byte name") {
            var source = Data(repeating: 0xA5, count: 64)
            source.replaceSubrange(0..<10, with: Data("OLDNAME   ".utf8))
            let renamed = try S9NativeSample.renamingInternalName(
                in: source,
                to: "BREAK_2"
            )
            let internalName = try S9NativeSample.internalName(in: renamed)
            try expect(String(decoding: renamed[0..<10], as: UTF8.self) == "BREAK_2   ")
            try expect(internalName == "BREAK_2")
            try expect(renamed[10...] == source[10...])
            try expect(source[0] == UInt8(ascii: "O"))
        }

        test("native S9 attributes preserve unknown bytes and scale marker loops") {
            let source = makeS9Fixture(
                sampleLength: 500,
                nominalPitchSixteenths: 60 * 16 + 5
            )
            let original = try S9NativeSample.attributes(in: source)
            try expect(original.rootNote == 60)
            try expect(original.finePitchSixteenths == 5)
            try expect(original.playbackMode == .oneShot)
            try expect(original.playbackDirection == .normal)

            let settings = S9SampleEditSettings(
                rootNote: 64,
                playbackMode: .alternatingLoop,
                playbackDirection: .reverse
            )
            let edited = try S9NativeSample.applying(
                settings,
                cueSampleOffsets: [800, 200],
                editedWAVFrameCount: 1_000,
                to: source,
                retainedFinePitchSixteenths: original.finePitchSixteenths
            )
            let attributes = try S9NativeSample.attributes(in: edited)
            try expect(attributes.nominalPitchSixteenths == 64 * 16 + 5)
            try expect(attributes.playbackMode == .alternatingLoop)
            try expect(attributes.playbackDirection == .reverse)
            try expect(attributes.playbackEnd == 400)
            try expect(attributes.loopLength == 300)
            try expect(attributes.loopStart == 100)

            let oneShot = try S9NativeSample.applying(
                S9SampleEditSettings(
                    rootNote: 60,
                    playbackMode: .oneShot,
                    playbackDirection: .normal
                ),
                cueSampleOffsets: [200, 800],
                editedWAVFrameCount: 1_000,
                to: source,
                retainedFinePitchSixteenths: original.finePitchSixteenths
            )
            let oneShotAttributes = try S9NativeSample.attributes(in: oneShot)
            try expect(oneShotAttributes.playbackMode == .oneShot)
            try expect(oneShotAttributes.playbackEnd == 400)
            try expect(oneShotAttributes.loopLength == 300)
            try expect(oneShotAttributes.loopStart == 100)

            let documentedOffsets = Set(
                [0x16, 0x17, 0x1A, 0x2B]
                    + Array(0x1C...0x1F)
                    + Array(0x24...0x27)
            )
            let changed = Set(source.indices.filter { source[$0] != edited[$0] })
            try expect(changed.isSubset(of: documentedOffsets))
            try expect(edited[0x2C...] == source[0x2C...])
            try expectThrows {
                _ = try S9NativeSample.applying(
                    settings,
                    cueSampleOffsets: [],
                    editedWAVFrameCount: 1_000,
                    to: source
                )
            }
            try expectThrows {
                _ = try S9NativeSample.applying(
                    settings,
                    cueSampleOffsets: [200, 800, 900],
                    editedWAVFrameCount: 1_000,
                    to: source
                )
            }
            try expectThrows {
                _ = try S9NativeSample.applying(
                    settings,
                    cueSampleOffsets: [800, 1_001],
                    editedWAVFrameCount: 1_000,
                    to: source
                )
            }

            let typedLoop = try S9NativeSample.applying(
                S9SampleEditSettings(
                    rootNote: 60,
                    playbackMode: .loop,
                    playbackDirection: .normal
                ),
                cueSampleOffsets: [],
                editedWAVFrameCount: 500,
                to: source,
                explicitLoopPoints: S9LoopPoints(start: 123, end: 456)
            )
            let typedAttributes = try S9NativeSample.attributes(in: typedLoop)
            try expect(typedAttributes.loopStart == 123)
            try expect(typedAttributes.playbackEnd == 456)
            try expect(typedAttributes.loopLength == 333)
            try expectThrows {
                _ = try S9NativeSample.applying(
                    settings,
                    cueSampleOffsets: [],
                    editedWAVFrameCount: 500,
                    to: source,
                    explicitLoopPoints: S9LoopPoints(start: 400, end: 600)
                )
            }
        }

        test("standard WAV cue markers and native S9 chunks parse independently") {
            let header = makeS9Fixture(
                sampleLength: 27_790,
                nominalPitchSixteenths: 60 * 16
            ).prefix(S9NativeSample.headerLength)
            let wav = makeMarkerWAV(
                cueSampleOffsets: [19_064, 4_726],
                s9Header: Data(header)
            )
            let parsedCues = try WAVService.cueSampleOffsets(in: wav)
            try expect(parsedCues == [19_064, 4_726])
            let parsedHeader = try WAVService.nativeS9Header(in: wav)
            try expect(parsedHeader == Data(header))
            let parsedAttributes = try S9NativeSample.attributes(
                in: parsedHeader!
            )
            try expect(parsedAttributes.sampleLength == 27_790)

            let importHeader = try S9NativeSample.nativeHeaderForWAVImport(
                existingHeader: nil,
                preparedFrameCount: 13_895,
                preparedSampleRate: 48_000,
                cueSampleOffsets: parsedCues,
                sourceFrameCount: 27_790
            )
            let imported = try S9NativeSample.attributes(in: importHeader)
            try expect(imported.playbackMode == .oneShot)
            try expect(imported.loopStart == 2_363)
            try expect(imported.playbackEnd == 9_532)

            let workspace = try temporaryDirectory("s9h-replace")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let wavURL = workspace.appendingPathComponent("MARKERS.wav")
            try wav.write(to: wavURL)
            try WAVService.replaceNativeS9Header(
                in: wavURL,
                with: importHeader
            )
            let rewrittenData = try Data(contentsOf: wavURL)
            let rewrittenHeader = try WAVService.nativeS9Header(
                in: rewrittenData
            )
            try expect(rewrittenHeader == importHeader)
            let rewrittenCues = try WAVService.cueSampleOffsets(
                in: rewrittenData
            )
            try expect(rewrittenCues == parsedCues)

            try WAVService.replaceCueSampleOffsets(
                [5_000, 18_000],
                in: wavURL
            )
            let labelledData = try Data(contentsOf: wavURL)
            let labelledCues = try WAVService.cueSampleOffsets(
                in: labelledData
            )
            try expect(labelledCues == [5_000, 18_000])
            let markerText = String(decoding: labelledData, as: UTF8.self)
            try expect(markerText.contains("LIST"))
            try expect(markerText.contains("adtl"))
            try expect(markerText.contains("Loop Start"))
            try expect(markerText.contains("Loop End"))
            let labelledHeader = try WAVService.nativeS9Header(
                in: labelledData
            )
            try expect(labelledHeader == importHeader)

            var loopHeader = Data(header)
            writeLittleEndian(UInt32(20_000), to: &loopHeader, at: 0x1C)
            writeLittleEndian(UInt32(10_000), to: &loopHeader, at: 0x24)
            let unmarkedWAV = makeMarkerWAV(
                cueSampleOffsets: [],
                s9Header: loopHeader
            )
            let unmarkedURL = workspace.appendingPathComponent("NATIVE-LOOP.wav")
            try unmarkedWAV.write(to: unmarkedURL)
            let addedNativeMarkers = try WAVService.addNativeS9LoopMarkers(
                to: unmarkedURL
            )
            try expect(addedNativeMarkers)
            let generatedMarkers = try WAVService.cueSampleOffsets(
                in: unmarkedURL
            )
            try expect(generatedMarkers == [1, 3])
            let generatedText = String(
                decoding: try Data(contentsOf: unmarkedURL),
                as: UTF8.self
            )
            try expect(generatedText.contains("Loop Start"))
            try expect(generatedText.contains("Loop End"))
        }

        test("S950 bandwidth conversion maps rates and preserves scaled loops") {
            try expect(S950BandwidthConversion(bandwidth: 3_000, mode: .antiAliased).sampleRate == 7_500)
            try expect(S950BandwidthConversion(bandwidth: 19_200, mode: .raw).sampleRate == 48_000)
            try expect(S950BandwidthConversion.bandwidth(forSampleRate: 25_000) == 10_000)
            let workspace = try temporaryDirectory("s950-bandwidth")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let source = workspace.appendingPathComponent("source.wav")
            try makeMarkerWAV(cueSampleOffsets: [1, 3], s9Header: Data(repeating: 0, count: 60)).write(to: source)
            for mode in S950ResamplingMode.allCases {
                let output = workspace.appendingPathComponent("\(mode.rawValue).wav")
                let inspection = try WAVService.resampleS950(
                    source, to: output,
                    conversion: S950BandwidthConversion(bandwidth: 9_600, mode: mode)
                )
                try expect(Int(inspection.sampleRate) == 24_000)
                try expect(inspection.frameCount == 2)
                try expect(inspection.bitDepth == 16)
                let markers = try WAVService.cueSampleOffsets(in: output)
                try expect(markers == [1, 2])
            }
        }

        test("zero-crossing navigation is strict and reports waveform direction") {
            let map = WAVZeroCrossingMap(
                samples: [-1, -0.5, 0, 0, 0.25, 0.5, -0.25, 0, 0.5]
            )
            try expect(
                map.crossings == [
                    WAVZeroCrossing(frame: 2, direction: .upward),
                    WAVZeroCrossing(frame: 6, direction: .downward),
                    WAVZeroCrossing(frame: 7, direction: .upward)
                ]
            )
            try expect(map.previous(before: 6)?.frame == 2)
            try expect(map.next(after: 6)?.frame == 7)
            try expect(map.direction(at: 6) == .downward)
            try expect(map.direction(at: 5) == nil)
            try expect(map.previous(before: 2) == nil)
            try expect(map.next(after: 7) == nil)
        }

        test("application chooser uses real runnable macOS application bundles") {
            try expect(
                AppSettings.applicationBundleContentType.identifier
                    == "com.apple.application-bundle"
            )
            let workspace = try temporaryDirectory("application-bundle")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let application = workspace.appendingPathComponent(
                "Test Audio Editor.app",
                isDirectory: true
            )
            let contents = application.appendingPathComponent(
                "Contents",
                isDirectory: true
            )
            let executableDirectory = contents.appendingPathComponent(
                "MacOS",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: executableDirectory,
                withIntermediateDirectories: true
            )
            let executable = executableDirectory.appendingPathComponent("Test Audio Editor")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executable.path
            )
            let propertyList: [String: Any] = [
                "CFBundleIdentifier": "test.akai.audio-editor",
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

            try expect(AppSettings.isRunnableApplication(at: application))
            try expect(
                !AppSettings.isRunnableApplication(
                    at: workspace.appendingPathComponent("not-an-app")
                )
            )
        }

        test("P9 programs round-trip without changing any unknown bytes") {
            let source = makeP9Fixture(keygroupCount: 2)
            let program = try P9Program(data: source)
            try expect(program.name == "JUNGLE")
            try expect(program.keygroups.count == 2)
            try expect(program.keygroups[0].envelope == P9Envelope(attack: 0, decay: 80, sustain: 99, release: 30))
            try expect(program.keygroups[0].vcfEnvelope == P9Envelope(attack: 20, decay: 20, sustain: 20, release: 20))
            try expect(program.keygroups[0].softSampleName == "AMEN-01")
            try expect(program.keygroups[0].output == .all)
            let encoded = try program.encoded()
            try expect(encoded == source)
        }

        test("MIDI monitor matches keygroup note ranges and channels") {
            var program = try P9Program(data: makeP9Fixture(keygroupCount: 2))
            program.keygroups[0].lowKey = 36
            program.keygroups[0].highKey = 40
            program.keygroups[0].midiChannelOffset = 0
            program.keygroups[1].lowKey = 40
            program.keygroups[1].highKey = 48
            program.keygroups[1].midiChannelOffset = 1

            try expect(
                MIDIKeygroupTriggerMatcher.matches(
                    program.keygroups[0],
                    activeNotes: [MIDINoteKey(channel: 0, note: 38): 100]
                )
            )
            try expect(
                !MIDIKeygroupTriggerMatcher.matches(
                    program.keygroups[0],
                    activeNotes: [MIDINoteKey(channel: 1, note: 38): 100]
                )
            )
            try expect(
                MIDIKeygroupTriggerMatcher.matches(
                    program.keygroups[1],
                    activeNotes: [MIDINoteKey(channel: 1, note: 40): 1]
                )
            )
            try expect(
                !MIDIKeygroupTriggerMatcher.matches(
                    program.keygroups[1],
                    activeNotes: [MIDINoteKey(channel: 1, note: 49): 127]
                )
            )
        }

        test("hardware P9 proves Key-filter 0x08 and independent LFO Depth 0x16") {
            let base64 = "S0VZRklMVEVSIAAAAAAAAAAAUMUAAP8CAAAA/wAAAAAAAAAAAAA7MIAAUGMeAAAAAAAAAGNAKgAE/wAAMgBGSUxUU0FXICAgFBQUFEAA3MUAAGMAICAgICAgICAgIAAAAAAAAAAAAABjAJbFRzyAAFBjHgBjAAAAAABjQCoABP8AADIARklMVFNBVyAgIBQUFBRAANzFAABjACAgICAgICAgICAAAAAAAAAAAAAAYwAAAA=="
            guard let source = Data(base64Encoded: base64) else {
                throw TestFailure.fixture
            }
            var program = try P9Program(data: source)
            try expect(program.keygroups.count == 2)
            try expect(program.keygroups[0].keyFilter == 0)
            try expect(program.keygroups[1].keyFilter == 99)
            try expect(program.keygroups[0].lfoDepth == 50)
            try expect(program.keygroups[1].lfoDepth == 50)
            let unedited = try program.encoded()
            try expect(unedited == source)

            let second = P9Program.headerSize + P9Program.keygroupSize
            program.keygroups[1].keyFilter = 50
            program.keygroups[1].lfoDepth = 25
            let edited = try program.encoded()
            let changed = Set(source.indices.filter { source[$0] != edited[$0] })
            try expect(changed == Set([second + 0x08, second + 0x16]))
            try expect(edited[second + 0x08] == 50)
            try expect(edited[second + 0x16] == 25)
        }

        test("P9 canonical names are resolved once for model, IMG and AKAI Util") {
            let cases: [(String, String)] = [
                ("Beat123", "BEAT123"),
                ("DRUM KIT", "DRUM KIT"),
                ("DRUM_KIT", "DRUM KIT"),
                ("KICK-HARD", "KICK-HARD"),
                ("lowercase", "LOWERCASE"),
                ("ABCDEFGHIJKLMN", "ABCDEFGHIJ"),
                ("BAD!?NAME", "BAD-NAME"),
                ("READY.P9", "READY")
            ]
            for (input, expected) in cases {
                let identity = try P9CanonicalName.resolve(input)
                try expect(identity.base == expected)
                try expect(identity.filename == "\(expected).P9")
                try expect(identity.stagingFilename == "\(expected.replacingOccurrences(of: " ", with: "_")).P9")
                let program = try P9Program.blank(named: identity.base)
                try expect(program.name == expected)
                let bytes = try program.encoded()
                let reopened = try P9Program(data: bytes)
                try expect(reopened.name == expected)
            }
            try expectThrows { _ = try P9CanonicalName.resolve("   ") }

            let duplicate = try P9CanonicalName.resolve(
                "PROGRAM",
                existingFilenames: ["PROGRAM.P9"]
            )
            try expect(duplicate.base == "PROGRAM-2")
            let canonicalCollision = try P9CanonicalName.resolve(
                "DRUM_KIT",
                existingFilenames: ["DRUM KIT.P9", "DRUM_KIT-2.P9"]
            )
            try expect(canonicalCollision.base == "DRUM KIT-3")
            try expect(P9CanonicalName.lookupKey("DRUM_KIT.P9") == "DRUM KIT")
        }

        test("P9 serialization depends only on final envelope and filter model") {
            let source = try P9Program.blank(named: "PUREMODEL").encoded()
            var amplitudeOnly = try P9Program(data: source)
            amplitudeOnly.keygroups[0].envelope = .init(
                attack: 25, decay: 50, sustain: 75, release: 99
            )
            let amplitudeBytes = try amplitudeOnly.encoded()
            let reopenedAmplitude = try P9Program(data: amplitudeBytes)
            try expect(reopenedAmplitude.keygroups[0].envelope == amplitudeOnly.keygroups[0].envelope)

            var vcfOnly = try P9Program(data: source)
            vcfOnly.keygroups[0].vcfEnvelope = .init(
                attack: 99, decay: 75, sustain: 50, release: 25
            )
            let vcfBytes = try vcfOnly.encoded()
            let reopenedVCF = try P9Program(data: vcfBytes)
            try expect(reopenedVCF.keygroups[0].vcfEnvelope == vcfOnly.keygroups[0].vcfEnvelope)

            var both = try P9Program(data: source)
            both.keygroups[0].envelope = amplitudeOnly.keygroups[0].envelope
            both.keygroups[0].vcfEnvelope = vcfOnly.keygroups[0].vcfEnvelope
            both.keygroups[0].softFilter = 40
            both.keygroups[0].vcfAmount = -50
            both.keygroups[0].velocitySensitivity.filter = 99
            let bothBytes = try both.encoded()
            let reopened = try P9Program(data: bothBytes)
            try expect(reopened.keygroups[0] == both.keygroups[0])
            let reopenedBytes = try reopened.encoded()
            try expect(reopenedBytes == bothBytes)

            var selfAssignment = try P9Program(data: source)
            selfAssignment.keygroups[0].envelope.attack = selfAssignment.keygroups[0].envelope.attack
            let selfAssignedBytes = try selfAssignment.encoded()
            try expect(selfAssignedBytes == source)
            selfAssignment.keygroups[0].envelope.attack = 88
            selfAssignment.keygroups[0].envelope.attack = 0
            let returnedBytes = try selfAssignment.encoded()
            try expect(returnedBytes == source)
        }

        test("P9 verification diagnostics identify the exact owned byte") {
            let expected = try P9Program.blank(named: "VERIFY").encoded()
            var exported = expected
            let absolute = P9Program.headerSize + P9Program.keygroupSize - 1
            exported[absolute] = 0x7E
            let message = P9Verification.differenceDescription(
                expected: expected,
                exported: exported
            )
            try expect(message.contains("keygroup 1 offset 0x45"))
            try expect(message.contains("expected 0x00"))
            try expect(message.contains("exported 0x7E"))
        }

        test("P9 image transition policy keeps local editors and protects drafts") {
            let image = URL(fileURLWithPath: "/tmp/FIXTURE.img")
            try expect(
                P9EditorImageTransitionPolicy.decision(
                    editorImageURL: nil,
                    currentImageURL: image,
                    hasUnwrittenChanges: true
                ) == .keepEditor
            )
            try expect(
                P9EditorImageTransitionPolicy.decision(
                    editorImageURL: image,
                    currentImageURL: image,
                    hasUnwrittenChanges: false
                ) == .closeEditor
            )
            try expect(
                P9EditorImageTransitionPolicy.decision(
                    editorImageURL: image,
                    currentImageURL: image,
                    hasUnwrittenChanges: true
                ) == .confirmDiscard
            )
        }

        test("PLAY950 fixture specification is complete and deterministic") {
            let specifications = PLAY950FixtureSpecification.programs
            try expect(specifications.count == 43)
            try expect(Set(specifications.map(\.name)).count == specifications.count)
            try expect(specifications.filter(\.oneShot).map(\.name) == ["ENVONESH"])
            let track = try specifications.first(where: { $0.name == "KEYTRACK" })
                .map { try $0.makeProgram() }
            guard let track else { throw TestFailure.fixture }
            let keygroup = track.keygroups[0]
            try expect(keygroup.keyFilter == 50)
            try expect(keygroup.lfoDepth == 0)
            try expect(!keygroup.constantPitch)
            try expect(keygroup.lowKey == 48 && keygroup.highKey == 72)
            let encoded = try track.encoded()
            try expect(encoded[P9Program.headerSize + 0x08] == 50)
            try expect(encoded[P9Program.headerSize + 0x16] == 0)
            for specification in specifications {
                let program = try specification.makeProgram()
                try expect(program.name == specification.name)
                try expect(!program.keygroups[0].constantPitch)
                try expect(program.keygroups[0].lfoDepth == 0)
                let bytes = try program.encoded()
                let reopened = try P9Program(data: bytes)
                let roundTrip = try reopened.encoded()
                try expect(roundTrip == bytes)
            }
        }

        test("P9 velocity sensitivity follows the S950 byte layout") {
            let source = makeP9Fixture(keygroupCount: 1)
            var program = try P9Program(data: source)
            let base = P9Program.headerSize

            try expect(program.keygroups[0].velocitySensitivity.loudness == 47)
            try expect(program.keygroups[0].velocitySensitivity.attack == 13)
            try expect(program.keygroups[0].velocitySensitivity.filter == 31)
            try expect(program.keygroups[0].velocitySensitivity.release == -7)

            program.keygroups[0].velocitySensitivity.loudness = 12
            program.keygroups[0].velocitySensitivity.attack = 34
            program.keygroups[0].velocitySensitivity.filter = 56
            program.keygroups[0].velocitySensitivity.release = -20

            let edited = try program.encoded()
            let changed = Set(source.indices.filter { source[$0] != edited[$0] })
            try expect(changed == Set([
                base + 0x07,
                base + 0x09,
                base + 0x0A,
                base + 0x0B
            ]))
            try expect(edited[base + 0x08] == 52)
        }

        test("P9 VCF amount uses byte 0x17 and preserves byte 0x27") {
            var source = makeP9Fixture(keygroupCount: 1)
            let base = P9Program.headerSize
            source[base + 0x17] = UInt8(bitPattern: Int8(-25))
            source[base + 0x27] = 0x5A

            var program = try P9Program(data: source)
            try expect(program.keygroups[0].vcfAmount == -25)
            let unedited = try program.encoded()
            try expect(unedited == source)

            program.keygroups[0].vcfAmount = 22
            let edited = try program.encoded()
            let changed = Set(source.indices.filter { source[$0] != edited[$0] })
            try expect(changed == Set([base + 0x17]))
            try expect(edited[base + 0x27] == 0x5A)
        }

        test("P9 tuning matches the S950 coarse and signed-fine display") {
            let positive = P9Tuning(rawSixteenths: 369)
            try expect(positive.transpose == 23)
            try expect(positive.fine == 1)
            try expect(positive.rawSixteenths == 369)

            let hardwareExample = P9Tuning(rawSixteenths: 380)
            try expect(hardwareExample.transpose == 24)
            try expect(hardwareExample.fine == -4)
            try expect(hardwareExample.rawSixteenths == 380)

            let negative = P9Tuning(rawSixteenths: -17)
            try expect(negative.transpose == -1)
            try expect(negative.fine == -1)
            try expect(negative.rawSixteenths == -17)

            let normalized = P9Tuning(transpose: 23, fine: 12)
            try expect(normalized.transpose == 24)
            try expect(normalized.fine == -4)
            try expect(normalized.rawSixteenths == 380)
        }

        test("Ableton Drum Rack samples parse, rename and map with pad-note offsets") {
            let workspace = try temporaryDirectory("ableton-drum-rack")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let firstWAV = workspace.appendingPathComponent("SAMPLE first.wav")
            let secondWAV = workspace.appendingPathComponent("SAMPLE second.wav")
            try Data("first".utf8).write(to: firstWAV)
            try Data("second".utf8).write(to: secondWAV)
            let sourceURL = workspace.appendingPathComponent("Rack.adg")
            let xml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <Ableton>
                  <DrumBranchPreset Id="0">
                    <MultiSampler>
                      <Player>
                        <MultiSamplePart Id="0">
                          <Name Value="SAMPLE" />
                          <RootKey Value="60" />
                          <Detune Value="-25" />
                          <SampleRef><FileRef><Path Value="\(firstWAV.path)" /></FileRef></SampleRef>
                        </MultiSamplePart>
                      </Player>
                      <Filter>
                        <IsOn><Manual Value="true" /></IsOn>
                        <Slot><Value><SimplerFilter>
                          <Freq><Manual Value="1000" /></Freq>
                          <ModByVelocity><Manual Value="0.5" /></ModByVelocity>
                        </SimplerFilter></Value></Slot>
                      </Filter>
                      <VolumeAndPan>
                        <VolumeVelScale><Manual Value="0.5" /></VolumeVelScale>
                      </VolumeAndPan>
                    </MultiSampler>
                    <ReceivingNote Value="66" />
                  </DrumBranchPreset>
                  <DrumBranchPreset Id="1">
                    <MultiSampler>
                      <Player>
                        <MultiSamplePart Id="0">
                          <Name Value="SAMPLE" />
                          <RootKey Value="60" />
                          <Detune Value="0" />
                          <SampleRef><FileRef><Path Value="\(secondWAV.path)" /></FileRef></SampleRef>
                        </MultiSamplePart>
                      </Player>
                      <Filter>
                        <IsOn><Manual Value="false" /></IsOn>
                        <Slot><Value><SimplerFilter>
                          <Freq><Manual Value="30" /></Freq>
                          <ModByVelocity><Manual Value="1" /></ModByVelocity>
                        </SimplerFilter></Value></Slot>
                      </Filter>
                      <VolumeAndPan>
                        <VolumeVelScale><Manual Value="1" /></VolumeVelScale>
                      </VolumeAndPan>
                    </MultiSampler>
                    <ReceivingNote Value="68" />
                  </DrumBranchPreset>
                </Ableton>
                """
            let preset = try AbletonDrumRackParser.parseXML(
                Data(xml.utf8),
                sourceURL: sourceURL
            )
            try expect(preset.samples.map(\.sourceNote) == [62, 60])
            try expect(preset.samples.map(\.detectedRootNote) == [60, 60])
            try expect(preset.samples.map(\.detuneCents) == [-25, 0])
            try expect(preset.samples.map(\.s950Filter) == [53, 99])
            try expect(preset.samples.map(\.s950VelocityLoudness) == [50, 99])
            try expect(preset.samples.map(\.s950VelocityFilter) == [50, 0])

            var draft = AbletonDrumRackImportDraft(
                preset: preset,
                startNote: 39,
                existingSampleNames: ["SAMPLE"],
                existingKeygroupCount: 1,
                replacesBlankKeygroup: true
            )
            try expect(draft.rows.map(\.sampleName) == ["SAMPLE 2", "SAMPLE 3"])
            draft.rows[0].sampleName = "KICK"
            draft.rows[1].sampleName = "SNARE"
            draft.midiChannel = 10
            draft.output = .mono(4)
            try expect(draft.validationError == nil)

            let original = try P9Program.blank(named: "DRUMS")
            let program = try draft.appendingKeygroups(to: original)
            try expect(program.keygroups.count == 2)
            try expect(program.keygroups[0].lowKey == 39)
            try expect(program.keygroups[0].highKey == 39)
            try expect(program.keygroups[1].lowKey == 41)
            try expect(program.keygroups[1].highKey == 41)
            try expect(program.keygroups[0].softSampleName == "KICK")
            try expect(program.keygroups[1].softSampleName == "SNARE")
            try expect(program.keygroups[0].softTuning.transpose == 21)
            try expect(program.keygroups[0].softTuning.fine == -4)
            try expect(program.keygroups[1].softTuning.transpose == 19)
            try expect(program.keygroups.map(\.softFilter) == [53, 99])
            try expect(
                program.keygroups.map(\.velocitySensitivity.loudness) == [50, 99]
            )
            try expect(
                program.keygroups.map(\.velocitySensitivity.filter) == [50, 0]
            )
            try expect(program.keygroups[0].midiChannelOffset == 9)
            try expect(program.keygroups[0].output == .mono(4))
        }

        test("S950 keygroups export through the sanitized Live 12 Sampler template") {
            let workspace = try temporaryDirectory("ableton-sampler-export")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let samplesDirectory = workspace.appendingPathComponent(
                "Samples",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: samplesDirectory,
                withIntermediateDirectories: true
            )
            let kick = samplesDirectory.appendingPathComponent("KICK ONE.wav")
            let snare = samplesDirectory.appendingPathComponent("SNARE.wav")
            try Data("kick".utf8).write(to: kick)
            try Data("snare".utf8).write(to: snare)
            let template = root.appendingPathComponent(
                "Sources/EDIT950/Resources/AKAI-S950-Sampler-Template.adg"
            )
            let pads = [
                AbletonSamplerExportPad(
                    keygroupIndex: 0,
                    receivingNote: 36,
                    sampleName: "KICK ONE",
                    wavURL: kick,
                    sampleFrames: 8_087,
                    sampleRate: 44_100,
                    rootNote: 60,
                    detuneCents: -25,
                    s950Filter: 53,
                    s950VelocityLoudness: 50,
                    s950VelocityFilter: 50
                ),
                AbletonSamplerExportPad(
                    keygroupIndex: 1,
                    receivingNote: 37,
                    sampleName: "SNARE",
                    wavURL: snare,
                    sampleFrames: 4_096,
                    sampleRate: 22_050,
                    rootNote: 61,
                    detuneCents: 0,
                    s950Filter: 99,
                    s950VelocityLoudness: 99,
                    s950VelocityFilter: 0
                )
            ]
            let adg = try AbletonDrumRackExporter.generate(
                templateURL: template,
                rackName: "TEST RACK",
                pads: pads
            )
            try expect(adg.starts(with: [0x1F, 0x8B]))
            let xml = try AbletonDrumRackExporter.decompressedADG(adg)
            let xmlText = String(decoding: xml, as: UTF8.self)
            try expect(xmlText.contains("Creator=\"Ableton Live 12.4.3\""))
            try expect(xmlText.contains("Value=\"TEST RACK\""))
            try expect(!xmlText.contains("/Users/"))
            try expect(!xmlText.contains("AKAI-S950-EXPORT"))
            try expect(xmlText.contains("Samples/KICK ONE.wav"))
            try expect(xmlText.contains("<ReceivingNote Value=\"92\""))
            try expect(xmlText.contains("<ReceivingNote Value=\"91\""))
            try expect(
                xmlText.components(
                    separatedBy: "<RelativePathType Value=\"1\""
                ).count >= 5
            )

            let generatedURL = workspace.appendingPathComponent("TEST RACK.adg")
            let verified = try AbletonDrumRackParser.parseXML(
                xml,
                sourceURL: generatedURL
            )
            try expect(verified.samples.map(\.sourceNote) == [36, 37])
            try expect(verified.samples.map(\.sourceName) == ["KICK ONE", "SNARE"])
            try expect(verified.samples.map(\.detectedRootNote) == [60, 61])
            try expect(verified.samples.map(\.detuneCents) == [-25, 0])
            try expect(verified.samples.map(\.s950Filter) == [53, 99])
            try expect(verified.samples.map(\.s950VelocityLoudness) == [50, 99])
            try expect(verified.samples.map(\.s950VelocityFilter) == [50, 0])
        }

        test("Ableton Simpler sample references resolve component-based relative paths") {
            let workspace = try temporaryDirectory("ableton-simpler-relative")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let presetDirectory = workspace.appendingPathComponent(
                "Presets",
                isDirectory: true
            )
            let sampleDirectory = workspace.appendingPathComponent(
                "Samples",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: presetDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: sampleDirectory,
                withIntermediateDirectories: true
            )
            let sampleURL = sampleDirectory.appendingPathComponent(
                "Relative Sample.wav"
            )
            try Data("audio".utf8).write(to: sampleURL)
            let sourceURL = presetDirectory.appendingPathComponent("Rack.adg")
            let xml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <Ableton>
                  <DrumBranchPreset Id="0">
                    <OriginalSimpler>
                      <MultiSamplePart Id="0">
                        <Name Value="SIMPLER" />
                        <RootKey Value="64" />
                        <SampleRef>
                          <FileRef>
                            <RelativePath>
                              <RelativePathElement Dir="Samples" />
                            </RelativePath>
                            <Name Value="Relative Sample.wav" />
                          </FileRef>
                        </SampleRef>
                      </MultiSamplePart>
                    </OriginalSimpler>
                    <ReceivingNote Value="92" />
                  </DrumBranchPreset>
                </Ableton>
                """
            let preset = try AbletonDrumRackParser.parseXML(
                Data(xml.utf8),
                sourceURL: sourceURL
            )
            try expect(preset.samples.count == 1)
            try expect(
                preset.samples[0].sampleURL.standardizedFileURL
                    == sampleURL.standardizedFileURL
            )
            try expect(preset.samples[0].detectedRootNote == 64)
        }

        test("P9 release source and custom midpoint flags preserve other flag bits") {
            var source = makeP9Fixture(keygroupCount: 1)
            let base = P9Program.headerSize
            source[base + 0x12] = 0x34

            var program = try P9Program(data: source)
            try expect(program.keygroups[0].releaseVelocityFromNoteOn)
            try expect(program.keygroups[0].customVelocityCrossfadePoint)
            let unedited = try program.encoded()
            try expect(unedited == source)

            program.keygroups[0].releaseVelocityFromNoteOn = false
            program.keygroups[0].customVelocityCrossfadePoint = false
            let edited = try program.encoded()
            try expect(edited[base + 0x12] == 0x04)
            try expect(edited[base + 0x12] & 0x04 == 0x04)
            let changed = Set(source.indices.filter { source[$0] != edited[$0] })
            try expect(changed == Set([base + 0x12]))
        }

        test("P9 sample changes clear stale runtime addresses and keep exact names") {
            var source = makeP9Fixture(keygroupCount: 1)
            let base = P9Program.headerSize
            source[base + 0x28] = 0x80
            source[base + 0x29] = 0xC7
            source[base + 0x3E] = 0x0C
            source[base + 0x3F] = 0xC8
            source[base + 0x44] = 0x34
            source[base + 0x45] = 0x12

            var program = try P9Program(data: source)
            program.keygroups[0].softSampleName = "SAMPLE 6"
            program.keygroups[0].loudSampleName = "SAMPLE 6 2"
            let edited = try program.encoded()

            try expect(
                String(decoding: edited[(base + 0x18)..<(base + 0x22)], as: UTF8.self)
                    == "SAMPLE 6  "
            )
            try expect(
                String(decoding: edited[(base + 0x2E)..<(base + 0x38)], as: UTF8.self)
                    == "SAMPLE 6 2"
            )
            try expect(edited[base + 0x28] == 0)
            try expect(edited[base + 0x29] == 0)
            try expect(edited[base + 0x3E] == 0)
            try expect(edited[base + 0x3F] == 0)
            try expect(edited[base + 0x44] == 0x34)
            try expect(edited[base + 0x45] == 0x12)
        }

        test("P9 sample rename updates every matching layer and clears only its runtime pointer") {
            var source = makeP9Fixture(keygroupCount: 2)
            let first = P9Program.headerSize
            let second = first + P9Program.keygroupSize
            source.replaceSubrange(
                (first + 0x18)..<(first + 0x22),
                with: Data("OLD NAME  ".utf8)
            )
            source[first + 0x28] = 0x34
            source[first + 0x29] = 0x12
            source.replaceSubrange(
                (second + 0x2E)..<(second + 0x38),
                with: Data("OLD_NAME  ".utf8)
            )
            source[second + 0x3E] = 0x78
            source[second + 0x3F] = 0x56
            source[first + 0x44] = 0xBC
            source[first + 0x45] = 0x9A

            var program = try P9Program(data: source)
            let replacements = program.renameSampleReferences(
                matching: ["OLD NAME"],
                to: "NEW NAME"
            )
            let renamed = try program.encoded()

            try expect(replacements == 2)
            try expect(
                String(decoding: renamed[(first + 0x18)..<(first + 0x22)], as: UTF8.self)
                    == "NEW NAME  "
            )
            try expect(
                String(decoding: renamed[(second + 0x2E)..<(second + 0x38)], as: UTF8.self)
                    == "NEW NAME  "
            )
            try expect(renamed[first + 0x28] == 0)
            try expect(renamed[first + 0x29] == 0)
            try expect(renamed[second + 0x3E] == 0)
            try expect(renamed[second + 0x3F] == 0)
            try expect(renamed[first + 0x44] == 0xBC)
            try expect(renamed[first + 0x45] == 0x9A)
        }

        test("P9 edits touch only documented fields and retain unknown flag bits") {
            let source = makeP9Fixture(keygroupCount: 1)
            var program = try P9Program(data: source)
            program.keygroups[0].softLoudness = -12
            program.keygroups[0].softFilter = 42
            program.keygroups[0].softTuning = P9Tuning(transpose: -2, fine: 0)
            program.keygroups[0].vcfAmount = -25
            program.keygroups[0].oneShot = true
            program.keygroups[0].midiChannelOffset = 15
            program.keygroups[0].output = .right
            let edited = try program.encoded()
            let base = P9Program.headerSize
            let changed = Set(source.indices.filter { source[$0] != edited[$0] })
            try expect(changed == Set([
                base + 0x12,
                base + 0x13,
                base + 0x14,
                base + 0x17,
                base + 0x2A,
                base + 0x2B,
                base + 0x2C,
                base + 0x2D
            ]))
            try expect(edited[base + 0x12] & 0x04 == 0x04)
        }

        test("P9 bulk editing can adjust all keygroups without changing unselected fields") {
            let source = makeP9Fixture(keygroupCount: 3)
            var program = try P9Program(data: source)
            var edits = P9BulkEdits()
            edits.softTranspose = P9BulkNumberEdit(enabled: true, mode: .adjust, value: 12)
            edits.softFilter = P9BulkNumberEdit(enabled: true, mode: .set, value: 55)
            edits.envAttack = P9BulkNumberEdit(enabled: true, mode: .set, value: 7)
            edits.velocityCrossfadePoint = P9BulkNumberEdit(enabled: true, mode: .set, value: 72)
            edits.midiChannel = 16
            edits.output = .mono(8)
            edits.releaseVelocityFromNoteOn = true
            edits.customVelocityCrossfadePoint = true
            program.apply(edits, to: Set(program.keygroups.indices))
            try expect(program.keygroups.allSatisfy { $0.softTuning.transpose == 12 })
            try expect(program.keygroups.allSatisfy { $0.softFilter == 55 })
            try expect(program.keygroups.allSatisfy { $0.envelope.attack == 7 })
            try expect(program.keygroups.allSatisfy { $0.midiChannelOffset == 15 })
            try expect(program.keygroups.allSatisfy { $0.output == .mono(8) })
            try expect(program.keygroups.allSatisfy { $0.velocityCrossfadePoint == 72 })
            try expect(program.keygroups.allSatisfy(\.releaseVelocityFromNoteOn))
            try expect(program.keygroups.allSatisfy(\.customVelocityCrossfadePoint))
            try expect(program.keygroups.allSatisfy { $0.vcfEnvelope.attack == 20 })
        }

        test("P9 bulk editing assigns available sample names to every selection") {
            var program = try P9Program(data: makeP9Fixture(keygroupCount: 3))
            var edits = P9BulkEdits()
            edits.softSampleName = "CHOP-01"
            edits.loudSampleName = ""
            program.apply(edits, to: [0, 2])

            let reopened = try P9Program(data: program.encoded())
            try expect(reopened.keygroups[0].softSampleName == "CHOP-01")
            try expect(reopened.keygroups[2].softSampleName == "CHOP-01")
            try expect(reopened.keygroups[0].loudSampleName.isEmpty)
            try expect(reopened.keygroups[2].loudSampleName.isEmpty)
            try expect(reopened.keygroups[1].softSampleName == "AMEN-01")
            try expect(reopened.keygroups[1].loudSampleName == "HARD-01")
        }

        test("P9 spread maps keygroups chromatically and compensates both sample layers") {
            let source = makeP9Fixture(keygroupCount: 12)
            var program = try P9Program(data: source)
            program.keygroups[0].softTuning.fine = 7
            program.keygroups[0].loudTuning.fine = -3
            let untouched = program.keygroups[10]
            let selected = Set([9, 4, 1, 7, 0, 8, 3, 6, 2, 5])
            let settings = P9SpreadSettings(
                startNote: 60,
                rootNote: 60,
                automaticallyTranspose: true
            )

            try program.spread(settings, to: selected)

            for (offset, index) in selected.sorted().enumerated() {
                let note = 60 + offset
                try expect(program.keygroups[index].lowKey == note)
                try expect(program.keygroups[index].highKey == note)
                try expect(program.keygroups[index].softTuning.transpose == -offset)
                try expect(program.keygroups[index].loudTuning.transpose == -offset)
            }
            try expect(program.keygroups[0].softTuning.fine == 7)
            try expect(program.keygroups[0].loudTuning.fine == -3)
            try expect(program.keygroups[10] == untouched)
        }

        test("P9 spread keeps non-zero fine tuning canonical and pitch-exact") {
            var program = try P9Program(data: makeP9Fixture(keygroupCount: 2))
            program.keygroups[0].softTuning = P9Tuning(rawSixteenths: 380)
            program.keygroups[0].loudTuning = P9Tuning(rawSixteenths: 380)
            try program.spread(
                P9SpreadSettings(
                    startNote: 36,
                    rootNote: 60,
                    automaticallyTranspose: true
                ),
                to: [0, 1]
            )

            try expect(program.keygroups[0].softTuning.transpose == 24)
            try expect(program.keygroups[0].softTuning.fine == -4)
            try expect(program.keygroups[0].softTuning.rawSixteenths == 380)
            try expect(program.keygroups[1].softTuning.transpose == 23)
            try expect(program.keygroups[1].softTuning.fine == 0)
            let reopened = try P9Program(data: program.encoded())
            try expect(reopened.keygroups[0].softTuning == program.keygroups[0].softTuning)
            try expect(reopened.keygroups[0].loudTuning == program.keygroups[0].loudTuning)
        }

        test("P9 spread without automatic transpose preserves existing tuning") {
            let source = makeP9Fixture(keygroupCount: 3)
            var program = try P9Program(data: source)
            program.keygroups[0].softTuning.transpose = 8
            program.keygroups[0].loudTuning.transpose = -4
            let settings = P9SpreadSettings(
                startNote: 72,
                rootNote: 36,
                automaticallyTranspose: false
            )

            try program.spread(settings, to: [0, 1, 2])

            try expect(program.keygroups.map(\.lowKey) == [72, 73, 74])
            try expect(program.keygroups.map(\.highKey) == [72, 73, 74])
            try expect(program.keygroups[0].softTuning.transpose == 8)
            try expect(program.keygroups[0].loudTuning.transpose == -4)
        }

        test("P9 spread rejects unsafe note and transpose ranges atomically") {
            let source = makeP9Fixture(keygroupCount: 3)
            var program = try P9Program(data: source)
            let original = program

            try expectThrows {
                try program.spread(
                    P9SpreadSettings(
                        startNote: 126,
                        rootNote: 126,
                        automaticallyTranspose: true
                    ),
                    to: [0, 1, 2]
                )
            }
            try expect(program == original)

            try expectThrows {
                try program.spread(
                    P9SpreadSettings(
                        startNote: 100,
                        rootNote: 0,
                        automaticallyTranspose: true
                    ),
                    to: [0, 1, 2]
                )
            }
            try expect(program == original)
        }

        test("P9 spread survives save and reopen while touching only mapping and tuning") {
            let source = makeP9Fixture(keygroupCount: 3)
            var program = try P9Program(data: source)
            try program.spread(
                P9SpreadSettings(
                    startNote: 70,
                    rootNote: 72,
                    automaticallyTranspose: true
                ),
                to: [0, 1, 2]
            )

            let saved = try program.encoded()
            let reopened = try P9Program(data: saved)
            try expect(reopened.keygroups.map(\.lowKey) == [70, 71, 72])
            try expect(reopened.keygroups.map(\.highKey) == [70, 71, 72])
            try expect(reopened.keygroups.map(\.softTuning.transpose) == [2, 1, 0])
            try expect(reopened.keygroups.map(\.loudTuning.transpose) == [2, 1, 0])

            var expectedChanges: Set<Int> = []
            for index in 0..<3 {
                let base = P9Program.headerSize + index * P9Program.keygroupSize
                expectedChanges.insert(base + 0x00)
                expectedChanges.insert(base + 0x01)
                if index < 2 {
                    expectedChanges.insert(base + 0x2A)
                    expectedChanges.insert(base + 0x40)
                }
            }
            let changed = Set(source.indices.filter { source[$0] != saved[$0] })
            try expect(changed == expectedChanges)
        }

        test("P9 copied keygroups append, rename sample references and survive reopen") {
            var sourceProgram = try P9Program(data: makeP9Fixture(keygroupCount: 3))
            sourceProgram.keygroups[1].softSampleName = "BREAK-02"
            sourceProgram.keygroups[1].loudSampleName = "BREAK-LD"
            sourceProgram.keygroups[2].softSampleName = "BREAK-03"
            let records = try sourceProgram.keygroupRecords(at: [1, 2])

            let destinationSource = makeP9Fixture(keygroupCount: 1)
            var destination = try P9Program(data: destinationSource)
            try destination.appendKeygroups(
                records: records,
                sampleNameMapping: [
                    "BREAK-02": "BRKCPY-02",
                    "BREAK-LD": "BRKCPY-LD"
                ]
            )

            let saved = try destination.encoded()
            try expect(saved.count == P9Program.headerSize + 3 * P9Program.keygroupSize)
            try expect(saved[0x17] == 3)
            let reopened = try P9Program(data: saved)
            try expect(reopened.keygroups.count == 3)
            try expect(reopened.keygroups[1].softSampleName == "BRKCPY-02")
            try expect(reopened.keygroups[1].loudSampleName == "BRKCPY-LD")
            try expect(reopened.keygroups[2].softSampleName == "BREAK-03")
            try expect(reopened.keygroups[1].envelope == sourceProgram.keygroups[1].envelope)
            try expect(
                saved.subdata(in: 0..<P9Program.headerSize)
                    .enumerated()
                    .allSatisfy { offset, byte in
                        [0x12, 0x13, 0x17].contains(offset)
                            || byte == destinationSource[offset]
                    }
            )
            try expect(saved[0x12] == 0 && saved[0x13] == 0)
        }

        test("P9 keygroup transfer clears sampler-maintained runtime addresses only") {
            var source = makeP9Fixture(keygroupCount: 1)
            let sourceBase = P9Program.headerSize
            source[sourceBase + 0x28] = 0x40
            source[sourceBase + 0x29] = 0xD0
            source[sourceBase + 0x3E] = 0x70
            source[sourceBase + 0x3F] = 0xD1
            source[sourceBase + 0x44] = 0x96
            source[sourceBase + 0x45] = 0xC5
            source[sourceBase + 0x15] = 0x5A

            let sourceProgram = try P9Program(data: source)
            let records = try sourceProgram.keygroupRecords(at: [0])
            var destination = try P9Program(data: makeP9Fixture(keygroupCount: 1))
            try destination.appendKeygroups(records: records)

            let encoded = try destination.encoded()
            let appendedBase = P9Program.headerSize + P9Program.keygroupSize
            for addressOffset in [0x28, 0x3E, 0x44] {
                try expect(encoded[appendedBase + addressOffset] == 0)
                try expect(encoded[appendedBase + addressOffset + 1] == 0)
            }
            try expect(encoded[appendedBase + 0x15] == 0x5A)
            try expect(
                encoded[appendedBase + 0x18..<appendedBase + 0x22]
                    == source[sourceBase + 0x18..<sourceBase + 0x22]
            )
        }

        test("P9 copied header creates a safe in-memory zero-keygroup destination") {
            var source = makeP9Fixture(keygroupCount: 2)
            source[0x12] = 0x34
            source[0x13] = 0xD2
            let sourceProgram = try P9Program(data: source)

            let template = try sourceProgram.destinationHeaderTemplate()
            try expect(template.count == P9Program.headerSize)
            try expect(template[0x12] == 0)
            try expect(template[0x13] == 0)
            try expect(template[0x17] == 0)
            try expect(
                template.indices.allSatisfy { index in
                    [0x12, 0x13, 0x17].contains(index)
                        || template[index] == source[index]
                }
            )

            var destination = try P9Program(data: template)
            try expect(destination.keygroups.isEmpty)
            destination.name = "NEWBREAK"
            let record = try sourceProgram.keygroupRecords(at: [0])[0]
            try destination.appendKeygroups(records: [record])
            let saved = try destination.encoded()
            let reopened = try P9Program(data: saved)
            try expect(reopened.name == "NEWBREAK")
            try expect(reopened.keygroups.count == 1)
            try expect(saved[0x12] == 0 && saved[0x13] == 0)
            try expect(saved[0x17] == 1)
        }

        test("P9 keygroup paste rejects malformed records and the hardware count limit") {
            var destination = try P9Program(data: makeP9Fixture(keygroupCount: 1))
            let original = destination
            try expectThrows {
                try destination.appendKeygroups(records: [Data(repeating: 0, count: 69)])
            }
            try expect(destination == original)

            var full = try P9Program(data: makeP9Fixture(keygroupCount: 99))
            let record = try destination.keygroupRecords(at: [0])[0]
            try expectThrows {
                try full.appendKeygroups(records: [record])
            }
        }

        test("blank P9 has one safe editable keygroup and survives reopen") {
            var program = try P9Program.blank(named: "NEWBREAK")
            try expect(program.name == "NEWBREAK")
            try expect(program.keygroups.count == 1)
            try expect(program.keygroups[0].id == 0)
            try expect(program.keygroups[0].lowKey == 0)
            try expect(program.keygroups[0].highKey == 127)
            try expect(program.keygroups[0].softSampleName.isEmpty)
            try expect(program.keygroups[0].loudSampleName.isEmpty)
            try expect(program.keygroups[0].output == .all)

            program.keygroups[0].softSampleName = "AMEN"
            program.keygroups[0].lowKey = 60
            program.keygroups[0].highKey = 60
            let saved = try program.encoded()
            try expect(saved.count == P9Program.headerSize + P9Program.keygroupSize)
            try expect(saved[0x12] == 0 && saved[0x13] == 0)
            try expect(saved[0x16] == 0xFF)
            try expect(saved[0x17] == 1)
            try expect(saved[0x1B] == 0xFF)
            let recordBase = P9Program.headerSize
            for addressOffset in [0x28, 0x3E, 0x44] {
                try expect(saved[recordBase + addressOffset] == 0)
                try expect(saved[recordBase + addressOffset + 1] == 0)
            }

            let reopened = try P9Program(data: saved)
            try expect(reopened.name == "NEWBREAK")
            try expect(reopened.keygroups[0].softSampleName == "AMEN")
            try expect(reopened.keygroups[0].lowKey == 60)
            try expect(reopened.keygroups[0].highKey == 60)
        }

        test("P9 keygroups can be duplicated and deleted without shifting record bytes") {
            var source = makeP9Fixture(keygroupCount: 3)
            source[0x12] = 0x34
            source[0x13] = 0xD2
            let firstBase = P9Program.headerSize
            source[firstBase + 0x15] = 0x6B
            var program = try P9Program(data: source)
            program.keygroups[0].softSampleName = "EDITED"
            let appendedIndex = try program.appendKeygroup(copying: 0)
            try expect(appendedIndex == 3)
            try expect(program.keygroups[3].softSampleName == "EDITED")
            try program.deleteKeygroups(at: [0, 2])
            try expect(program.keygroups.map(\.id) == [0, 1])

            let saved = try program.encoded()
            let reopened = try P9Program(data: saved)
            try expect(saved[0x12] == 0 && saved[0x13] == 0)
            try expect(reopened.keygroups.count == 2)
            try expect(reopened.keygroups.map(\.id) == [0, 1])
            try expect(reopened.keygroups[0].lowKey == 61)
            try expect(reopened.keygroups[1].softSampleName == "EDITED")
            for remainingIndex in 0..<2 {
                let base = P9Program.headerSize
                    + remainingIndex * P9Program.keygroupSize
                for addressOffset in [0x28, 0x3E, 0x44] {
                    try expect(saved[base + addressOffset] == 0)
                    try expect(saved[base + addressOffset + 1] == 0)
                }
            }
            let copiedBase = P9Program.headerSize + P9Program.keygroupSize
            try expect(saved[copiedBase + 0x15] == 0x6B)
            try expectThrows {
                try program.deleteKeygroups(at: [0, 1])
            }
        }

        test("typed bulk loudness survives Apply, save and reopen for every keygroup") {
            try expect(P9NumericInput.boundedValue("-12", range: -50...50) == -12)
            try expect(P9NumericInput.boundedValue("99", range: -50...50) == 50)
            try expect(P9NumericInput.boundedValue("-", range: -50...50) == nil)
            try expect(
                P9NumericInput.draggedValue(
                    from: 20,
                    verticalTranslation: -10,
                    range: 0...99
                ) == 25
            )
            try expect(
                P9NumericInput.draggedValue(
                    from: 20,
                    verticalTranslation: 10,
                    range: 0...99
                ) == 15
            )
            try expect(
                P9NumericInput.draggedValue(
                    from: 98,
                    verticalTranslation: -20,
                    range: 0...99
                ) == 99
            )

            let source = makeP9Fixture(keygroupCount: 40)
            var program = try P9Program(data: source)
            var edits = P9BulkEdits()
            edits.softLoudness = P9BulkNumberEdit(enabled: true, mode: .set, value: -12)
            program.apply(edits, to: Set(program.keygroups.indices))

            let saved = try program.encoded()
            let reopened = try P9Program(data: saved)
            try expect(reopened.keygroups.allSatisfy { $0.softLoudness == -12 })

            let changed = Set(source.indices.filter { source[$0] != saved[$0] })
            let expected = Set((0..<40).map {
                P9Program.headerSize + $0 * P9Program.keygroupSize + 0x2D
            })
            try expect(changed == expected)
        }

        test("P9 validation rejects truncated and inconsistent programs") {
            try expectThrows { _ = try P9Program(data: Data(repeating: 0, count: 12)) }
            var inconsistent = makeP9Fixture(keygroupCount: 1)
            inconsistent[0x17] = 2
            try expectThrows { _ = try P9Program(data: inconsistent) }
        }

        test("recursive parser creates volume paths") {
            let volumes = AkaiOutputParser.parseVolumes(try fixture("dirrec.txt"))
            try expect(volumes.map(\.path) == ["/disk0/A/VOLUME 001", "/disk0/A/DRUM SET"])
        }

        test("multiple deletion is unique and descending") {
            try expect(AkaiCommandBuilder.deletionOrder([3, 12, 3, 1, 64]) == [64, 12, 3, 1])
        }

        test("filename sanitization honors S950 limits and unique suffixes") {
            let s900 = AkaiFilename.sanitizedBase("Béat #One!.WAV", family: .s900)
            try expect(s900 == "BEAT__ONE")
            try expect(s900.count <= 10)
            let unique = AkaiFilename.uniqueName(
                base: "LONGSAMPLE",
                existing: ["LONGSAMPLE", "LONGSAM_2"],
                maximumLength: 10
            )
            try expect(unique.count <= 10)
            try expect(unique == "LONGSAMP_2")
            let validatedName = try AkaiFilename.validatedS950Base(
                " kick-01 "
            )
            try expect(validatedName == "KICK-01")
            try expect(
                AkaiFilename.s950BaseValidationError("TOO-LONG-NAME")
                    != nil
            )
            try expect(
                AkaiFilename.s950BaseValidationError("BAD NAME") != nil
            )
            try expect(
                AkaiFilename.s950BaseValidationError("_BAD_") != nil
            )
        }

        test("USB owner resolution never guesses partial names") {
            let exact = USBVolumeResolver.owningVolume(for: URL(fileURLWithPath: "/Volumes/AKAI USB/disk.img"))
            try expect(exact?.path == "/Volumes/AKAI USB")
            try expect(USBVolumeResolver.owningVolume(for: URL(fileURLWithPath: "/tmp/Volumes/AKAI/disk.img")) == nil)
        }

        test("copy destination requires an existing exact filename") {
            let workspace = try temporaryDirectory("copy-destination")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let volumeA = workspace.appendingPathComponent("USB-A", isDirectory: true)
            let volumeB = workspace.appendingPathComponent("USB-B", isDirectory: true)
            try FileManager.default.createDirectory(at: volumeA, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: volumeB, withIntermediateDirectories: true)
            let source = workspace.appendingPathComponent("local/DRUMS.img")
            try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("source".utf8).write(to: source)
            try Data("old".utf8).write(to: volumeB.appendingPathComponent("DRUMS.img"))
            let result = USBVolumeResolver.exactCopyDestination(source: source, mountedVolumes: [volumeA, volumeB])
            try expect(result == volumeB.appendingPathComponent("DRUMS.img"))
        }

        test("only S950 format presets and commands are exposed") {
            try expect(AkaiFamily.allCases == [.s900])
            try expect(
                FormatPreset.allCases
                    == [.s900Low, .s900High, .s900Hard32]
            )
            try expect(FormatPreset.s900Low.byteCount == 800 * 1024)
            try expect(FormatPreset.s900High.byteCount == 1600 * 1024)
            try expect(FormatPreset.s900Hard32.byteCount == 32 * 1024 * 1024)
            try expect(FormatPreset.s900Low.command == "formatfloppyl9")
            try expect(FormatPreset.s900High.command == "formatfloppyh9")
            try expect(FormatPreset.s900Hard32.command == "formatharddisk9 32M")
            try expect(!FormatPreset.s900Low.requiresInitialVolume)
            try expect(FormatPreset.s900Hard32.requiresInitialVolume)
            try expect(FormatPreset.allCases.allSatisfy {
                $0.command.hasSuffix("9") || $0.command.contains("disk9 ")
            })
        }

        test("operation progress is clamped to a valid UI range") {
            let over = OperationProgress(kind: .refreshing, current: 4, total: 1, detail: "Done")
            let under = OperationProgress(kind: .refreshing, current: -1, total: 4, detail: "Starting")
            try expect(over.fraction == 1)
            try expect(under.fraction == 0)
        }

        test("WAV compatibility detects float stereo and repairs to mono PCM16") {
            let workspace = try temporaryDirectory("wav")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let source = workspace.appendingPathComponent("Float Stereo.wav")
            try writeFloatStereoWAV(to: source)
            let options = ImportOptions(family: .s900, compressedS900: false, convertToMono: true, preserveSampleRate: true)
            let inspection = try WAVService.inspect(source, options: options)
            try expect(inspection.needsRepair)
            try expect(inspection.repairReasons.contains { $0.contains("mono") })

            let repaired = workspace.appendingPathComponent("CANONICAL.wav")
            try WAVService.canonicalCopy(of: source, to: repaired, options: options)
            let repairedInspection = try WAVService.inspect(repaired, options: options)
            try expect(repairedInspection.channelCount == 1)
            try expect(repairedInspection.bitDepth == 16)
            try expect(repairedInspection.isLinearPCM)
        }

        test("verified image copy atomically replaces exact destination") {
            let workspace = try temporaryDirectory("verified-copy")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let source = workspace.appendingPathComponent("source.img")
            let destination = workspace.appendingPathComponent("destination.img")
            let bytes = Data((0..<32_768).map { UInt8($0 % 251) })
            try bytes.write(to: source)
            try Data("old".utf8).write(to: destination)
            try ImageFileOperations.copyAtomicallyAndVerify(source: source, destination: destination)
            let copied = try Data(contentsOf: destination)
            try expect(copied == bytes)
        }

        test("timestamped destructive backup is a byte-exact verified image copy") {
            let workspace = try temporaryDirectory("verified-backup")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let source = workspace.appendingPathComponent("COLLECTION.img")
            let bytes = Data((0..<65_536).map { UInt8(($0 * 7) % 253) })
            try bytes.write(to: source)
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            let backup = try ImageFileOperations.timestampedBackup(
                of: source,
                now: date
            )
            try expect(backup.lastPathComponent == "COLLECTION-backup-2023-11-14-221320.img")
            let backupBytes = try Data(contentsOf: backup)
            let sourceBytes = try Data(contentsOf: source)
            try expect(backupBytes == bytes)
            try expect(sourceBytes == bytes)

            let backupDirectory = workspace.appendingPathComponent(
                "central-backups",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true
            )
            let centralBackup = try ImageFileOperations.timestampedBackup(
                of: source,
                destinationDirectory: backupDirectory,
                now: date
            )
            try expect(
                centralBackup.deletingLastPathComponent().standardizedFileURL
                    == backupDirectory.standardizedFileURL
            )
            let centralBackupBytes = try Data(contentsOf: centralBackup)
            try expect(centralBackupBytes == bytes)
        }

        test("IMG modification date can be updated after a successful mutation") {
            let workspace = try temporaryDirectory("modified-date")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let image = workspace.appendingPathComponent("TEST.img")
            try Data(repeating: 0, count: 1024).write(to: image)
            let expected = Date(timeIntervalSince1970: 1_800_000_000)
            try ImageFileOperations.updateModificationDate(
                of: image,
                to: expected
            )
            let actual = try image.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            try expect(actual == expected)
        }

        test("backing up a backup-derived IMG does not chain timestamp suffixes") {
            let workspace = try temporaryDirectory("backup-name-normalization")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let source = workspace.appendingPathComponent(
                "MARYBRK copy-backup-2026-08-02-152650-backup-2026-08-02-153000-2.img"
            )
            let bytes = Data((0..<8_192).map { UInt8($0 % 241) })
            try bytes.write(to: source)
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            let first = try ImageFileOperations.timestampedBackup(
                of: source,
                now: date
            )
            try expect(
                first.lastPathComponent
                    == "MARYBRK copy-backup-2023-11-14-221320.img"
            )
            let second = try ImageFileOperations.timestampedBackup(
                of: source,
                now: date
            )
            try expect(
                second.lastPathComponent
                    == "MARYBRK copy-backup-2023-11-14-221320-2.img"
            )
            let firstBytes = try Data(contentsOf: first)
            let secondBytes = try Data(contentsOf: second)
            try expect(firstBytes == bytes)
            try expect(secondBytes == bytes)
        }

        test("built-in removable-media cleanup rules match FIND950") {
            try expect(RemovableMediaCleanupPolicy.defaultNames == [
                ".DS_Store", "._*", "._AppleDouble", ".AppleDouble", ".fseventsd",
                ".VolumeIcon.icns", ".TemporaryItems",
                ".DocumentRevisions-V100", ".Spotlight-V100", ".Trashes",
                ".localized", ".AppleDB", ".apdisk", "Thumbs.db",
                "Desktop.ini", ".syncing_db", ".Trash",
                ".metadata_never_index", ".bzvol", ".dbxignore",
                "System Volume Information", "$RECYCLE.BIN", "RECYCLED"
            ])
            try expect(
                RemovableMediaCleanupPolicy().activeNames.count
                    == RemovableMediaCleanupPolicy.defaultNames.count
            )
        }

        test("safe eject cleanup removes only configured metadata names") {
            let root = try temporaryDirectory("removable-cleanup")
            defer { try? FileManager.default.removeItem(at: root) }
            let samples = root.appendingPathComponent("Samples", isDirectory: true)
            try FileManager.default.createDirectory(
                at: samples,
                withIntermediateDirectories: true
            )
            let rootMetadata = root.appendingPathComponent(".DS_Store")
            let nestedMetadata = samples.appendingPathComponent("Thumbs.db")
            let keptMetadata = samples.appendingPathComponent("Desktop.ini")
            let custom = samples.appendingPathComponent("SAMPLER.CACHE")
            let appleDouble = samples.appendingPathComponent("._beat-disk.img")
            let similarlyNamed = samples.appendingPathComponent("Thumbs.db.backup")
            for url in [
                rootMetadata,
                nestedMetadata,
                keptMetadata,
                custom,
                appleDouble,
                similarlyNamed
            ] {
                try Data([0x01]).write(to: url)
            }

            var policy = RemovableMediaCleanupPolicy()
            try policy.addCustomName("SAMPLER.CACHE")
            try policy.addException("Samples/Desktop.ini")
            let candidates = try RemovableMediaCleaner.candidates(
                on: root,
                policy: policy
            )
            try expect(Set(candidates.map(\.relativePath)) == [
                ".DS_Store",
                "Samples/Thumbs.db",
                "Samples/SAMPLER.CACHE",
                "Samples/._beat-disk.img"
            ])
            let result = try RemovableMediaCleaner.remove(
                candidates,
                from: root
            )
            try expect(result.failures.isEmpty)
            try expect(Set(result.removedPaths) == Set(candidates.map(\.relativePath)))
            try expect(!FileManager.default.fileExists(atPath: rootMetadata.path))
            try expect(!FileManager.default.fileExists(atPath: nestedMetadata.path))
            try expect(!FileManager.default.fileExists(atPath: custom.path))
            try expect(!FileManager.default.fileExists(atPath: appleDouble.path))
            try expect(FileManager.default.fileExists(atPath: keptMetadata.path))
            try expect(FileManager.default.fileExists(atPath: similarlyNamed.path))
            let remaining = try RemovableMediaCleaner.candidates(
                on: root,
                policy: policy
            )
            try expect(remaining.isEmpty)
        }

        test("incomplete cleanup inspection directs the user to Full Disk Access") {
            let description = RemovableMediaCleanupError
                .enumerationFailed("/Volumes/AKAI/.Spotlight-V100")
                .errorDescription ?? ""
            try expect(description.contains("Full Disk Access"))
        }

        test("cleanup exceptions preserve matching parent directories") {
            let root = try temporaryDirectory("removable-cleanup-exception")
            defer { try? FileManager.default.removeItem(at: root) }
            let trash = root.appendingPathComponent(".Trashes", isDirectory: true)
            let kept = trash.appendingPathComponent("Keep Me.txt")
            try FileManager.default.createDirectory(
                at: trash,
                withIntermediateDirectories: true
            )
            try Data([0x01]).write(to: kept)

            var policy = RemovableMediaCleanupPolicy()
            try policy.addException(".Trashes/Keep Me.txt")
            let candidates = try RemovableMediaCleaner.candidates(
                on: root,
                policy: policy
            )
            try expect(!candidates.contains { $0.relativePath == ".Trashes" })
            try expect(FileManager.default.fileExists(atPath: kept.path))
        }

        test("partial metadata cleanup reports failures and keeps successful removals") {
            let root = try temporaryDirectory("removable-cleanup-partial")
            let outside = root.deletingLastPathComponent().appendingPathComponent(
                "outside-cleanup-\(UUID().uuidString)"
            )
            defer {
                try? FileManager.default.removeItem(at: root)
                try? FileManager.default.removeItem(at: outside)
            }
            try Data([0x01]).write(to: outside)
            let removable = root.appendingPathComponent(".DS_Store")
            try Data([0x01]).write(to: removable)
            let candidates = [
                RemovableMediaCleanupCandidate(
                    url: outside,
                    relativePath: ".Spotlight-V100",
                    isDirectory: true
                ),
                RemovableMediaCleanupCandidate(
                    url: removable,
                    relativePath: ".DS_Store",
                    isDirectory: false
                )
            ]

            let result = try RemovableMediaCleaner.remove(
                candidates,
                from: root
            )
            try expect(result.removedPaths == [".DS_Store"])
            try expect(result.failures.map(\.relativePath) == [
                ".Spotlight-V100"
            ])
            try expect(!FileManager.default.fileExists(atPath: removable.path))
            try expect(FileManager.default.fileExists(atPath: outside.path))
        }

        await asyncTest("eject completion waits for the volume to be unmounted") {
            let missingVolume = FileManager.default.temporaryDirectory
                .appendingPathComponent("already-unmounted-\(UUID().uuidString)")
            try await ImageFileOperations.waitUntilUnmounted(
                volume: missingVolume,
                timeout: 0.01,
                pollIntervalNanoseconds: 1_000_000
            )

            let mounted = try temporaryDirectory("mounted-volume")
            defer { try? FileManager.default.removeItem(at: mounted) }
            do {
                try await ImageFileOperations.waitUntilUnmounted(
                    volume: mounted,
                    timeout: 0,
                    pollIntervalNanoseconds: 1_000_000
                )
                throw TestFailure.expectedThrow
            } catch TestFailure.expectedThrow {
                throw TestFailure.expectedThrow
            } catch {
                try expect(error.localizedDescription.contains("still mounted"))
            }
        }

        await asyncTest("serialized controller reaches ready, runs a command, then quits") {
            let workspace = try temporaryDirectory("controller")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let image = workspace.appendingPathComponent("test.img")
            try Data(repeating: 0, count: 8_192).write(to: image)
            let fake = root.appendingPathComponent("Tests/Fixtures/fake-akaiutil.sh")
            let controller = AkaiCommandController()
            _ = try await controller.open(imageURL: image, executableURL: fake, readOnly: false)
            let openState = await controller.state
            try expect(openState == .ready)
            let result = try await controller.send("df")
            try expect(result.output.contains("FLL"))
            let commandState = await controller.state
            try expect(commandState == .ready)
            await controller.close()
            let closedState = await controller.state
            try expect(closedState == .closed)
        }

        await asyncTest("read-only controller permits native and WAV exports only") {
            let workspace = try temporaryDirectory("read-only-controller")
            defer { try? FileManager.default.removeItem(at: workspace) }
            let image = workspace.appendingPathComponent("test.img")
            try Data(repeating: 0, count: 8_192).write(to: image)
            let fake = root.appendingPathComponent(
                "Tests/Fixtures/fake-akaiutil.sh"
            )
            let controller = AkaiCommandController()
            _ = try await controller.open(
                imageURL: image,
                executableURL: fake,
                readOnly: true
            )
            _ = try await controller.send("geti 1")
            _ = try await controller.send("sample2wavi 1")
            do {
                _ = try await controller.send("put TEST.S9")
                throw TestFailure.expectedThrow
            } catch AppError.readOnly {
                // Expected: export-only commands are allowed, import is not.
            }
            await controller.close()
            let closedState = await controller.state
            try expect(closedState == .closed)
        }

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }

    private static func test(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            passed += 1
            print("✓ \(name)")
        } catch {
            failed += 1
            print("✗ \(name): \(error)")
        }
    }

    private static func asyncTest(_ name: String, _ body: () async throws -> Void) async {
        do {
            try await body()
            passed += 1
            print("✓ \(name)")
        } catch {
            failed += 1
            print("✗ \(name): \(error)")
        }
    }

    private static func fixture(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Tests/Fixtures/\(name)"), encoding: .utf8)
    }

    private static func expect(_ condition: @autoclosure () -> Bool) throws {
        if !condition() { throw TestFailure.expectation }
    }

    private static func expectThrows(_ body: () throws -> Void) throws {
        do {
            try body()
            throw TestFailure.expectedThrow
        } catch TestFailure.expectedThrow {
            throw TestFailure.expectedThrow
        } catch {}
    }

    private static func temporaryDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("akai-tests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writeFloatStereoWAV(to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410)
        else { throw TestFailure.fixture }
        buffer.frameLength = 4_410
        for channel in 0..<2 {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(buffer.frameLength) {
                samples[frame] = sin(Float(frame) * 0.04) * 0.25
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private static func makeS9Fixture(
        sampleLength: UInt32,
        nominalPitchSixteenths: UInt16
    ) -> Data {
        var data = Data(repeating: 0xA5, count: 128)
        data.replaceSubrange(0..<10, with: Data("SAMPLE    ".utf8))
        writeLittleEndian(sampleLength, to: &data, at: 0x10)
        writeLittleEndian(UInt16(25_000), to: &data, at: 0x14)
        writeLittleEndian(nominalPitchSixteenths, to: &data, at: 0x16)
        data[0x1A] = S9PlaybackMode.oneShot.rawValue
        writeLittleEndian(sampleLength, to: &data, at: 0x1C)
        writeLittleEndian(UInt32(0), to: &data, at: 0x20)
        writeLittleEndian(UInt32(0), to: &data, at: 0x24)
        data[0x2B] = S9PlaybackDirection.normal.rawValue
        return data
    }

    private static func makeMarkerWAV(
        cueSampleOffsets: [UInt32],
        s9Header: Data
    ) -> Data {
        var body = Data("WAVE".utf8)
        var format = Data()
        writeLittleEndian(UInt16(1), to: &format)
        writeLittleEndian(UInt16(1), to: &format)
        writeLittleEndian(UInt32(48_000), to: &format)
        writeLittleEndian(UInt32(96_000), to: &format)
        writeLittleEndian(UInt16(2), to: &format)
        writeLittleEndian(UInt16(16), to: &format)
        appendRIFFChunk("fmt ", payload: format, to: &body)
        appendRIFFChunk("data", payload: Data(repeating: 0, count: 8), to: &body)

        var cue = Data()
        writeLittleEndian(UInt32(cueSampleOffsets.count), to: &cue)
        for (index, sampleOffset) in cueSampleOffsets.enumerated() {
            writeLittleEndian(UInt32(index + 1), to: &cue)
            writeLittleEndian(sampleOffset, to: &cue)
            cue.append(Data("data".utf8))
            writeLittleEndian(UInt32(0), to: &cue)
            writeLittleEndian(UInt32(0), to: &cue)
            writeLittleEndian(sampleOffset, to: &cue)
        }
        appendRIFFChunk("cue ", payload: cue, to: &body)
        appendRIFFChunk("S9H ", payload: s9Header, to: &body)

        var wav = Data("RIFF".utf8)
        writeLittleEndian(UInt32(body.count), to: &wav)
        wav.append(body)
        return wav
    }

    private static func appendRIFFChunk(
        _ identifier: String,
        payload: Data,
        to data: inout Data
    ) {
        data.append(Data(identifier.utf8))
        writeLittleEndian(UInt32(payload.count), to: &data)
        data.append(payload)
        if !payload.count.isMultiple(of: 2) { data.append(0) }
    }

    private static func writeLittleEndian(
        _ value: UInt16,
        to data: inout Data,
        at offset: Int? = nil
    ) {
        let bytes = Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF)
        ])
        if let offset {
            data.replaceSubrange(offset..<(offset + 2), with: bytes)
        } else {
            data.append(bytes)
        }
    }

    private static func writeLittleEndian(
        _ value: UInt32,
        to data: inout Data,
        at offset: Int? = nil
    ) {
        let bytes = Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
        if let offset {
            data.replaceSubrange(offset..<(offset + 4), with: bytes)
        } else {
            data.append(bytes)
        }
    }

    private static func makeP9Fixture(keygroupCount: Int) -> Data {
        var data = Data(
            repeating: 0xA5,
            count: P9Program.headerSize + keygroupCount * P9Program.keygroupSize
        )
        let name = Array("JUNGLE    ".utf8)
        data.replaceSubrange(0x00..<0x0A, with: name)
        data[0x15] = 0
        data[0x17] = UInt8(keygroupCount)

        for index in 0..<keygroupCount {
            let base = P9Program.headerSize + index * P9Program.keygroupSize
            data[base + 0x00] = UInt8(60 + index)
            data[base + 0x01] = UInt8(60 + index)
            data[base + 0x02] = 128
            data[base + 0x03] = 0
            data[base + 0x04] = 80
            data[base + 0x05] = 99
            data[base + 0x06] = 30
            data[base + 0x07] = 31
            data[base + 0x08] = 52
            data[base + 0x09] = 13
            data[base + 0x0A] = UInt8(bitPattern: Int8(-7))
            data[base + 0x0B] = 47
            data[base + 0x12] = 0x04
            data[base + 0x13] = 0xFF
            data[base + 0x14] = 0
            data[base + 0x17] = 0
            data.replaceSubrange(
                (base + 0x18)..<(base + 0x22),
                with: Array("AMEN-01   ".utf8)
            )
            data[base + 0x22] = 20
            data[base + 0x23] = 20
            data[base + 0x24] = 20
            data[base + 0x25] = 20
            data[base + 0x26] = 64
            data[base + 0x27] = 0x5A
            data[base + 0x2A] = 0
            data[base + 0x2B] = 0
            data[base + 0x2C] = 99
            data[base + 0x2D] = 0
            data.replaceSubrange(
                (base + 0x2E)..<(base + 0x38),
                with: Array("HARD-01   ".utf8)
            )
            data[base + 0x40] = 0
            data[base + 0x41] = 0
            data[base + 0x42] = 99
            data[base + 0x43] = 0
        }
        return data
    }
}

enum TestFailure: Error {
    case expectation
    case expectedThrow
    case fixture
}
