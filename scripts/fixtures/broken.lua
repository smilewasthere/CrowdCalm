-- Deliberately broken Lua used to prove check-lua.js detects syntax errors.
-- This file is never shipped: it lives under scripts/fixtures/ and is only
-- parsed when the gate is invoked with --fixture.
local function broken(  )
  print("this line is fine"
end
