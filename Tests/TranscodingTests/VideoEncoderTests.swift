import CoreMedia
@testable import Transcoding
import XCTest

final class VideoEncoderTests: XCTestCase {
    func testFrameEncoded() async throws {
        let encoder = VideoEncoder(config: .init())
        var stream = encoder.compressedSampleBuffers.makeAsyncIterator()
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 3840, 2160, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        CIContext().render(.red, to: pixelBuffer!)
        encoder.encode(pixelBuffer!)
        let compressedSampleBuffer = await stream.next()
        XCTAssertNotNil(compressedSampleBuffer?.dataBuffer)
        XCTAssertEqual(compressedSampleBuffer?.formatDescription?.mediaSubType, .hevc)
    }

    func testInvalidateSession() async throws {
        let encoder = VideoEncoder(config: .ultraLowLatency)
        var stream = encoder.compressedSampleBuffers.makeAsyncIterator()
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 3840, 2160, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        CIContext().render(.red, to: pixelBuffer!)
        encoder.encode(pixelBuffer!)
        _ = await stream.next()
        XCTAssertFalse(encoder.sessionInvalidated)
        encoder.config.realTime?.toggle()
        XCTAssertTrue(encoder.sessionInvalidated)
    }

    func testContinuationsEmptied() async throws {
        let encoder = VideoEncoder(config: .init())
        var stream: AsyncStream<CMSampleBuffer>? = encoder.compressedSampleBuffers
        _ = stream
        XCTAssertEqual(encoder.continuations.count, 1)
        stream = nil
        XCTAssertEqual(encoder.continuations.count, 0)
    }
}
