-- saves files to "raw/<gamename>/", create this dir first!
mainrom = manager.machine.memory.regions[":maincpu"]
sprites = manager.machine.memory.regions[":sprites"]
sprites_hi = manager.machine.memory.regions[":sprites_hi"]
tiles = manager.machine.memory.regions[":tilemap"]
tiles_hi = manager.machine.memory.regions[":tilemap_hi"]
function strcpy_lol(addr)
  local s = ""
  for i = 0, 15, 1 do
    local c = mainrom:read_u8(addr + i)
    if c == 0 or c == 32 then break end
    s = s .. string.char(c)
  end
  return s 
end
function save_matrix(m, width, height, filename)
  out = io.open(string.format("raw/%s/%s",manager.machine.system.name,filename),"wb")
  for i=0, width*height-1, 1 do
    out:write(string.char(m[i]))
  end
  out:close()
  return filename
end
function parse_chip(value, is_tilemap)
  if is_tilemap then
    xflip   = (sp & 0x40000000) ~= 0
    yflip   = (sp & 0x80000000) ~= 0
    indexq  = (sp & 0x30000000) ~= 0
    planes  = (sp & 0x0c000000) >> 26
    ablend  = (sp & 0x02000000) ~= 0  
    chip    = (sp & 0xffff)
  else
    xflip   = (sp & 0x01000000) ~= 0
    yflip   = (sp & 0x02000000) ~= 0
    indexq  = (sp & 0x0c000000) ~= 0
    planes  = (sp & 0x30000000) >> 28 --(?)
    ablend  = (sp & 0x40000000) ~= 0  --(?)
    chip    = (sp & 0xffff)
  end
  -- don't even bother with color
  return chip, xflip, yflip, indexq, planes, ablend
end
function get_bits(n, bits, ofs)
  local result = 0
  for k,bpos in ipairs(bits) do
    result = result | ((n & 1<<(bpos+ofs))>>(bpos+ofs))<<(k-1)
  end
  return result
end
function save_namedblock_as_raw(addr, scp)
  local obj = 0
  if scp==nil or scp==0 then obj = 1 else obj = 0 end
  local name = strcpy_lol(addr+4)
  local addr = mainrom:read_u32(addr)
  local h = obj + mainrom:read_u16(addr)
  local w = obj + mainrom:read_u16(addr + 2)
  if obj==0 then w,h = w,h end -- different order for scps...
  px = {} -- [h*w*16]
  start = addr + 4
  for u = 0,w-1, 1 do
    for v = 0,h-1, 1 do
      if obj==0 then -- scps/tilemaps are row major
        addr = start + v*w*4 + u*4 
      else -- obj/sprites are column major
        addr = start + u*h*4 + v*4
      end
      --print(string.format("%x",addr))
      sp = mainrom:read_u32(addr)
      chip, xflip, yflip = parse_chip(sp, obj==0)
      if obj==0 then
        gfx_lo, gfx_hi = tiles, tiles_hi
        xoffsets_hi = {7, 6, 5, 4, 3, 2, 1, 0,  23, 22, 21, 20, 19, 18, 17, 16}
        planeoffsets_hi = {8, 0}
      else
        gfx_lo, gfx_hi = sprites, sprites_hi
        xoffsets_hi = {6, 4, 2, 0,  14, 12, 10, 8,  22, 20, 18, 16,  30, 28, 26, 24}
        planeoffsets_hi = {0, 1}
      end
      local row, rowend, rowstep = 0, 15*16, 16
      local col, colend, colstep = 0, 16-2, 2 -- read 2x 4bpp low/byte in chip
      for row=0, rowend, rowstep do
        for col=0, colend, colstep do
          -- reverse write direction
          if xflip then gcol=colend-col; go=1; gd=-1 else gcol=col; go=0; gd=1 end
          if yflip then grow=rowend-row              else grow=row end
          local gidx = v*16*w*16 + grow*w + u*16 + gcol
          local ofs = (256*chip + row + col)//2 -- 2 pixels per byte
          L = gfx_lo:read_u8(ofs)
          px[gidx+go+gd*0] =  L & 0x0F
          px[gidx+go+gd*1] = (L & 0xF0)>>4
        end
      end
      row, rowend, rowstep = 0, 15*16, 16
      col, colend, colstep = 0, 16-16, 16 -- read 16x 2bpp high/4 bytes in chip
      for row=0, rowend, rowstep do
        for col=0, colend, colstep do
          -- reverse write direction
          if xflip then gcol=colend-col; go=15; gd=-1 else gcol=col; go=0; gd=1 end
          if yflip then grow=rowend-row               else grow=row end
          local gidx = v*16*w*16 + grow*w + u*16 + gcol
          local ofs = (256*chip + row + col)//4 -- 4 pixels per byte
          -- endianness isn't actually a concept that exists. you don't have to believe in it.
          H = gfx_hi:read_u8(ofs)<<24 | gfx_hi:read_u8(ofs+1)<<16 | gfx_hi:read_u8(ofs+2)<<8 | gfx_hi:read_u8(ofs+3)
          for gp=0, 16-1, 1 do
            px[gidx+go+gd*gp]=px[gidx+go+gd*gp] | get_bits(H,planeoffsets_hi,xoffsets_hi[16-gp])<<4
          end
        end
      end
    end
  end
  local filename = string.format("%s-W-%d-H-%d.raw",name,w*16,h*16)
  save_matrix(px, w*16, h*16, filename)
  print("saved " .. filename)
end

-- save_namedblock_as_raw(0xb2136)
-- save_namedblock_as_raw(0xb05de)
-- save_namedblock_as_raw(0xb64b6)
-- save_namedblock_as_raw(0xb64b6+20*(56+3753+1)-16, 1)