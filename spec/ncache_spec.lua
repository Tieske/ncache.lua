local call_count
local normalizer = function(key)
  call_count = call_count + 1
  local num = tonumber(key)
  return num, (not num) and "not a valid number"
end

-- create a simple cache, returns the cache, but also it's cache
-- table for test inspection
local function create_cache(weak)
  local cache

  local r = {
    get = function(self, key)
      return cache[key]
    end,
    set = function(self, key, value)
      cache[key] = value
      return true
    end,
    delete = function(self, key)
      cache[key] = nil
      return true
    end,
    flush_all = function(self)
      cache = {}
      -- self.cache = cache  -- for debugging only
      if weak then
        setmetatable(cache, { __mode = "v" })
      end
    end
  }
  r:flush_all()  -- initialize the internal cache
  return r, cache
end

describe("ncache:", function()

  local ncache, cache

  before_each(function()
    ncache = require("ncache")
    cache = ncache.new(normalizer)
    call_count = 0
  end)

  after_each(function()
    cache = nil
  end)

  it("requires anormalizer function", function()
    assert.has.error(function()
      ncache.new(nil)
    end)
  end)

  it("stores an entry", function()
    cache:set(5, "value 5")
    assert.equal(1, call_count)  -- normalized once
    assert.equal("value 5", cache:get(5))
    assert.equal(1, call_count)  -- don't normalize again
  end)

  it("getting a non existing key returns a 'key not found' error", function()
    local value, err = cache:get(5)
    assert.is_nil(value)
    assert.equal(ncache.ERR_NOT_FOUND, err)
  end)

  it("setting a value to nil is supported", function()
    cache:set(5, nil)  -- set value to nil
    assert.equal(1, call_count)
    local value, err = cache:get(5)
    assert.is_nil(value)
    assert.is_nil(err)  -- no error in this case
    assert.equal(1, call_count)
  end)

  it("caches raw and normalized keys", function()
    cache:set("5", "value 5")
    assert.equal(1, call_count)  -- normalized once
    assert.equal("value 5", cache:get(5))  -- get using normalized key
    assert.equal(1, call_count)  -- don't normalize again
    assert.equal("value 5", cache:get("5"))  -- get using raw key
    assert.equal(1, call_count)  -- don't normalize again
  end)

  it("set updates all related entries", function()
    local value = {}  -- by reference value
    cache:set(5, "value 5")
    cache:get("5")
    assert.equal(2, call_count)  -- once for each key
    cache:set("5", value)
    assert.equal(2, call_count)  -- no new ones
    assert.equal(value, cache:get("5"))  -- get using raw key
    assert.equal(value, cache:get(5))    -- get using normalized key
    assert.equal(2, call_count)  -- still no new ones
  end)

  it("delete removes entry", function()
    cache:set(5, "value 5")
    assert.equal(1, call_count)  -- normalized once
    cache:delete(5)
    cache:set(5, "value 5")
    assert.equal(2, call_count)  -- normalized again after deleting
  end)

  it("raw_set bypasses the normalizer", function()
    cache:raw_set("5", "value 5")
    cache:raw_set(5, "why 5?")
    assert.equal(0, call_count)  -- normalized never
    assert.equal("value 5", cache:get("5"))
    assert.equal("why 5?", cache:get(5))
    assert.equal(0, call_count)  -- normalized still never
  end)

  it("delete removes key-variants as well", function()
    cache:set(5, "value 5")
    cache:set("5", "value 5")
    assert.equal(2, call_count)  -- normalized both variants
    cache:delete(5)              -- delete by normalized-key -> orphane the raw one
    collectgarbage()
    collectgarbage()  -- make sure to clean weak tables
    cache:set(5, "value 5")
    cache:set("5", "value 5")
    assert.equal(4, call_count)  -- normalized both variants again
  end)

  it("delete removes key-variants without GC", function()
    finally(function()
      collectgarbage("restart")
    end)
    cache:set(5, "value 5")
    cache:set("5", "value 5")
    assert.equal(2, call_count)  -- normalized both variants
    collectgarbage("stop")

    cache:delete(5)              -- delete by normalized-key -> orphane the raw one
    cache:set(5, "value 5")
    cache:set("5", "value 5")
    assert.equal(4, call_count)  -- normalized both variants again
  end)

  it("flush_all removes entries", function()
    cache:set(5, "value 5")
    cache:flush_all()
    assert.is_nil(cache:get(5))
  end)

  it("flush_all removes key-variants as well", function()
    cache:set(5, "value 5")
    cache:set("5", "value 5")
    assert.equal(2, call_count)  -- normalized both variants
    cache:flush_all()
    assert.is_nil(cache:get(5))
    assert.is_nil(cache:get("5"))
    assert.equal(4, call_count)  -- normalized both variants again
  end)

  it("set/get/delete return error on key-normalization failure", function()
    local result, err = cache:set(nil,"some value")
    assert.is_nil(result)
    assert.matches(err, "failed to normalize key: not a valid number")
    local result, err = cache:get(nil,"some value")
    assert.is_nil(result)
    assert.matches(err, "failed to normalize key: not a valid number")
    local result, err = cache:delete(nil,"some value")
    assert.is_nil(result)
    assert.matches(err, "failed to normalize key: not a valid number")
  end)

  it("external eviction of cache-keys regenerates them", function()
    local key_cache, inspect = create_cache()
    local value_cache = create_cache()
    local nc = ncache.new(normalizer, key_cache, value_cache)
    nc:set(5, "value 5")
    nc:get("5")
    assert.equal(2, call_count)  -- normalized both variants
    assert(inspect["5"])         -- value should be there
    inspect["5"] = nil           -- remove it, emulate external eviction
    assert.equal("value 5", nc:get("5")) -- retrieve proper value
    assert.equal(3, call_count)  -- one more normalization
  end)

  it("external eviction of cache-values also drops key-variants", function()
    local key_cache = create_cache()
    local value_cache, inspect = create_cache()
    local nc = ncache.new(normalizer, key_cache, value_cache)
    nc:set(5, "value 5")
    nc:get("5")
    assert(inspect[5])             -- value should be there
    inspect[5] = nil               -- remove it, emulate external eviction
    local value, err = nc:get("5") -- retrieve proper value
    assert.is_nil(value)           -- should no longer be available
    assert.equal(err, ncache.ERR_NOT_FOUND)
  end)

end)
