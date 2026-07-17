@preconcurrency import AVFoundation
import Foundation

final class VoiceInputPCMTransfer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

struct VoiceInputPCMFormat: Sendable {
    let sampleRate: Double
    let formatID: AudioFormatID
    let formatFlags: AudioFormatFlags
    let bytesPerPacket: UInt32
    let framesPerPacket: UInt32
    let bytesPerFrame: UInt32
    let channelsPerFrame: UInt32
    let bitsPerChannel: UInt32

    init(_ description: AudioStreamBasicDescription) {
        sampleRate = description.mSampleRate
        formatID = description.mFormatID
        formatFlags = description.mFormatFlags
        bytesPerPacket = description.mBytesPerPacket
        framesPerPacket = description.mFramesPerPacket
        bytesPerFrame = description.mBytesPerFrame
        channelsPerFrame = description.mChannelsPerFrame
        bitsPerChannel = description.mBitsPerChannel
    }

    var streamDescription: AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: formatID,
            mFormatFlags: formatFlags,
            mBytesPerPacket: bytesPerPacket,
            mFramesPerPacket: framesPerPacket,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channelsPerFrame,
            mBitsPerChannel: bitsPerChannel,
            mReserved: 0
        )
    }
}

struct VoiceInputCopiedPCM: Sendable {
    let format: VoiceInputPCMFormat
    let frameLength: AVAudioFrameCount
    let buffers: [Data]

    var duration: TimeInterval {
        Double(frameLength) / format.sampleRate
    }

    init(copying buffer: AVAudioPCMBuffer) throws {
        let description = buffer.format.streamDescription
        self = try Self.copy(
            format: VoiceInputPCMFormat(description.pointee),
            frameLength: buffer.frameLength,
            audioBufferList: buffer.audioBufferList
        )
    }

    static func copyIfAdmitted(
        _ buffer: AVAudioPCMBuffer,
        generation: UInt64,
        queue: VoiceInputPCMQueue
    ) {
        let description = buffer.format.streamDescription
        let format = VoiceInputPCMFormat(description.pointee)
        copyIfAdmitted(
            format: format,
            frameLength: buffer.frameLength,
            generation: generation,
            queue: queue
        ) {
            try Self.copy(
                format: format,
                frameLength: buffer.frameLength,
                audioBufferList: buffer.audioBufferList
            )
        }
    }

    #if compiler(>=6.4)
    @available(macOS 27, *)
    init(copying buffer: AVReadOnlyAudioPCMBuffer) throws {
        let description = buffer.format.streamDescription
        self = try buffer.withUnsafeAudioBufferList { list in
            try Self.copy(
                format: VoiceInputPCMFormat(description.pointee),
                frameLength: AVAudioFrameCount(buffer.frameLength),
                audioBufferList: list
            )
        }
    }

    @available(macOS 27, *)
    static func copyIfAdmitted(
        _ buffer: AVReadOnlyAudioPCMBuffer,
        generation: UInt64,
        queue: VoiceInputPCMQueue
    ) {
        let description = buffer.format.streamDescription
        let format = VoiceInputPCMFormat(description.pointee)
        let frameLength = AVAudioFrameCount(buffer.frameLength)
        copyIfAdmitted(
            format: format,
            frameLength: frameLength,
            generation: generation,
            queue: queue
        ) {
            try buffer.withUnsafeAudioBufferList { list in
                try Self.copy(
                    format: format,
                    frameLength: frameLength,
                    audioBufferList: list
                )
            }
        }
    }
    #endif

    func makeTransfer() throws -> VoiceInputPCMTransfer {
        var description = format.streamDescription
        guard let audioFormat = AVAudioFormat(streamDescription: &description),
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameLength) else {
            throw VoiceInputServiceError.invalidInputFormat
        }
        buffer.frameLength = frameLength

        let destination = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard destination.count == buffers.count else {
            throw VoiceInputServiceError.invalidInputFormat
        }
        for (index, data) in buffers.enumerated() {
            let audioBuffer = destination[index]
            guard let pointer = audioBuffer.mData,
                  data.count <= Int(audioBuffer.mDataByteSize) else {
                throw VoiceInputServiceError.invalidInputFormat
            }
            data.copyBytes(to: pointer.assumingMemoryBound(to: UInt8.self), count: data.count)
            destination[index].mDataByteSize = UInt32(data.count)
        }
        return VoiceInputPCMTransfer(buffer: buffer)
    }

    private static func copy(
        format: VoiceInputPCMFormat,
        frameLength: AVAudioFrameCount,
        audioBufferList: UnsafePointer<AudioBufferList>
    ) throws -> VoiceInputCopiedPCM {
        guard frameLength > 0,
              format.sampleRate > 0,
              format.sampleRate.isFinite,
              format.channelsPerFrame > 0 else {
            throw VoiceInputServiceError.invalidInputFormat
        }
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        let buffers = try source.map { audioBuffer -> Data in
            guard audioBuffer.mDataByteSize > 0, let pointer = audioBuffer.mData else {
                throw VoiceInputServiceError.invalidInputFormat
            }
            return Data(bytes: pointer, count: Int(audioBuffer.mDataByteSize))
        }
        return VoiceInputCopiedPCM(format: format, frameLength: frameLength, buffers: buffers)
    }

    private static func copyIfAdmitted(
        format: VoiceInputPCMFormat,
        frameLength: AVAudioFrameCount,
        generation: UInt64,
        queue: VoiceInputPCMQueue,
        copy: () throws -> VoiceInputCopiedPCM
    ) {
        guard frameLength > 0,
              format.sampleRate > 0,
              format.sampleRate.isFinite,
              format.channelsPerFrame > 0 else {
            queue.fail(.invalidInputFormat)
            return
        }
        let duration = Double(frameLength) / format.sampleRate
        guard queue.reserve(duration: duration, generation: generation) else {
            return
        }
        do {
            queue.commitReserved(try copy())
        } catch {
            queue.cancelReservation(duration: duration)
            queue.fail(.invalidInputFormat)
        }
    }

    private init(format: VoiceInputPCMFormat, frameLength: AVAudioFrameCount, buffers: [Data]) {
        self.format = format
        self.frameLength = frameLength
        self.buffers = buffers
    }
}
