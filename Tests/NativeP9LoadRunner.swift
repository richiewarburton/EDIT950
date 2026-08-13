import Foundation

@main
struct NativeP9LoadRunner {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: NativeP9LoadRunner <export-directory>\n", stderr)
            exit(2)
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.caseInsensitiveCompare("P9") == .orderedSame }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var keygroupCount = 0
        for file in files {
            let data = try Data(contentsOf: file)
            let program = try P9Program(data: data)
            guard try program.encoded() == data else {
                throw NSError(
                    domain: "NativeP9LoadRunner",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "P9 loader changed \(file.lastPathComponent)"]
                )
            }
            keygroupCount += program.keygroups.count
        }
        print("loaded \(files.count) P9 programs containing \(keygroupCount) keygroups")
    }
}
