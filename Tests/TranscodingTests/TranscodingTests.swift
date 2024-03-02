import CoreMedia
@testable import Transcoding
import XCTest

// MARK: - TranscodingTests

final class TranscodingTests: XCTestCase {
    func testFrameEncodedAndDecoded() {
        execute(withTimeout: 5) {
            let encoder = VideoEncoder(config: .ultraLowLatency)
            var stream = encoder.encodedSampleBuffers.makeAsyncIterator()
            var pixelBuffer: CVPixelBuffer!
            CVPixelBufferCreate(nil, 3840, 2160, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            CIContext().render(.red, to: pixelBuffer)
            encoder.encode(pixelBuffer)

            let encodedSampleBuffer = await stream.next()!
            XCTAssertNotNil(encodedSampleBuffer.dataBuffer)
            XCTAssertEqual(encodedSampleBuffer.formatDescription?.mediaSubType, .hevc)

            let decoder = VideoDecoder(config: .init())
            stream = decoder.decodedSampleBuffers.makeAsyncIterator()
            decoder.setFormatDescription(encodedSampleBuffer.formatDescription!)
            decoder.decode(encodedSampleBuffer)
            let decodedSampleBuffer = await stream.next()!
            XCTAssertNotNil(decodedSampleBuffer.imageBuffer)
            XCTAssertEqual(CVPixelBufferGetWidth(decodedSampleBuffer.imageBuffer!), CVPixelBufferGetWidth(pixelBuffer))
            XCTAssertEqual(CVPixelBufferGetHeight(decodedSampleBuffer.imageBuffer!), CVPixelBufferGetHeight(pixelBuffer))
        }
    }

    func testInvalidateSession() {
        execute(withTimeout: 5) {
            let encoder = VideoEncoder(config: .ultraLowLatency)
            var stream = encoder.encodedSampleBuffers.makeAsyncIterator()
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 3840, 2160, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            CIContext().render(.red, to: pixelBuffer!)
            encoder.encode(pixelBuffer!)
            let encodedSampleBuffer = await stream.next()!
            XCTAssertFalse(encoder.sessionInvalidated)
            encoder.config.realTime?.toggle()
            XCTAssertTrue(encoder.sessionInvalidated)

            let decoder = VideoDecoder(config: .init())
            stream = decoder.decodedSampleBuffers.makeAsyncIterator()
            decoder.setFormatDescription(encodedSampleBuffer.formatDescription!)
            decoder.decode(encodedSampleBuffer)
            _ = await stream.next()
            XCTAssertFalse(decoder.sessionInvalidated)
            decoder.config.realTime = false
            XCTAssertTrue(decoder.sessionInvalidated)
        }
    }

    func testContinuationsEmptied() {
        execute(withTimeout: 5) {
            let encoder = VideoEncoder(config: .ultraLowLatency)
            var stream: AsyncStream<CMSampleBuffer>? = encoder.encodedSampleBuffers
            _ = stream
            XCTAssertEqual(encoder.continuations.count, 1)
            stream = nil
            XCTAssertEqual(encoder.continuations.count, 0)

            let decoder = VideoDecoder(config: .init())
            stream = decoder.decodedSampleBuffers
            XCTAssertEqual(decoder.continuations.count, 1)
            stream = nil
            XCTAssertEqual(decoder.continuations.count, 0)
        }
    }

    func testAnnexBAdaptors() {
        execute(withTimeout: 5) {
            let encoder = VideoEncoder(config: .ultraLowLatency)
            let encoderAdaptor = VideoEncoderAnnexBAdaptor(videoEncoder: encoder)
            var annexBStream = encoderAdaptor.annexBData.makeAsyncIterator()
            let decoder = VideoDecoder(config: .init())
            var decodedStream = decoder.decodedSampleBuffers.makeAsyncIterator()
            let decoderAdaptor = VideoDecoderAnnexBAdaptor(videoDecoder: decoder, codec: .hevc)

            var pixelBuffer: CVPixelBuffer!
            CVPixelBufferCreate(nil, 3840, 2160, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            CIContext().render(.red, to: pixelBuffer)

            encoder.encode(pixelBuffer)
            let annexBData = await annexBStream.next()!

            decoderAdaptor.decode(annexBData)
            let decodedSampleBuffer = await decodedStream.next()!

            XCTAssertNotNil(decodedSampleBuffer.imageBuffer)
            XCTAssertEqual(CVPixelBufferGetWidth(decodedSampleBuffer.imageBuffer!), CVPixelBufferGetWidth(pixelBuffer))
            XCTAssertEqual(CVPixelBufferGetHeight(decodedSampleBuffer.imageBuffer!), CVPixelBufferGetHeight(pixelBuffer))
        }
    }
}

extension XCTestCase {
    func execute(
        withTimeout timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line,
        workItem: @escaping () async throws -> Void
    ) {
        let expectation = expectation(description: "Wait for async function")
        var workItemError: Error?
        let captureError = { workItemError = $0 }

        let task = Task {
            do {
                try await workItem()
            } catch {
                captureError(error)
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: timeout) { _ in
            if let error = workItemError {
                XCTFail("\(error)", file: file, line: line)
            }
            task.cancel()
        }
    }
}
