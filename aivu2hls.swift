#!/usr/bin/env swift

import Foundation
import AVFoundation
import ImmersiveMediaSupport

// MARK: - Configuration

struct Config {
	let inputURL: URL
	let outputDirectory: URL
	let streamName: String
	let segmentDuration: Double
	let bitrates: [Int]
	let layout: String
	let videoRange: String
	let contentType: String
}

struct RuntimeError: Error, CustomStringConvertible {
	let message: String
	init(_ message: String) { self.message = message }
	var description: String { message }
}

// MARK: - Argument Parsing

func parseArguments() throws -> Config {
	var inputPath: String?
	var outputPath: String?
	var streamName: String?
	var segmentDuration: Double = 6.0
	var bitrates: [Int] = [25_000_000, 50_000_000, 100_000_000]
	var layout = "CH-STEREO/PACK-NONE/PROJ-AIV"
	var videoRange = "PQ"
	var contentType = "Fully Immersive"

	var iterator = CommandLine.arguments.dropFirst().makeIterator()

	while let arg = iterator.next() {
		switch arg {
		case "-i", "--input":
			guard let value = iterator.next() else { throw RuntimeError("Missing value for \(arg)") }
			inputPath = value
		case "-o", "--output":
			guard let value = iterator.next() else { throw RuntimeError("Missing value for \(arg)") }
			outputPath = value
		case "-n", "--name":
			guard let value = iterator.next() else { throw RuntimeError("Missing value for \(arg)") }
			streamName = value
		case "-d", "--duration":
			guard let value = iterator.next() else { throw RuntimeError("Missing value for \(arg)") }
			guard let number = Double(value) else { throw RuntimeError("Invalid duration: \(value)") }
			segmentDuration = number
		case "-r", "--bitrates":
			guard let value = iterator.next() else { throw RuntimeError("Missing value for \(arg)") }
			bitrates = try parseBitrates(value)
		case "--layout":
			guard let value = iterator.next() else { throw RuntimeError("Missing value for \(arg)") }
			layout = value
		case "--video-range":
			guard let value = iterator.next() else { throw RuntimeError("Missing value for \(arg)") }
			videoRange = value
		case "--content-type":
			guard let value = iterator.next() else { throw RuntimeError("Missing value for \(arg)") }
			contentType = value
		case "-h", "--help":
			printUsage()
			exit(0)
		default:
			throw RuntimeError("Unknown argument: \(arg)")
		}
	}

	guard let resolvedInput = inputPath else { throw RuntimeError("Missing required argument: -i/--input") }
	guard let resolvedOutput = outputPath else { throw RuntimeError("Missing required argument: -o/--output") }

	let fm = FileManager.default
	let inputURL = URL(fileURLWithPath: resolvedInput).standardizedFileURL
	guard fm.fileExists(atPath: inputURL.path) else {
		throw RuntimeError("Input file not found: \(inputURL.path)")
	}

	let outputURL = URL(fileURLWithPath: resolvedOutput).standardizedFileURL
	var isDirectory: ObjCBool = false
	if fm.fileExists(atPath: outputURL.path, isDirectory: &isDirectory) {
		if !isDirectory.boolValue {
			throw RuntimeError("Output path exists but is not a directory: \(outputURL.path)")
		}
	} else {
		try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)
	}

	let finalStreamName = streamName ?? inputURL.deletingPathExtension().lastPathComponent

	return Config(
		inputURL: inputURL,
		outputDirectory: outputURL,
		streamName: finalStreamName,
		segmentDuration: segmentDuration,
		bitrates: bitrates,
		layout: layout,
		videoRange: videoRange,
		contentType: contentType
	)
}

func parseBitrates(_ value: String) throws -> [Int] {
	let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
	var bitrates: [Int] = []
	for part in parts where !part.isEmpty {
		guard let number = Int(part) else {
			throw RuntimeError("Invalid bitrate value: \(part)")
		}
		bitrates.append(number)
	}
	return bitrates
}

func printUsage() {
	print("""
		Usage: aivu2hls [options]

		Required:
		  -i, --input <path>       Input .aivu file
		  -o, --output <dir>       Output directory for HLS package

		Optional:
		  -n, --name <name>        Stream name (default: input filename)
		  -d, --duration <sec>     Segment duration (default: 6.0)
		  -r, --bitrates <list>    Comma-separated bitrates (default: 25000000,50000000,100000000)
		  --layout <value>         REQ-VIDEO-LAYOUT (default: CH-STEREO/PACK-NONE/PROJ-AIV)
		  --video-range <value>    VIDEO-RANGE (default: PQ)
		  --content-type <value>   Content type (default: Fully Immersive)
		  -h, --help               Show this help
		""")
}

// MARK: - Process Utilities

@discardableResult
func runProcess(path: String, arguments: [String], printCommand: Bool = true) throws -> (exitCode: Int32, stdout: String, stderr: String) {
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

	return (process.terminationStatus, stdoutString, stderrString)
}

func which(_ tool: String) -> String? {
	let result = try? runProcess(path: "/usr/bin/which", arguments: [tool], printCommand: false)
	guard let result, result.exitCode == 0 else { return nil }
	let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
	return trimmed.isEmpty ? nil : trimmed
}

// MARK: - AIVU Processing

func extractVenueAIME(from inputURL: URL, to aimeURL: URL) async throws {
	print("Extracting VenueDescriptor from AIVU...")
	
	let asset = AVURLAsset(url: inputURL)
	
	// Load metadata from AIVU file
	let metadataItems = try await asset.load(.metadata)
	
	// Find AIME data metadata item
	let aimeItems = AVMetadataItem.metadataItems(from: metadataItems, filteredByIdentifier: .quickTimeMetadataAIMEData)
	guard let aimeItem = aimeItems.first,
	      let aimeData = try await aimeItem.load(.value) as? Data else {
		throw RuntimeError("No AIME data found in AIVU file")
	}
	
	// Load VenueDescriptor from AIME data
	let venueDescriptor = try await VenueDescriptor(aimeData: aimeData)
	
	// Save VenueDescriptor to .aime file
	try await venueDescriptor.save(to: aimeURL)
	
	print("✓ Extracted venue metadata to \(aimeURL.lastPathComponent)")
}

// MARK: - HLS Segmentation

func segmentWithMediaFileSegmenter(config: Config, mediafilesegmenterPath: String) throws {
	print("Segmenting with mediafilesegmenter...")
	
	let durationString = String(Int(config.segmentDuration))
	let indexFilename = "\(config.streamName).m3u8"
	
	// mediafilesegmenter automatically preserves all tracks including metadata
	let arguments = [
		"-f", config.outputDirectory.path,
		"-t", durationString,
		"-B", config.streamName,
		"-i", indexFilename,
		config.inputURL.path
	]
	
	let result = try runProcess(path: mediafilesegmenterPath, arguments: arguments)
	guard result.exitCode == 0 else {
		throw RuntimeError("mediafilesegmenter failed: \(result.stderr)")
	}
	
	// Verify output
	let variantURL = config.outputDirectory.appendingPathComponent(indexFilename)
	guard FileManager.default.fileExists(atPath: variantURL.path) else {
		throw RuntimeError("mediafilesegmenter did not produce expected playlist")
	}
	
	print("✓ Segmentation complete")
}

// MARK: - Master Playlist

func probeMetadata(from inputURL: URL) async throws -> (resolution: String?, frameRate: String?, codecs: String?) {
	guard let ffprobePath = which("ffprobe") else {
		return (nil, nil, nil)
	}
	
	let args = ["-v", "error", "-show_streams", "-of", "json", inputURL.path]
	let result = try runProcess(path: ffprobePath, arguments: args, printCommand: false)
	
	guard let jsonData = result.stdout.data(using: .utf8),
	      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
	      let streams = json["streams"] as? [[String: Any]] else {
		return (nil, nil, nil)
	}
	
	var resolution: String?
	var frameRate: String?
	var videoCodec: String?
	var audioCodec: String?
	
	for stream in streams {
		let codecType = stream["codec_type"] as? String
		
		if codecType == "video" {
			if let width = stream["width"] as? Int, let height = stream["height"] as? Int {
				resolution = "\(width)x\(height)"
			}
			if let rateStr = stream["r_frame_rate"] as? String {
				let parts = rateStr.split(separator: "/")
				if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
					frameRate = String(format: "%.3f", num / den)
				}
			}
			if let codec = stream["codec_name"] as? String {
				videoCodec = codec == "hevc" ? "hvc1.2.20000000.H183" : codec
			}
		} else if codecType == "audio" {
			if let codec = stream["codec_name"] as? String {
				audioCodec = codec == "aac" ? "mp4a.40.2" : codec
			}
		}
	}
	
	let codecs: String?
	if let vc = videoCodec, let ac = audioCodec {
		codecs = "\(vc),\(ac)"
	} else if let vc = videoCodec {
		codecs = vc
	} else if let ac = audioCodec {
		codecs = ac
	} else {
		codecs = nil
	}
	
	return (resolution, frameRate, codecs)
}

func buildMasterPlaylist(config: Config) async throws {
	print("Building master playlist...")
	
	let masterURL = config.outputDirectory.appendingPathComponent("\(config.streamName)_master.m3u8")
	
	// Probe metadata
	let (resolution, frameRate, codecs) = try await probeMetadata(from: config.inputURL)
	
	// Get AIME file
	let aimeURL = config.outputDirectory.appendingPathComponent("\(config.streamName).venue.aime")
	guard FileManager.default.fileExists(atPath: aimeURL.path) else {
		throw RuntimeError("Venue AIME file not found: \(aimeURL.lastPathComponent)")
	}
	
	var lines: [String] = []
	lines.append("#EXTM3U")
	lines.append("#EXT-X-VERSION:12")
	lines.append("")
	
	// Session data for venue
	lines.append("#EXT-X-SESSION-DATA:DATA-ID=\"com.apple.hls.venue-description\",URI=\"\(aimeURL.lastPathComponent)\"")
	
	// Content type
	let escapedContentType = escapePlaylistAttribute(config.contentType)
	lines.append("#EXT-X-SESSION-DATA:DATA-ID=\"com.apple.private.content-type\",VALUE=\"\(escapedContentType)\"")
	lines.append("")
	
	// Variants
	let variantPlaylist = "\(config.streamName).m3u8"
	
	for bitrate in config.bitrates {
		var attributes: [String] = []
		attributes.append("BANDWIDTH=\(bitrate)")
		
		if let codecs {
			attributes.append("CODECS=\"\(codecs)\"")
		}
		if let resolution {
			attributes.append("RESOLUTION=\(resolution)")
		}
		if let frameRate {
			attributes.append("FRAME-RATE=\(frameRate)")
		}
		
		attributes.append("VIDEO-RANGE=\(config.videoRange)")
		
		let escapedLayout = escapePlaylistAttribute(config.layout)
		attributes.append("REQ-VIDEO-LAYOUT=\"\(escapedLayout)\"")
		
		lines.append("#EXT-X-STREAM-INF:\(attributes.joined(separator: ","))")
		lines.append(variantPlaylist)
	}
	
	let content = lines.joined(separator: "\n") + "\n"
	try content.write(to: masterURL, atomically: true, encoding: .utf8)
	
	print("✓ Master playlist: \(masterURL.lastPathComponent)")
}

func escapePlaylistAttribute(_ value: String) -> String {
	value.replacingOccurrences(of: "\\", with: "\\\\")
	     .replacingOccurrences(of: "\"", with: "\\\"")
}

// MARK: - Validation

func validateOutput(config: Config) throws {
	guard let validatorPath = which("mediastreamvalidator") else {
		print("⚠️  mediastreamvalidator not found, skipping validation")
		return
	}
	
	print("Validating HLS output...")
	
	let masterURL = config.outputDirectory.appendingPathComponent("\(config.streamName)_master.m3u8")
	let args = ["--device", "visionpro", masterURL.path]
	
	let result = try runProcess(path: validatorPath, arguments: args, printCommand: false)
	
	if result.stdout.contains("CRITICAL") || result.stdout.contains("ERROR") {
		print("❌ Validation failed:")
		print(result.stdout)
		throw RuntimeError("Validation errors detected")
	} else if result.stdout.contains("CAUTION") {
		print("⚠️  Validation warnings (expected for binary AIME format)")
	} else {
		print("✓ Validation passed")
	}
}

// MARK: - Main

func run() async {
	do {
		let config = try parseArguments()
		
		print("AIVU → HLS Converter")
		print("Input: \(config.inputURL.lastPathComponent)")
		print("Output: \(config.outputDirectory.path)")
		print("")
		
		// Check for required Apple tools
		guard let mediafilesegmenterPath = which("mediafilesegmenter") else {
			throw RuntimeError("mediafilesegmenter not found. Please install Apple HLS tools from developer.apple.com/download")
		}
		
		// Extract venue AIME
		let aimeURL = config.outputDirectory.appendingPathComponent("\(config.streamName).venue.aime")
		try await extractVenueAIME(from: config.inputURL, to: aimeURL)
		
		// Segment with Apple tools
		try segmentWithMediaFileSegmenter(config: config, mediafilesegmenterPath: mediafilesegmenterPath)
		
		// Build master playlist
		try await buildMasterPlaylist(config: config)
		
		// Validate
		try validateOutput(config: config)
		
		print("")
		print("✓ HLS package complete: \(config.streamName)_master.m3u8")
		
	} catch {
		print("Error: \(error)")
		exit(1)
	}
}

await run()
