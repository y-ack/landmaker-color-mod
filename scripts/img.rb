require 'bindata'

class SubImageHeader < BinData::Record
	endian :little
	uint32 :typecode    #? 18 for palette line entries
	uint32 :unknown1
	uint32 :len
	uint8  :unknown2
	uint8  :bpp         # exponent
	uint16 :vram_line
	uint16 :width       # assumes 16bpp,  have to width >> 4-bpp
	uint16 :height
end

filename = "PICI.IMG"
data = File.open(filename, "rb") { |f| f.read }

subimage_cnt = data.slice(0,4).unpack("L<").first
for i in 0..(subimage_cnt-1) do
  pos = 4 + 8*i
  sub_ofs = data.slice(pos,4).unpack("L<").first
  sub_header = SubImageHeader.read(data.slice(sub_ofs,20))
  if sub_header.typecode != 17 then
    puts "strange subimage data ##{i} (normal):"
    puts sub_header
  else
    if sub_header.bpp == 0 then
    	width = sub_header.width
    else
    	width = sub_header.width*16 >> sub_header.bpp
    end
    sub_filename = "#{filename}[#{i}]-W-#{width}-H-#{sub_header.height}.RAW"
		File.open(sub_filename, 'wb'){ |file|
			file.write(data.slice(sub_ofs+20,sub_header.len-12))
		}
  end
end
