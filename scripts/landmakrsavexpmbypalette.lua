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
function save_matrix(m, width, height, filename, palette)
  dir = string.format("raw/%s/xpm_bypal/%06X/",manager.machine.system.name,palette)
  ok = os.rename(dir,dir)
  if ok == nil then
      os.execute('mkdir "' .. dir .. '"')
  end
  out = io.open(string.format("raw/%s/xpm_bypal/%06X/%s",manager.machine.system.name,palette,filename),"wb")
  out:write("/* XPM */\n")
  out:write("char* NAME_XPM[] = {")
  out:write(string.format("\"%d %d %d %d\",\n", width, height, 64, 1))
  CBASE = 48
  out:write(string.format("\"%c c None\",\n",CBASE+0))
  for i=1, 63, 1 do
    local r = mainrom:read_u8(palette + i*4+1)
    local g = mainrom:read_u8(palette + i*4+2)
    local b = mainrom:read_u8(palette + i*4+3)
    out:write(string.format("\"%s c #%02X%02X%02X\",\n",string.char(CBASE+i),r,g,b))
  end
  for y=0, height-1, 1 do
    out:write("\"")
    for x=0, width-1, 1 do
      out:write(string.char(CBASE+m[y*width + x]))
    end
    out:write("\",\n")
  end
  out:write("}\n")
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
function save_namedblock_as_raw(addr, scp, palette)
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
  local filename = string.format("%s.xpm",name,w*16,h*16)
  save_matrix(px, w*16, h*16, filename, palette)
  print("saved " .. filename)
end


BL_OBJ_PAL = 0x0caed2
BL_OBJ = 0x0ad60e
for bl_idx=0,5577,1 do
  pal = mainrom:read_u32(BL_OBJ_PAL + bl_idx*4)
  save_namedblock_as_raw(BL_OBJ + 20*bl_idx, 0, pal)
end
BL_OBJ_PAL = 0x0caed2
BL_OBJ = 0x0ad60e
for bl_idx=0,0,1 do
  pal = mainrom:read_u32(BL_OBJ_PAL + bl_idx*4)
  save_namedblock_as_raw(BL_OBJ + 20*bl_idx, 0, pal)
end

BL_SCR_PAL = 0x0d05fe
BL_SCR = 0x0c89da
for bl_idx=0,472,1 do
--  pal = mainrom:read_u32(BL_SCR_PAL + bl_idx*4)
--  save_namedblock_as_raw(BL_SCR + 20*bl_idx, 1, pal)
end
