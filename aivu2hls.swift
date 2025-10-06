#!/usr/bin/env swift

import Foundation

struct Config {
    let inputURL: URL
    let outputDirectory: URL
    let streamName: String
    let aimeURL: URL?
    let segmentDuration: Double
    let bitrates: [Int]
    let layout: String
    let videoRange: String
    let contentType: String
}

struct PlaylistMetadata {
    let resolution: String?
    let frameRate: String?
    let codecs: String?
    let averageBitrate: Int?
    let peakBitrate: Int?
}

enum CLIError: Error, CustomStringConvertible {
    case missingValue(flag: String)
    case missingRequired(String)
    case invalidNumber(flag: String, value: String)
    case fileNotFound(String)
    case directoryCreationFailed(String)

    var description: String {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .missingRequired(let name):
            return "Missing required argument: \(name)."
        case .invalidNumber(let flag, let value):
            return "Invalid numeric value for \(flag): \(value)."
        case .fileNotFound(let path):
            return "File not found at path: \(path)."
        case .directoryCreationFailed(let path):
            return "Unable to create output directory at \(path)."
        }
    }
}

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

@discardableResult
func runProcess(path: String, arguments: [String], printCommand: Bool = true) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    if printCommand {
        let joined = ([path] + arguments).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        print("→ \(joined)")
    }

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
    let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

    if process.terminationStatus != 0 {
        throw RuntimeError("Command failed with exit code \(process.terminationStatus): \(stderrString.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    return ProcessResult(exitCode: process.terminationStatus, stdout: stdoutString, stderr: stderrString)
}

struct RuntimeError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

func escapePlaylistAttribute(_ value: String) -> String {
    let escapedBackslashes = value.replacingOccurrences(of: "\\", with: "\\\\")
    return escapedBackslashes.replacingOccurrences(of: "\"", with: "\\\"")
}

func which(_ tool: String) -> String? {
    do {
        let result = try runProcess(path: "/usr/bin/which", arguments: [tool], printCommand: false)
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    } catch {
        return nil
    }
}

func parseBitrates(_ value: String) throws -> [Int] {
    let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    var bitrates: [Int] = []
    for part in parts where !part.isEmpty {
        guard let number = Int(part) else {
            throw CLIError.invalidNumber(flag: "-r", value: part)
        }
        bitrates.append(number)
    }
    return bitrates
}

func parseArguments() throws -> Config {
    var inputPath: String?
    var outputPath: String?
    var streamName: String?
    var aimePath: String?
    var segmentDuration: Double = 6.0
    var bitrates: [Int] = [25_000_000, 50_000_000, 100_000_000]
    var layout = "CH-STEREO/PACK-NONE/PROJ-AIV"
    var videoRange = "PQ"
    var contentType = "Fully Immersive"

    var iterator = CommandLine.arguments.dropFirst().makeIterator()

    while let arg = iterator.next() {
        switch arg {
        case "-i", "--input":
            guard let value = iterator.next() else { throw CLIError.missingValue(flag: arg) }
            inputPath = value
        case "-o", "--output":
            guard let value = iterator.next() else { throw CLIError.missingValue(flag: arg) }
            outputPath = value
        case "-n", "--name":
            guard let value = iterator.next() else { throw CLIError.missingValue(flag: arg) }
            streamName = value
        case "-d", "--duration":
            guard let value = iterator.next() else { throw CLIError.missingValue(flag: arg) }
            guard let number = Double(value) else { throw CLIError.invalidNumber(flag: arg, value: value) }
            segmentDuration = number
        case "-r", "--bitrates":
            guard let value = iterator.next() else { throw CLIError.missingValue(flag: arg) }
            bitrates = try parseBitrates(value)
        case "--aime":
            guard let value = iterator.next() else { throw CLIError.missingValue(flag: arg) }
            aimePath = value
        case "--layout":
            guard let value = iterator.next() else { throw CLIError.missingValue(flag: arg) }
            layout = value
        case "--video-range":
            guard let value = iterator.next() else { throw CLIError.missingValue(flag: arg) }
            videoRange = value
        case "--content-type":
            guard let value = iterator.next() else { throw CLIError.missingValue(flag: arg) }
            contentType = value
        case "-h", "--help":
            printUsage()
            exit(0)
        default:
            if arg.hasPrefix("-") {
                throw RuntimeError("Unknown flag: \(arg)")
            } else {
                // Treat bare arguments as input/output if not set
                if inputPath == nil {
                    inputPath = arg
                } else if outputPath == nil {
                    outputPath = arg
                } else {
                    throw RuntimeError("Unexpected positional argument: \(arg)")
                }
            }
        }
    }

    guard let resolvedInput = inputPath else { throw CLIError.missingRequired("input (-i)") }
    guard let resolvedOutput = outputPath else { throw CLIError.missingRequired("output (-o)") }

    let fm = FileManager.default
    let inputURL = URL(fileURLWithPath: resolvedInput).standardizedFileURL
    guard fm.fileExists(atPath: inputURL.path) else {
        throw CLIError.fileNotFound(inputURL.path)
    }

    let outputURL = URL(fileURLWithPath: resolvedOutput).standardizedFileURL
    var isDirectory: ObjCBool = false
    if fm.fileExists(atPath: outputURL.path, isDirectory: &isDirectory) {
        if !isDirectory.boolValue {
            throw RuntimeError("Output path exists but is not a directory: \(outputURL.path)")
        }
    } else {
        do {
            try fm.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw CLIError.directoryCreationFailed(outputURL.path)
        }
    }

    let finalStreamName: String
    if let name = streamName, !name.isEmpty {
        finalStreamName = name
    } else {
        finalStreamName = inputURL.deletingPathExtension().lastPathComponent
    }

    let aimeURL = aimePath.map { URL(fileURLWithPath: $0).standardizedFileURL }
    if let aimeURL, !fm.fileExists(atPath: aimeURL.path) {
        throw CLIError.fileNotFound(aimeURL.path)
    }

    return Config(
        inputURL: inputURL,
        outputDirectory: outputURL,
        streamName: finalStreamName,
        aimeURL: aimeURL,
        segmentDuration: segmentDuration,
        bitrates: bitrates,
        layout: layout,
        videoRange: videoRange,
        contentType: contentType
    )
}

func printUsage() {
    let usage = """
    Usage: aivu2hls.swift -i <input.aivu> -o <output_dir> [options]

    Required:
      -i, --input <path>       Source .aivu (QuickTime) file
      -o, --output <dir>       Destination directory for HLS output

    Options:
      -n, --name <string>      Stream name (default: input filename)
      -d, --duration <secs>    Segment duration in seconds (default: 6.0)
      -r, --bitrates <list>    Comma-separated BANDWIDTH values (bps)
                               default: 25000000,50000000,100000000
      --aime <path>            Venue AIME file to copy alongside playlists
      --layout <string>        REQ-VIDEO-LAYOUT value (default: CH-STEREO/PACK-NONE/PROJ-AIV)
      --video-range <value>    Variant VIDEO-RANGE attribute (default: PQ)
      --content-type <value>   Session DATA com.apple.private.content-type (default: Fully Immersive)
      -h, --help               Show this help text

    The tool prefers Apple's HLS authoring utilities when installed;
    otherwise it falls back to ffmpeg (copying tracks into an fMP4 ladder).
    Generated playlists are patched for immersive playback metadata and
    validated when mediastreamvalidator is available.
    """
    print(usage)
}

func cleanOutputDirectory(_ url: URL) throws {
    let fm = FileManager.default
    let contents = try fm.contentsOfDirectory(atPath: url.path)
    for item in contents {
        let itemURL = url.appendingPathComponent(item)
        try fm.removeItem(at: itemURL)
    }
}

func formatDecimal(_ value: Double, precision: Int = 3) -> String {
    let formatString = String(format: "%%.%df", precision)
    var string = String(format: formatString, value)
    while string.contains(".") && (string.last == "0" || string.last == ".") {
        if string.last == "0" {
            string.removeLast()
        } else if string.last == "." {
            string.removeLast()
            break
        }
    }
    return string
}

func formatFrameRate(_ value: Double) -> String {
    return formatDecimal(value)
}

func formatSegmentDuration(_ value: Double) -> String {
    return formatDecimal(value)
}

func probePlaylistMetadata(for inputURL: URL) -> PlaylistMetadata {
    guard let ffprobePath = which("ffprobe") else {
        print("ffprobe not found; skipping metadata probe.")
        return PlaylistMetadata(resolution: nil, frameRate: nil, codecs: nil, averageBitrate: nil, peakBitrate: nil)
    }

    do {
        let result = try runProcess(path: ffprobePath,
                                    arguments: ["-v", "error",
                                                "-print_format", "json",
                                                "-show_streams",
                                                "-show_format",
                                                inputURL.path],
                                    printCommand: false)
        guard let data = result.stdout.data(using: .utf8) else {
            return PlaylistMetadata(resolution: nil, frameRate: nil, codecs: nil, averageBitrate: nil, peakBitrate: nil)
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = object as? [String: Any],
              let streams = root["streams"] as? [[String: Any]] else {
            return PlaylistMetadata(resolution: nil, frameRate: nil, codecs: nil, averageBitrate: nil, peakBitrate: nil)
        }

        var resolution: String?
        var frameRate: String?
        var codecs: [String] = []
        var averageBitrate: Int?
        var peakBitrate: Int?

        if let format = root["format"] as? [String: Any] {
            if let bitRateString = format["bit_rate"] as? String, let bitRateValue = Double(bitRateString) {
                averageBitrate = Int(bitRateValue.rounded())
            } else if let bitRateNumber = format["bit_rate"] as? NSNumber {
                averageBitrate = bitRateNumber.intValue
            }
            if let avg = averageBitrate {
                peakBitrate = Int((Double(avg) * 2.0).rounded())
            }
        }

        for stream in streams {
            guard let codecType = stream["codec_type"] as? String else { continue }
            if codecType == "video" {
                if let width = stream["width"] as? Int,
                   let height = stream["height"] as? Int,
                   width > 0, height > 0 {
                    resolution = "\(width)x\(height)"
                }

                if let avg = stream["avg_frame_rate"] as? String, avg != "0/0" {
                    let parts = avg.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
                    if parts.count == 2,
                       let numerator = Double(parts[0]),
                       let denominator = Double(parts[1]),
                       denominator != 0 {
                        let value = numerator / denominator
                        frameRate = formatFrameRate(value)
                    } else if let value = Double(avg) {
                        frameRate = formatFrameRate(value)
                    }
                }

                let codecTag = (stream["codec_tag_string"] as? String)?.lowercased()
                let codecName = (stream["codec_name"] as? String)?.lowercased()
                var videoCodec: String?
                if let tag = codecTag, !tag.isEmpty {
                    if tag == "hvc1" || tag == "hev1" {
                        videoCodec = "hvc1"
                    } else if tag == "avc1" || tag == "avc3" {
                        videoCodec = "avc1"
                    } else {
                        videoCodec = tag
                    }
                }
                if videoCodec == nil, let name = codecName, !name.isEmpty {
                    if name == "hevc" || name == "h265" {
                        videoCodec = "hvc1"
                    } else if name == "h264" || name == "avc" {
                        videoCodec = "avc1"
                    } else {
                        videoCodec = name
                    }
                }
                if let videoCodec {
                    codecs.append(videoCodec)
                }
            } else if codecType == "audio" {
                let codecTag = (stream["codec_tag_string"] as? String)?.lowercased()
                let codecName = (stream["codec_name"] as? String)?.lowercased()
                var audioCodec: String?
                if let name = codecName {
                    if name == "aac" {
                        audioCodec = "mp4a.40.2"
                    } else if name == "ac3" {
                        audioCodec = "ac-3"
                    }
                }
                if audioCodec == nil, let tag = codecTag, !tag.isEmpty {
                    audioCodec = tag
                }
                if let audioCodec {
                    codecs.append(audioCodec)
                }
            }
        }

        let codecString = codecs.isEmpty ? nil : codecs.joined(separator: ",")
        return PlaylistMetadata(resolution: resolution, frameRate: frameRate, codecs: codecString, averageBitrate: averageBitrate, peakBitrate: peakBitrate)
    } catch {
        print("Warning: Unable to probe media metadata: \(error)")
        return PlaylistMetadata(resolution: nil, frameRate: nil, codecs: nil, averageBitrate: nil, peakBitrate: nil)
    }
}

func segmentWithAppleTools(config: Config, mediafilesegmenterPath: String) throws -> URL {
    print("Using Apple mediafilesegmenter.")
    let arguments = ["-f", config.outputDirectory.path,
                     "-t", formatSegmentDuration(config.segmentDuration),
                     "-B", config.streamName,
                     config.inputURL.path]
    _ = try runProcess(path: mediafilesegmenterPath, arguments: arguments)
    let variantURL = config.outputDirectory.appendingPathComponent("\(config.streamName).m3u8")
    guard FileManager.default.fileExists(atPath: variantURL.path) else {
        throw RuntimeError("mediafilesegmenter did not produce expected playlist at \(variantURL.path)")
    }
    return variantURL
}

func segmentWithFFmpeg(config: Config, ffmpegPath: String) throws -> URL {
    print("Using ffmpeg fallback for HLS segmentation.")
    let variantFilename = "\(config.streamName)_base.m3u8"
    let variantURL = config.outputDirectory.appendingPathComponent(variantFilename)
    if FileManager.default.fileExists(atPath: variantURL.path) {
        try FileManager.default.removeItem(at: variantURL)
    }

    let segmentPattern = config.outputDirectory.appendingPathComponent("\(config.streamName)_segment_%05d.m4s").path
    let initFilename = "\(config.streamName)_init.mp4"
    let initFilePath = config.outputDirectory.appendingPathComponent(initFilename).path

    let args: [String] = ["-y", "-i", config.inputURL.path,
                          "-map_metadata", "0",
                          "-map", "0:v:0",
                          "-map", "0:a?",
                          "-c:v", "copy",
                          "-c:a", "copy",
                          "-hls_time", formatSegmentDuration(config.segmentDuration),
                          "-hls_playlist_type", "vod",
                          "-hls_segment_type", "fmp4",
                          "-hls_flags", "independent_segments",
                          "-hls_fmp4_init_filename", initFilename,
                          "-hls_segment_filename", segmentPattern,
                          variantURL.path]

    _ = try runProcess(path: ffmpegPath, arguments: args)

    guard FileManager.default.fileExists(atPath: variantURL.path) else {
        throw RuntimeError("ffmpeg did not produce playlist at \(variantURL.path)")
    }

    guard FileManager.default.fileExists(atPath: initFilePath) else {
        throw RuntimeError("ffmpeg did not produce init segment at \(initFilePath)")
    }

    return variantURL
}

func duplicateVariantPlaylists(original variantURL: URL, config: Config) throws -> [String] {
    let fm = FileManager.default
    let baseVariantName = "\(config.streamName)_variant0.m3u8"
    let baseVariantURL = config.outputDirectory.appendingPathComponent(baseVariantName)
    if fm.fileExists(atPath: baseVariantURL.path) {
        try fm.removeItem(at: baseVariantURL)
    }
    if variantURL.path != baseVariantURL.path {
        try fm.moveItem(at: variantURL, to: baseVariantURL)
    }

    let variantData = try Data(contentsOf: baseVariantURL)

    var playlistNames: [String] = []
    for index in 0..<config.bitrates.count {
        if index == 0 {
            playlistNames.append(baseVariantName)
        } else {
            let filename = "\(config.streamName)_variant\(index).m3u8"
            let copyURL = config.outputDirectory.appendingPathComponent(filename)
            if fm.fileExists(atPath: copyURL.path) {
                try fm.removeItem(at: copyURL)
            }
            try variantData.write(to: copyURL)
            playlistNames.append(filename)
        }
    }

    if config.bitrates.count > 1 {
        print("Note: multiple bitrate rungs share the same media tracks. Provide pre-encoded variants for true multi-bitrate output.")
    }

    return playlistNames
}

func buildMasterPlaylist(variants: [String], config: Config, metadata: PlaylistMetadata) throws -> URL {
    var lines: [String] = ["#EXTM3U", "#EXT-X-VERSION:12"]

    if let aimeURL = config.aimeURL {
        let destination = config.outputDirectory.appendingPathComponent(aimeURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: aimeURL, to: destination)
        let escapedVenue = escapePlaylistAttribute(aimeURL.lastPathComponent)
        lines.append("#EXT-X-SESSION-DATA:DATA-ID=\"com.apple.hls.venue-description\",URI=\"\(escapedVenue)\"")
        lines.append("#EXT-X-IMMERSIVE-VIDEO:URI=\"\(escapedVenue)\"")
    }

    if !config.contentType.isEmpty {
        let escapedContentType = escapePlaylistAttribute(config.contentType)
        lines.append("#EXT-X-SESSION-DATA:DATA-ID=\"com.apple.private.content-type\",VALUE=\"\(escapedContentType)\"")
    }

    if variants.count != config.bitrates.count {
        throw RuntimeError("Variant count (\(variants.count)) does not match bitrate count (\(config.bitrates.count))")
    }

    for (index, variant) in variants.enumerated() {
        var attributes: [String] = []
        let declaredPeak = config.bitrates[index]
        let computedAverage = metadata.averageBitrate
        let computedPeak = metadata.peakBitrate
        let peakBandwidth = max(declaredPeak, computedPeak ?? declaredPeak)
        var averageBandwidth = computedAverage ?? declaredPeak
        if averageBandwidth > peakBandwidth {
            averageBandwidth = peakBandwidth
        }
        attributes.append("BANDWIDTH=\(peakBandwidth)")
        attributes.append("AVERAGE-BANDWIDTH=\(averageBandwidth)")
        let escapedLayout = escapePlaylistAttribute(config.layout)
        attributes.append("REQ-VIDEO-LAYOUT=\"\(escapedLayout)\"")
        attributes.append("VIDEO-RANGE=\(config.videoRange)")
        if let resolution = metadata.resolution {
            attributes.append("RESOLUTION=\(resolution)")
        }
        if let frameRate = metadata.frameRate {
            attributes.append("FRAME-RATE=\(frameRate)")
        }
        if let codecs = metadata.codecs, !codecs.isEmpty {
            let escapedCodecs = escapePlaylistAttribute(codecs)
            attributes.append("CODECS=\"\(escapedCodecs)\"")
        }
        attributes.append("CLOSED-CAPTIONS=NONE")
        lines.append("#EXT-X-STREAM-INF:\(attributes.joined(separator: ","))")
        lines.append(variant)
    }

    let masterContent = lines.joined(separator: "\n") + "\n"
    let masterURL = config.outputDirectory.appendingPathComponent("\(config.streamName).m3u8")
    try masterContent.write(to: masterURL, atomically: true, encoding: .utf8)
    return masterURL
}

func runValidatorIfAvailable(masterURL: URL) {
    guard let validatorPath = which("mediastreamvalidator") else {
        print("mediastreamvalidator not found; skipping validation.")
        return
    }

    do {
        _ = try runProcess(path: validatorPath, arguments: [masterURL.path])
        print("mediastreamvalidator completed successfully.")
    } catch {
        fputs("mediastreamvalidator reported an error: \(error)\n", stderr)
    }
}

func main() {
    do {
        let config = try parseArguments()
        try cleanOutputDirectory(config.outputDirectory)

        let playlistMetadata = probePlaylistMetadata(for: config.inputURL)

        let variantURL: URL
        if let mediafilesegmenterPath = which("mediafilesegmenter") {
            do {
                variantURL = try segmentWithAppleTools(config: config, mediafilesegmenterPath: mediafilesegmenterPath)
            } catch {
                print("mediafilesegmenter failed: \(error). Falling back to ffmpeg.")
                guard let ffmpegPath = which("ffmpeg") else {
                    throw RuntimeError("mediafilesegmenter failed and ffmpeg is unavailable. Cannot produce HLS output.")
                }
                variantURL = try segmentWithFFmpeg(config: config, ffmpegPath: ffmpegPath)
            }
        } else if let ffmpegPath = which("ffmpeg") {
            variantURL = try segmentWithFFmpeg(config: config, ffmpegPath: ffmpegPath)
        } else {
            throw RuntimeError("Neither mediafilesegmenter nor ffmpeg is available. Cannot produce HLS output.")
        }

        let variants = try duplicateVariantPlaylists(original: variantURL, config: config)
        let masterURL = try buildMasterPlaylist(variants: variants, config: config, metadata: playlistMetadata)
        print("Master playlist generated at \(masterURL.path)")
        runValidatorIfAvailable(masterURL: masterURL)
        print("Done.")
    } catch let error as CLIError {
        fputs("Error: \(error.description)\n", stderr)
        printUsage()
        exit(1)
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }
}

main()
