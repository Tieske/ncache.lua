--- #Normalization cache
--
--
-- Use case: storing values by a specific key, except that the same key can have many
-- different representations. For example IPv6 addresses, where `[::1]`, `[::0:1]`, and
-- `[::0001]` all refer to the same address. To cache values you need normalization of the
-- key to a single, unique value for all the variants the key can have.
--
-- Since you need the normalization on every cache lookup, this can become too expensive.
-- Hence this library not only caches the values, but also the normalization results. Which
-- means that every key-variant only needs to be normalized once.
--
-- When creating a new cache you provide a normalization function, and the optionally the
-- cache instances for the two internal caches:
--
-- - key_cache : the cache that links the key variant to the normalized key.
-- - value_cache : the cache that holds the values, indexed by the normalized key.
--
-- You can either provide an OpenResty LRU cache, or not provide one, in which case it will
-- get a simple Lua table based cache. In the latter case you have to watch memory usage, as
-- it might grow uncontrollable.
--
-- When to use what caches for the `new` call:
--
-- `key_cache = nil, value_cache = nil`
--
-- In this case any data in there will only be removed when explicitly calling `delete`. So
-- only use this when the number of normalized-keys and their variants are limited. Otherwise
-- both caches can grow uncontrolled.
--
-- `key_cache = nil, value_cache = resty-lru`
--
-- This will protect against too many normalized keys. But not against too many variants of
-- a single key. Since the key_cache can still grow uncontrolled.
-- In case a value gets evicted from the value-cache, then all its key-variants will also be
-- removed from the key-cache based on weak-table references.
--
-- `key_cache = lru, value_cache = nil`
--
-- Use this if the number of normalized-keys is limited, but the variants are not.
--
-- `key_cache = lru, value_cache = lru`
--
-- This protects against both types of memory usage.
--
-- *Example 1:*
--
-- A cache of versioned items based on Semantic Versioning. Many input versions, in different formats
-- will lead to a limited number of compatible versions of objects to return.
-- Since the versions will (most likely) be defined in code, they will be limited. Both
-- the requested versions, as well as the returned versions.
-- In this case use the Lua-table based caches by providing `nil` for both of them, since there
-- is no risk of memory exhaustion in this case.
--
-- *Example 2:*
--
-- Matching incoming requested IPv6 addresses to a limited number of upstream servers.
-- Since we know the upstream servers before hand, or through some configuration directive
-- they will be limited.
--
-- But the incoming IPv6 addresses are user provided, and hence one can expect every possible
-- representation of that address to appear sometime (which are a lot!).
-- Hence for the value_cache (with a limited number of normalized addresses for the upstream
-- services) we can use the Lua-table based cache. But for the key-cache storing the combination
-- of every raw-key to normalized key, we must protect for overruns, and hence we use lru-cache.
--
-- NOTE: besides the above on cache types, it is important to realize that even if there is no
-- value in the cache, looking it up, will still normalize the key. It will store the raw key, the
-- normalized key, and the fact that there is no value for that key. So repeatedly looking for a
-- non-existing key will only normalize the key once. The cost of this optimization is that it
-- will still use memory to store the non-existing entry, and hence grow memory usage. Keep this
-- in mind when picking the proper cache types.
--
-- @copyright 2018 Thijs Schreijer
-- @author Thijs Schreijer
-- @license MIT

local M = {}

local ABSENT = {}  -- sentinel value indicating there is no value (for negative caching)
local INVALID = {} -- sentinel value indicating the record is invalid and shouldn't be used
local ERR_NOT_FOUND = "not found"


-- Creates a simple Lua table based cache.
-- @param weak if truthy the cache will have weak values
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
      if weak then
        setmetatable(cache, { __mode = "v" })
      end
    end
  }
  r:flush_all()  -- initialize the internal cache
  return r
end


--- Creates a new instance of the normalization cache.
-- The cache objects are optional, and are API compatible with the OpenResty lru-cache. If not
-- provided then simple table based caches will be created, without an lru safety mechanism.
-- @param normalizer (function) a function that normalizes a key value to a common, unique, non-nil representation
-- @param key_cache (optional) cache object (get, set, delete, flush_all) where the relation between the raw keys and values will be stored.
-- @param value_cache (optional) cache object (get, set, delete, flush_all) where the relation between the normalized key and values is stored
-- @return normalization cache
-- @usage -- sample `normalizer` function
-- local normalizer = function(key)
--   -- normalize everything to a proper number
--   local key = tonumber(key)
--   if key then return key end
--
--   return nil, "key was not coercable to a number"
-- end
--
-- local cache = mcache.new(normalizer)
function M.new(normalizer, key_cache, value_cache)
  if type(normalizer) ~= "function" then
    error("new requires to pass a 'normalizer' function", 2)
  end
  return setmetatable({
    normalizer = normalizer,
    key_cache = key_cache or create_cache(true),
    value_cache = value_cache or create_cache(false),
  }, M)
end


--- Returns the normalized key.
-- If the key was not in the cache, it will normalize and add it to the cache.
-- @param key the raw key in a normalizable format
-- @return the normalized key + key_entry (internal representation), or nil+error
function M:normalize(key)
  local key_entry = self.key_cache:get(key)
  if key_entry == nil then
    -- not found, we need to normalize it first
    local n_key, err = self.normalizer(key)
    if n_key == nil then
      return nil, "failed to normalize key: " .. tostring(err)
    end
    -- look it up by the normalized key
    key_entry = self.key_cache:get(n_key)
    if key_entry ~= nil then
      -- new variant of an existing key, store the new one
      self.key_cache:set(key, key_entry)
    else
      -- a complete new entry
      key_entry = {
        key = n_key,
        value = ABSENT,
      }
      -- store both raw + normalized variants we currently have
      self.key_cache:set(key, key_entry)
      self.key_cache:set(n_key, key_entry)
      -- add the value to the proper cache
      self.value_cache:set(n_key, key_entry)
    end

  elseif key_entry.key == INVALID then
    -- This entry is invalid, it was deleted. So
    -- delete this variant, and then try again
    self.key_cache:delete(key)
    return self:normalize(key)

  -- we have one, but it's normalized, so _touch the_
  -- _value cache to make sure it is kept alive (!)_ and
  -- validate it is the same.
  -- We're doing this, since we're only "getting" from the key-cache
  -- which might lead to eviction of the value from the value-cache
  -- because of low access rate. And even then it might still get evicted
  -- so in those cases evict from key-cache as well and regenerate.
  elseif key_entry ~= self.value_cache[key_entry.key] then
    -- value was removed from it's cache, can happen if its an lru...
    key_entry.value = ABSENT
    key_entry.key = INVALID
    self.key_cache:delete(key)  -- delete from key-cache as well
    return self:normalize(key)  -- try again, regenerate
  end

  return key_entry.key, key_entry
end

--- Sets a value in the cache.
-- Note: `nil` is a valid value to set, use `delete` to remove an entry.
-- @param key the raw key in a normalizable format
-- @param value the value to store (can be `nil`)
-- @return true on success, nil + err on error
function M:set(key, value)
  local n_key, entry = self.normalize(key)
  if n_key == nil then
    return nil, entry
  end
  entry.value = value
  return true
end

--- Gets a value from the cache.
-- Note: if there is no value, then still the normalization results will be stored
-- so even if nothing is in the cache, memory usage may increase when only getting.
-- To undo this, explicitly `delete` a key.
-- @param key the raw key in a normalizable format
-- @return the value, or nil + error. Note that `nil` is a valid value, and that
-- the error will be "not found" if the (normalized) key wasn't found.
function M:get(key)
  local n_key, entry = self.normalize(key)
  if n_key == nil then
    return nil, entry
  end

  local value = entry.value
  if value == ABSENT then
    return nil, ERR_NOT_FOUND
  end

  return entry.value
end

--- Deletes a key from the cache.
-- The accompanying value will also be deleted, and all other variants of `key`
-- will be evicted.
-- @param key the raw key in a normalizable format
-- @return true, or nil+err
function M:delete(key)
  local n_key, entry = self.normalize(key)
  if n_key == nil then
    return nil, entry
  end

  -- remove the value
  entry.value = ABSENT
  -- mark the entry as invalid
  entry.key = INVALID
  -- delete the key variants we know explicitly
  self.key_cache:delete(key)
  self.key_cache:delete(n_key)
  -- delete the value
  self.value_cache:delete(n_key)

  return true
end

--- Clears the cache.
-- Removes all values as well as all variants of normalized keys.
-- @return true
function M:flush_all()
  self.key_cache:flush_all()
  self.value_cache:flush_all()
  return true
end
