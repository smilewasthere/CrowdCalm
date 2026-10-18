local framework = { passed = 0, failed = 0, failures = {}, context = nil }

local function repr(v)
  local t = type(v)
  if t == "string" then
    return string.format("%q", v)
  end
  return tostring(v)
end

function framework.describe(name, fn)
  local prev = framework.context
  framework.context = prev and (prev .. " > " .. name) or name
  local ok, err = pcall(fn)
  framework.context = prev
  if not ok then
    framework.failed = framework.failed + 1
    framework.failures[#framework.failures + 1] = { name = name, err = tostring(err) }
    io.write("FAIL ", name, "\n      ", tostring(err), "\n")
  end
end

function framework.it(name, fn)
  local label = framework.context and (framework.context .. " > " .. name) or name
  local ok, err = pcall(fn)
  if ok then
    framework.passed = framework.passed + 1
    io.write("PASS ", label, "\n")
  else
    framework.failed = framework.failed + 1
    framework.failures[#framework.failures + 1] = { name = label, err = tostring(err) }
    io.write("FAIL ", label, "\n      ", tostring(err), "\n")
  end
end

local Matchers = {}
Matchers.__index = Matchers

function Matchers:toBe(expected)
  if self.value ~= expected then
    error(string.format("expected %s to be %s", repr(self.value), repr(expected)), 2)
  end
end

function Matchers:toBeTruthy()
  if not self.value then
    error("expected a truthy value, got " .. repr(self.value), 2)
  end
end

function Matchers:toBeFalsy()
  if self.value then
    error("expected a falsy value, got " .. repr(self.value), 2)
  end
end

function Matchers:toBeNil()
  if self.value ~= nil then
    error("expected nil, got " .. repr(self.value), 2)
  end
end

function framework.expect(value)
  return setmetatable({ value = value }, Matchers)
end

function framework.run()
  io.write(string.format("\n%d passed, %d failed\n", framework.passed, framework.failed))
  for _, f in ipairs(framework.failures) do
    io.write("FAILED: ", f.name, "\n  ", f.err, "\n")
  end
  return framework.passed, framework.failed
end

return framework
