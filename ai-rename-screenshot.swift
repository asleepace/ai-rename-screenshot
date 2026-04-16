//  @file ai-screenshot-analyzer.swift
//  @description automatically rename screenshots with ai.
//  @created on April 15th, 2026
//  @author asleepace
//
//  Requirements:
//      Make sure to have an api key stored in your keychain access,
//      to do so run the following bash with your api key:
//
//          security add-generic-password -a "$USER" -s "CLAUDE_API_KEY" -w "sk-ant-..."
//
//      or you can include directly in the code below:
//
//          let apiKey = "sk-ant-..."
//          request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
//
//  How this works:
//      1. Watches for new files on ~/Desktop
//      2. Filter all files names "Screenshot*" ending with ".png"
//      3. Compress image and upload to Claude for annotation
//      4. Rename local file with response
//
//  To compile this program:
//      xcrun swiftc <full_path_to_this_file> -o ai-screenshot-analyzer
//  
//  To run this program:
//      ./ai-screenshot-analyzer
//
//  To add this program to launchctl:
/* 

cat > ~/Library/LaunchAgents/com.asleepace.ai-screenshot-analyzer.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.asleepace.ai-screenshot-analyzer</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/asleepace/swift-scripts/ai-screenshot-analyzer</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/ai-screenshot-analyzer.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ai-screenshot-analyzer.log</string>
</dict>
</plist>
EOF

*/  
//
//  To load it:
//      launchctl load ~/Library/LaunchAgents/com.asleepace.ai-screenshot-analyzer.plist
//
//  Useful commands:
//      launchctl unload ~/Library/LaunchAgents/com.asleepace.ai-screenshot-analyzer.plist  # stop
//      launchctl load ~/Library/LaunchAgents/com.asleepace.ai-screenshot-analyzer.plist    # start
//      tail -f /tmp/ai-screenshot-analyzer.log  
//              
import AppKit
import CoreServices
import Foundation

// MARK: - Configuration (editable)

let anthropicModel: String = "claude-haiku-4-5"
let folderName: String = "Desktop"
let maxProcessed: Int = 50
let delayInSeconds: UInt64 = 1
let systemPrompt: String = """
Create descriptive title for screenshot in 2-6 words, lowercase, hyphen-separated. Return only the filename with no extension. Example: safari-github-pull-request
"""

func isScreenshot(_ filename: String) -> Bool {
    filename.hasPrefix("Screenshot") && filename.hasSuffix(".png")
}

// MARK: - Internal State

var processed = Set<String>()

func hasNotProcessed(_ path: String) -> Bool {
    if processed.contains(path) { return false }
    processed.insert(path)
    if processed.count > maxProcessed {
        processed.removeFirst()
    }
    return true
}

// MARK: - Keychain

func getSecret(_ name: String) -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    task.arguments = ["find-generic-password", "-a", NSUserName(), "-s", "\(name)", "-w"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    try? task.run()
    task.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Image Compression

func compressImage(_ path: String, maxDimension: CGFloat = 1024, quality: CGFloat = 0.7) -> Data? {
    guard let image = NSImage(contentsOfFile: path) else { return nil }

    let originalSize = image.size
    let scale = min(maxDimension / originalSize.width, maxDimension / originalSize.height, 1.0)
    let newSize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)

    let resized = NSImage(size: newSize)
    resized.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: newSize))
    resized.unlockFocus()

    guard let tiff = resized.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    else { return nil }

    return jpeg
}

// MARK: - Claude API

func renameScreenshot(_ path: String) async {
    // add 0.5s delay before compressing image to let system store file
    try? await Task.sleep(nanoseconds: delayInSeconds * 1_000_000_000)

    guard let apiKey = getSecret("CLAUDE_API_KEY"), !apiKey.isEmpty else {
        print("❌ CLAUDE_API_KEY not found in keychain")
        return
    }

    guard let imageData = compressImage(path) else {
        print("❌ Could not compress image: \(path)")
        return
    }

    print("📦 Compressed to \(imageData.count / 1024)KB")

    let base64 = imageData.base64EncodedString()
    let dir = URL(fileURLWithPath: path).deletingLastPathComponent().path

    let payload: [String: Any] = [
        "model": anthropicModel,
        "max_tokens": 64,
        "messages": [[
            "role": "user",
            "content": [
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": base64
                    ]
                ],
                [
                    "type": "text",
                    "text": "\(systemPrompt)"
                ]
            ]
        ]]
    ]

    guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
        print("❌ Failed to serialize payload")
        return
    }

    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.setValue("application/json", forHTTPHeaderField: "content-type")

    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = (json["content"] as? [[String: Any]])?.first,
            let text = content["text"] as? String
        else {
            print("❌ Failed to parse response")
            return
        }

        let newName = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        guard !newName.isEmpty else {
            print("❌ Empty filename returned")
            return
        }

        var newPath = "\(dir)/\(newName).png"

        // prevent naming collisions:
        if FileManager.default.fileExists(atPath: newPath) {
            newPath = "\(dir)/\(newName)-\(Int(Date().timeIntervalSince1970)).png"
        }
        
        // save output file:
        try FileManager.default.moveItem(atPath: path, toPath: newPath)
        print("✓ Renamed to: \(newName).png")
    } catch {
        print("❌ Error: \(error)")
    }
}

// MARK: - FSEvents

let desktopURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(folderName)

let queue = DispatchQueue(label: "com.asleepace.ai-screenshot-analyzer")

// NOTE: This is the callback that is triggered each time the Desktop is updated.
let callback: FSEventStreamCallback = { _, _, numEvents, eventPaths, eventFlags, _ in
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
    let flags = UnsafeBufferPointer(start: eventFlags, count: numEvents)

    for (path, flag) in zip(paths, flags) {
        // extract filename from path
        let filename = URL(fileURLWithPath: path).lastPathComponent

        print("Event: \(filename) flags: \(flag)")  // see what's coming in

        // only trigger for newly created files
        guard flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0 else { continue }

        // Note sometimes the file is saved as a tmp file, so handle those differently:
        if filename.hasPrefix(".") && isScreenshot(String(filename.dropFirst())) {
            let finalFilename = String(filename.dropFirst())
            let finalPath = URL(fileURLWithPath: path)
                .deletingLastPathComponent()
                .appendingPathComponent(finalFilename)
                .path
            guard hasNotProcessed(finalPath) else { continue }
            print("📸 Detected incoming screenshot: \(filename)")
            Task {
                try? await Task.sleep(nanoseconds: delayInSeconds * 1_000_000_000)
                await renameScreenshot(finalPath)
            }
            continue
        }

        // Pattern match file here:
        guard isScreenshot(filename) else { continue }
        guard hasNotProcessed(path) else { continue }

        print("📸 New screenshot: \(filename)")
        Task { await renameScreenshot(path) }
    }
}

var context = FSEventStreamContext()
let stream = FSEventStreamCreate(
    nil, callback, &context,
    [desktopURL.path] as CFArray,
    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
    0.5,
    FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
)!

FSEventStreamSetDispatchQueue(stream, queue)
FSEventStreamStart(stream)

print("👀 Watching for screenshots on Desktop...")
dispatchMain()
