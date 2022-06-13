require 'bindata'

# Unsigned 24 bit big endian integer
class Uint24be < BinData::Primitive
	uint8 :byte1
	uint8 :byte2
	uint8 :byte3

	def get
		(self.byte1 << 16) | (self.byte2 << 8) | self.byte3
	end

	def set(v)
		v = 0 if v < 0
		v = 0xffffff if v > 0xffffff

		self.byte1 = (v >> 16) & 0xff
		self.byte2 = (v >>	8) & 0xff
		self.byte3 =	v				 & 0xff
	end
end

class SampleName < BinData::Record
	endian :big
	uint16 :ofs
	string :name, :length => 12, :trim_padding => true, :pad_byte => ' '
end

class SampleParameters < BinData::Record
	endian :big
	uint16 :frequency # 12 says this is in relation to semitones
	Uint24be :start_ofs
	uint8 :key_range_end
	Uint24be :loop_start
	uint8 :loop_type # 0=non-looping, 1,2,4=uni-directional, 3=bi-directional
	Uint24be :loop_end
	uint8 :u5
end

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
=begin
	puts freqcount(48041) # -> 632
	puts freqcount(47000) # -> 500
	puts freqcount(46898) # -> 488
=end

def samplerate(freqcount)
	# machine sample rate * freqcount[fixed 20.9]
	return (30476180.0/2.0 / (16.0*32.0))/2.0	 *	freqcount/512.0
end
=begin
	puts samplerate(freqcount(48041)) # -> 18368.66928
	puts samplerate(freqcount(47000)) # -> 14532.17506
	puts samplerate(freqcount(46898)) # -> 14183.40286
=end

$trk = 0
def writewav(filepath, samplerate, es_slice, s_name, params)
	slice_size = es_slice.size
	header_len = 44 + 46 + 56 + 60
	# signed 8-bit to unsigned 8-bit
	es_slice = es_slice.unpack("c*").map { |n| n + 0x80 }.pack("C*")
	File.open(filepath, 'wb'){ |file|
		file.write("RIFF")
		file.write([slice_size + header_len - 8].pack('L')) # 32bit file length
		file.write("WAVE")
		file.write("fmt ")
		file.write([16].pack('L')) # 32bit fmt chunk length
		file.write([1].pack('S'))	 # 16bit data type (pcm)
		file.write([1].pack('S'))	 # 16bit # channels
		file.write([samplerate].pack('L'))
		file.write([samplerate].pack('L')) # (sample rate * 8 bit/sample * 1 channel) / 8
		file.write([1].pack('S')) # (8 bit/sample * 1 channel) / 8
		file.write([8].pack('S')) # 8 bits per sample

		# INFO, 46 bytes
		file.write("LIST")
		file.write([38].pack('L'))
		file.write("INFO")
		file.write("INAM")
		file.write([14].pack("L"))
		file.write([s_name].pack("A12"))
		file.write([0].pack('S'))
		file.write("ITRK")
		file.write([4].pack("L"))
		$trk = $trk + 1
		file.write([$trk.to_s].pack("a4"))

		# ID3, 56 bytes
		file.write("id3 ")
		file.write([48].pack('L'))
		file.write("ID3") # ID3v2/file identifier
		file.write("\x03\x00") # ID3v2 version
		file.write("\0") # ID3v2 flags
		file.write([37].pack("L>")) # size
		file.write("TIT2")        # TITLE frame
		file.write([13].pack('L>'))
		file.write([0].pack('S>')) # flags
		file.write("\0") # ?
		file.write([s_name].pack("A12"))
		file.write("TRCK")        # TRACK frame
		file.write([4].pack("L>"))
		file.write([0].pack('S>')) # flags
		file.write($trk.to_s.rjust(4, "\0"))
		file.write("\0") # padding

		# cue, 60 bytes
		file.write("cue ")
		file.write([0x34].pack('L'))
		file.write([2].pack('L')) # number of cue points
		file.write("STRT") # loop start cue point identifier (viena needs 0000)
		file.write([0].pack('L'))
		file.write("\0\0\0\0") # chunk id (viena needs 0000)
		file.write([0].pack('L')) # chunk start
		file.write([0].pack('L')) # block start
		loop_start_ofs = ((params.loop_start - params.start_ofs) / 2).round
		file.write([loop_start_ofs].pack('L')) # cue point sample offset
		file.write("END ") # loop end cue point identifier (viena needs 0000)
		file.write([0].pack('L'))
		file.write("\0\0\0\0") # chunk id (viena needs 0000)
		file.write([0].pack('L')) # chunk start
		file.write([0].pack('L')) # block start
		# off by a fractional amount...
		loop_end_ofs = ((params.loop_end - params.start_ofs) / 2).round
		file.write([loop_end_ofs].pack('L')) # cue point sample offset
				
		file.write("data")
		file.write([slice_size].pack('L'))
		file.write(es_slice)
	}
end

ensoniq = File.open("ensoniq_unpadded.bin", "rb") { |f| f.read }
Dir.mkdir('wav') unless File.exists?('wav')

0x200000.step(0x7FFFFF,0x80000) do |bank|
	bank_magic = ensoniq.slice(bank,1).unpack("C")

	name_tbl_pos = 1
	while ensoniq.slice(bank+name_tbl_pos,4).unpack("L>").first != 0
		sample_n = SampleName.read(ensoniq.slice(bank+name_tbl_pos,14))
		split = 0
		loop do
			params = SampleParameters.read(ensoniq.slice(bank+sample_n.ofs + split*14,14))
			puts "#{sample_n.name},#{bank},#{sample_n.ofs},#{params.frequency},#{params.start_ofs},#{params.key_range_end},#{params.loop_start},#{params.loop_type},#{params.loop_end},#{params.u5}"

			filename = "wav/#{sample_n.name}_#{params.key_range_end}.wav"
			rate = samplerate(freqcount(params.frequency)).round
			wavelen = (params.loop_end - params.start_ofs)/2
			writewav(filename,rate,ensoniq.slice(bank + params.start_ofs/2, wavelen), sample_n.name, params)
			split += 1
			break if params.key_range_end >= 0x7F
		end
		name_tbl_pos += 14
	end
end
