-----------------------------------------------
-- Example for getting versioned objects
-----------------------------------------------
-- the `version` module can be installed using LuaRocks:
--
-- `luarocks install version`
--
-- See https://github.com/Kong/version.lua


local Ncache = require "ncache"
local Version = require "version"


--- Creates a SemVer based cache.
-- @param list (table) values, indexed by their versions
-- @param closest (bool) if thruthy returns the newest version matching, otherwise the closest version
-- @return ncache object that returns the best SemVer based match
local function vcache(list, closest)
  local version_list = {}

  local normalizer = function(key)
    local v, err = Version(key)
    if not v then
      return nil, err
    end
    -- go find the semver compatible version
    local target
    for i = #version_list, 1, -1 do
      -- traverse backwards to find the newest compatible version
      local provider = version_list[i]
      if v:semver(provider) then
        -- this one is compatible
        target = provider
        if not closest then break end
      end
    end

    if not target then
      return nil, "version '" .. tostring(v) .. "' is unsupported"
    end
    return "*" .. tostring(target)
  end

  local ncache = Ncache.new(normalizer)

  -- insert all versions before hand
  for version, value in pairs(list) do
    version = Version(version)
    local version_string = tostring(version)
    table.insert(version_list, version)
    -- do a raw_set to skip invoking normalizer.
    ncache:raw_set("*" .. version_string, value)
  end
  -- sort for comparison
  table.sort(version_list)

  return ncache
end


-----------------------------------------------
-- Test suite
-----------------------------------------------

describe("vcache example", function()

  local versions = {
    ["0.9"] = "version 0.9",
    ["1.0"] = "version 1.0",
    ["1.2"] = "version 1.2",
    ["1.4.3"] = "version 1.4.3",
    ["2.3"] = "version 2.3",
  }

  it("returns closest versions", function()
    local cache = vcache(versions, true)
    -- note: pre 1.x version only match when exactly equal
    assert.equals("version 0.9", cache:get("0.9"))
    assert.same({ nil, "failed to normalize key: version '0.8' is unsupported"}, { cache:get("0.8") })
    assert.same({ nil, "failed to normalize key: version '0.9.1' is unsupported"}, { cache:get("0.9.1") })
    assert.equals("version 1.0", cache:get("1.0"))
    assert.equals("version 1.2", cache:get("1.1"))
    assert.equals("version 1.2", cache:get("1.2"))
    assert.equals("version 1.4.3", cache:get("1.4"))
    assert.same({ nil, "failed to normalize key: version '1.5' is unsupported"}, { cache:get("1.5") })
    assert.equals("version 2.3", cache:get("2.2"))
  end)

  it("returns newest versions", function()
    local cache = vcache(versions, false)
    -- note: pre 1.x version only match when exactly equal
    assert.equals("version 0.9", cache:get("0.9"))
    assert.same({ nil, "failed to normalize key: version '0.8' is unsupported"}, { cache:get("0.8") })
    assert.same({ nil, "failed to normalize key: version '0.9.1' is unsupported"}, { cache:get("0.9.1") })
    assert.equals("version 1.4.3", cache:get("1.0"))
    assert.equals("version 1.4.3", cache:get("1.1"))
    assert.equals("version 1.4.3", cache:get("1.2"))
    assert.equals("version 1.4.3", cache:get("1.4"))
    assert.same({ nil, "failed to normalize key: version '1.5' is unsupported"}, { cache:get("1.5") })
    assert.equals("version 2.3", cache:get("2.2"))
  end)

end)
