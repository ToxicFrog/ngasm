-- Stream IO for the nandgame VM.
-- An iostream device is backed by a file (or at least by a character device).
-- It maps three addresses:
-- 0 - file status word
--      read: 0x0001 if there is data remaining in the file, 0x0000 otherwise
--      write: seek to the written offset (absolute from start of file)
-- 1 - byte-width IO
--      read: return the next byte from the file. The high bits of the word will be 0.
--      write: write a single byte to the file. The input will be & with 0x00FF.
-- 2 - word-width IO
--      read: return the next 16-bit word from the file, MSB first.
--      write: write a 16-bit word to the file, MSB first.

local bit = require "bit"

local iostream = {}
iostream.__index = iostream

function iostream.new(path, mode)
  return setmetatable({ path = path; mode = mode; fd = nil; }, iostream)
end

function iostream:__tostring()
  return string.format("iostream(%s, %s)", self.path, self.mode)
end

-- Three words: [status, bytes, words]
function iostream:size() return 3 end

-- IO functions
function iostream:read(address)
  if address == 0 then
    -- status bit
    return self.fd:read(0) and 0x0001 or 0x0000
  elseif address == 1 then
    -- read byte
    return self.fd:read(1):byte()
  elseif address == 2 then
    -- read word
    local high,low = self.fd:read(2):byte(1,2)
    return high * 256 + low
  end
end

function iostream:write(address, data)
  if address == 0 then
    -- seek to offset
    self.fd:seek('set', data)
  elseif address == 1 then
    -- write byte
    self.fd:write(string.char(data % 256))
  elseif address == 2 then
    -- write word
    local low = data % 256
    local high = (data/256) % 256
    self.fd:write(string.char(high, low))
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
