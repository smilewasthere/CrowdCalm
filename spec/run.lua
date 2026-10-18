local dir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."

local framework = dofile(dir .. "/framework.lua")
_G.describe = framework.describe
_G.it = framework.it
_G.expect = framework.expect

_G.stub = dofile(dir .. "/wow_stub.lua")
stub.install()

local specs = {
  "smoke_spec",
  "crowd_spec",
  "profiles_spec",
}

for _, name in ipairs(specs) do
  local chunk, err = loadfile(dir .. "/" .. name .. ".lua")
  if not chunk then
    io.stderr:write("cannot load spec '" .. name .. "': " .. tostring(err) .. "\n")
    os.exit(1)
  end
  chunk()
end

local passed, failed = framework.run()
os.exit(failed == 0 and 0 or 1)
