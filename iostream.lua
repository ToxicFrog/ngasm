-- Stream IO for the nandgame VM.
-- An iostream device is backed by a file (or at least by a character device)
-- and takes up two words in memory.
-- Reads and writes to the first word will return successive words from the
-- backing stream, or write words to it.
-- Reads and writes to the second are identical, but will read and write bytes --
-- on writes the high byte is ignored and on reads the high byte is always 0x00.
-- Word-sized reads/writes are BIG-ENDIAN regardless of the host platform.

local bit = require "bit"

local iostream = {}
iostream.__index = iostream

function iostream.new(path, mode)
  return setmetatable({ path = path; mode = mode; fd = nil; }, iostream)
end

function iostream:__tostring()
  return string.format("iostream(%s, %s)", self.path, self.mode)
end

-- two words of memory
function iostream:size() return 2 end

-- IO functions
function iostream:read(address)
  if address == 0 then
    -- read word
    local high,low = self.fd:read(2):byte(1,2)
    return high * 256 + low
  else
    -- read byte
    return self.fd:read(1):byte()
  end
end

function iostream:write(address, data)
  if address == 0 then
    -- write word
    local low = data % 256
    local high = (data/256) % 256
    self.fd:write(string.char(high, low))
  else
    -- write byte
    self.fd:write(string.char(data % 256))
  end
end

-- management functions
function iostream:reset()
  return self:detach():attach()
end

function iostream:attach()
  -- attaching multiple times is a no-op, and the file remains open
  if self.fd then return end
  self.fd = assert(io.open(self.path, self.mode))
  return self
end

function iostream:detach()
  if not self.fd then return end
  assert(self.fd:close())
  self.fd = nil
  return self
end

return iostream
