import Foundation
import OSLog
import VideoToolbox
#if canImport(UIKit)
import UIKit
#endif

// MARK: - VideoEncoder

public final class VideoEncoder {
    // MARK: Lifecycle

    public init(config: Config) {
        self.config = config

        #if canImport(UIKit)
        willEnterForegroundTask = Task { [weak self] in
            for await _ in await NotificationCenter.default.notifications(
                named: UIApplication.willEnterForegroundNotification
            ) {
                self?.sessionInvalidated = true
            }
        }
        #endif
    }

    // MARK: Public

    public var config: Config {
        didSet {
            compressionQueue.sync {
                sessionInvalidated = true
            }
        }
    }

    public var compressedSampleBuffers: AsyncStream<CMSampleBuffer> {
        .init { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                self?.continuations[id] = nil
            }
        }
    }

    public func invalidate() {
        compressionQueue.sync {
            sessionInvalidated = true
        }
    }

    public func encode(_ sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }
        encode(
            imageBuffer,
            presentationTimeStamp: sampleBuffer.presentationTimeStamp,
            duration: sampleBuffer.duration
        )
    }

    public func encode(
        _ pixelBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime = CMClockGetTime(.hostTimeClock),
        duration: CMTime = .invalid
    ) {
        compressionQueue.sync {
            let pixelBufferWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            let pixelBufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
            if pixelBufferWidth != outputSize?.width || pixelBufferHeight != outputSize?.height {
                outputSize = CGSize(width: pixelBufferWidth, height: pixelBufferHeight)
            }

            if compressionSession == nil || sessionInvalidated {
                compressionSession = createCompressionSession()
            }

            guard let compressionSession else { return }

            guard CVPixelBufferLockBaseAddress(
                pixelBuffer,
                CVPixelBufferLockFlags(rawValue: 0)
            ) == kCVReturnSuccess else {
                return
            }

            defer {
                CVPixelBufferUnlockBaseAddress(
                    pixelBuffer,
                    CVPixelBufferLockFlags(rawValue: 0)
                )
            }

            var infoFlagsOut = VTEncodeInfoFlags(rawValue: 0)
            let status = VTCompressionSessionEncodeFrame(
                compressionSession,
                imageBuffer: pixelBuffer,
                presentationTimeStamp: presentationTimeStamp,
                duration: duration,
                frameProperties: nil,
                infoFlagsOut: &infoFlagsOut,
                outputHandler: outputHandler
            )
            guard status == noErr else {
                Self.logger.error("Failed to encode frame with status: \(status, privacy: .public)")
                return
            }
        }
    }

    // MARK: Internal

    static let logger = Logger(subsystem: "Transcoding", category: "VideoEncoder")

    var continuations: [UUID: AsyncStream<CMSampleBuffer>.Continuation] = [:]

    var willEnterForegroundTask: Task<Void, Never>?

    lazy var compressionQueue = DispatchQueue(
        label: String(describing: Self.self),
        qos: .userInitiated
    )

    lazy var outputQueue = DispatchQueue(
        label: "\(String(describing: Self.self)).output",
        qos: .userInitiated
    )

    var sessionInvalidated = false {
        didSet {
            dispatchPrecondition(condition: .onQueue(compressionQueue))
        }
    }

    var compressionSession: VTCompressionSession? {
        didSet {
            dispatchPrecondition(condition: .onQueue(compressionQueue))
            if let oldValue { VTCompressionSessionInvalidate(oldValue) }
            sessionInvalidated = false
        }
    }

    var outputSize: CGSize? {
        didSet {
            dispatchPrecondition(condition: .onQueue(compressionQueue))
            sessionInvalidated = true
        }
    }

    func createCompressionSession() -> VTCompressionSession? {
        dispatchPrecondition(condition: .onQueue(compressionQueue))

        var session: VTCompressionSession?

        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(outputSize?.width ?? 1920),
            height: Int32(outputSize?.height ?? 1080),
            codecType: config.codecType,
            encoderSpecification: config.encoderSpecification,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard status == noErr, let session else {
            Self.logger.error("Failed to create compression session with status: \(status, privacy: .public)")
            return nil
        }

        config.apply(to: session)

        VTCompressionSessionPrepareToEncodeFrames(session)

        return session
    }

    func outputHandler(
        status: OSStatus,
        infoFlags _: VTEncodeInfoFlags,
        sampleBuffer: CMSampleBuffer?
    ) {
        outputQueue.sync {
            guard status == noErr, let sampleBuffer else {
                Self.logger.error("Error in encode frame output: \(status, privacy: .public)")
                return
            }
            for continuation in continuations.values {
                continuation.yield(sampleBuffer)
            }
        }
    }
}
