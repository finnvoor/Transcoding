# Transcoding (WIP)


```swift
let videoEncoder = VideoEncoder(config: .ultraLowLatency)
let videoEncoderAnnexBAdaptor = VideoEncoderAnnexBAdaptor(
    videoEncoder: videoEncoder
)
let videoDecoder = VideoDecoder(config: .init())
let videoDecoderAnnexBAdaptor = try! VideoDecoderAnnexBAdaptor(
    videoDecoder: videoDecoder,
    codec: .hevc
)

videoEncoderTask = Task {
    for await data in videoEncoderAnnexBAdaptor.annexBData {
        // send data over network or whatever
    }
}

videoDecoderTask = Task {
    for await decodedSampleBuffer in videoDecoder.decodedSampleBuffers {
        // here you have a received decoded sample buffer with image buffer
    }
}

receivedMessageTask = Task {
    // Replace `realtimeStreaming.receivedMessages` with however you receive encoded data packets 
    for await (data, _) in realtimeStreaming.receivedMessages {
        videoDecoderAnnexBAdaptor.decode(data)
    }
}

captureSessionTask = Task {
    // Replace `captureSession.pixelBuffers` with your video data source
    for await pixelBuffer in captureSession.pixelBuffers {
        videoEncoder.encode(pixelBuffer)
    }
}
```

### Important Notes
- Currently `VideoDecoderAnnexBAdaptor` only supports decoding full NALU's, meaning if you are passing data over the network or some stream you must ensure you receive full video frame packets, not just an arbitrarily sized data stream. When using Network.framework, for example, you would use a custom `NWProtocolFramerImplementation` to receive individual messages.
- There are a number of instances where either the encoder or decoder needs to be reset during an application lifecycle. The encoder and decoder automatically handle resetting after an iOS app has been backgrounded, but you may need to handle other cases by calling `encoder/decoder.invalidate()`. For example, if you maintain one encoder and disconnect then reconnect from a peer/decoder, the encoder will need to be invalidated to ensure it sends over the H264/HEVC parameter sets again. Otherwise the decoder will not be able to decode frames, as the encoder is optimized to only send SPS/PPS/VPS when necessary.
