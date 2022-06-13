#!/usr/bin/env ruby

def freqcount(semitones, note = 0x3C00)
  semitones = semitones + note
  unless semitones >= 0x8000 then fail "cannot handle positive case!" end
  # clamp to highest note 72
  semitones = [semitones, 0xB800].max
  octave_adjust = 0
  loop do
    octave_adjust += 1
    semitones += (12 << 8)
    if semitones >= 0x10000 then break end
  end
  semitones = (semitones & 0xFFFF) >> 2
  # note to frequency
  freqcount = ((2.0**(1.0/12.0))**(semitones/64.0))*1024
  freqcount = freqcount.round >> octave_adjust
  return freqcount
end

def samplerate(freqcount)
  # machine sample rate * freqcount[fixed 20.9]
  return (30476180.0/2.0 / (16.0*32.0))/2.0  *  freqcount/512.0
end

puts samplerate(freqcount(Integer(ARGV[0]),Integer(ARGV[1])))
