-- Stream IO for the nandgame VM.
--
-- This is identical to iostream, except backed by a string rather than a file.

local bit = require "bit"

local memstream = {}
memstream.__index = memstream

function memstream.new(buf)
  return setmetatable({ buf = buf, ptr = 1 }, memstream)
end

function memstream:__tostring()
  return string.format("memstream(#%d @ %d)", #self.buf, self.ptr)
end

-- Three words: [status, bytes, words]
function memstream:size() return 3 end

-- IO functions
function memstream:read(address)
  if address == 0 then
    -- status bit
    return self.ptr <= #self.buf and 0x0001 or 0x0000
  elseif address == 1 then
    -- read byte
    if self.ptr > #self.buf then return nil end
    local byte = self.buf:sub(self.ptr, self.ptr):byte()
    self.ptr = self.ptr + 1
    return byte
  elseif address == 2 then
    -- read word
    if self.ptr+1 > #self.buf then return nil end
    return self:read(1) * 256 + self:read(1)
  end
end

function memstream:write(address, data)
  if address == 0 then
    -- seek to offset
    self.ptr = data+1
  elseif address == 1 then
    -- write byte
    if self.ptr > #self.buf then
      self.buf = self.buf .. string.char(data % 256)
      self.ptr = #self.buf+1
    else
      self.buf = self.buf:sub(1, self.ptr-1)
        .. string.char(data % 256)
        .. self.buf:sub(self.ptr+1)
      self.ptr = self.ptr + 1
    end
  elseif address == 2 then
    -- write word
    local low = data % 256
    local high = (data/256) % 256
    self.buf = self.buf:sub(1, self.ptr-1)
      .. string.char(high, low)
      .. self.buf:sub(self.ptr+2)
    self.ptr = self.ptr + 2
  end
end

-- management functions
function memstream:reset()
  return self:attach():detach()
end

function memstream:attach()
  self.ptr = 1
  return self
end

function memstream:detach()
  return self
end

return memstream
