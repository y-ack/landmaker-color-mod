require 'bindata'

ensoniq = File.open("ensoniq_unpadded.bin", "rb") { |f| f.read }

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
    self.byte2 = (v >>  8) & 0xff
    self.byte3 =  v        & 0xff
  end
end

class SampleName < BinData::Record
  endian :big
  uint16 :ofs
  string :name, :length => 12, :trim_padding => true, :pad_byte => ' '
end

class SampleParameters < BinData::Record
  endian :big
  uint16 :u1
	Uint24be :start_ofs
	uint8 :u3
	Uint24be :loop_ofs
	uint8 :u4
	Uint24be :end_ofs
	uint8 :u5
end


0x200000.step(0x7FFFFF,0x80000) do |bank|
  bank_magic = ensoniq.slice(bank,1).unpack("C")
  unless bank_magic#ord == 0x80
    fail "missing bank magic byte?"
  end

  name_tbl_pos = 1
  while ensoniq.slice(bank+name_tbl_pos,4).unpack("L>").first != 0
    sample_n = SampleName.read(ensoniq.slice(bank+name_tbl_pos,14))
    puts sample_n
    sample_params = SampleParameters.read(ensoniq.slice(bank+sample_n.ofs,14))
    puts sample_params
    
    name_tbl_pos += 14
  end
end
