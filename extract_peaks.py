import wave
import struct
import math

def process_audio():
    # Read the full wav file
    with wave.open('wax_slime_full.wav', 'rb') as w:
        frames = w.getnframes()
        data = w.readframes(frames)
        rate = w.getframerate()
        channels = w.getnchannels()
        sampwidth = w.getsampwidth()
        
    print(f"Rate: {rate}, Channels: {channels}, Width: {sampwidth}, Frames: {frames}")
    
    # Convert to mono float array
    fmt = f"<{frames * channels}h"
    samples = struct.unpack(fmt, data)
    
    if channels == 2:
        mono = [float(samples[i] + samples[i+1]) / 65536.0 for i in range(0, len(samples), 2)]
    else:
        mono = [float(s) / 32768.0 for s in samples]
        
    # Find the sharpest peaks (the "crunch" sounds)
    window_size = int(rate * 0.05) # 50ms window
    
    peaks = []
    for i in range(0, len(mono) - window_size, window_size):
        energy = sum(x*x for x in mono[i:i+window_size])
        if energy > 0.05: # threshold
            peaks.append((i, energy))
            
    peaks.sort(key=lambda x: x[1], reverse=True)
    
    if not peaks:
        print("No peaks found")
        return
        
    # Take the best peak (highest energy)
    best_peak_idx = peaks[0][0]
    print(f"Best peak at {best_peak_idx / rate:.2f} seconds with energy {peaks[0][1]:.2f}")
    
    # Extract 0.15 seconds starting slightly before the peak
    start_idx = max(0, best_peak_idx - int(rate * 0.01))
    end_idx = min(len(mono), start_idx + int(rate * 0.15))
    
    extract = mono[start_idx:end_idx]
    
    # Apply fade in / fade out to avoid clicks
    fade_len = int(rate * 0.005) # 5ms
    for i in range(fade_len):
        extract[i] *= (i / fade_len)
        extract[-(i+1)] *= (i / fade_len)
        
    # Normalize
    max_val = max(abs(x) for x in extract)
    if max_val > 0:
        extract = [x / max_val * 0.9 for x in extract]
        
    # Write back to wav
    out_samples = [int(x * 32767.0) for x in extract]
    out_data = struct.pack(f"<{len(out_samples)}h", *out_samples)
    
    with wave.open('wax_slime_clean.wav', 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(out_data)
        
    print("Created wax_slime_clean.wav")

process_audio()
