import Foundation
import AVFoundation

let url = URL(fileURLWithPath: "wax_slime_full.m4a")
let outUrl = URL(fileURLWithPath: "wax_slime.caf")
do {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let frameCount = AVAudioFrameCount(format.sampleRate * 0.15) // 0.15 seconds
    
    // Read frame
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    file.framePosition = AVAudioFramePosition(format.sampleRate * 2.0) // skip 2 seconds to get a clear crunch
    try file.read(into: buffer, frameCount: frameCount)
    
    // Write out
    let settings = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: format.sampleRate,
        AVNumberOfChannelsKey: format.channelCount,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsNonInterleaved: false,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ] as [String : Any]
    let outFile = try AVAudioFile(forWriting: outUrl, settings: settings)
    try outFile.write(from: buffer)
    print("Done")
} catch {
    print("Error: \(error)")
}
