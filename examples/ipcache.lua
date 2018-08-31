-----------------------------------------------
-- Example for normalizing IP addresses
-----------------------------------------------


-- code copied from Kong `utils` module
-- see http://github.com/Kong/kong and from
-- Penlight see https://github.com/stevedonovan/Penlight

local _M = {}
local gsub = string.gsub
local fmt = string.format
local lower = string.lower
local find = string.find

--- split a string into a list of strings separated by a delimiter.
-- @param s The input string
-- @param re A Lua string pattern; defaults to '%s+'
-- @param plain don't use Lua patterns
-- @param n optional maximum number of splits
-- @return a list-like table
-- @raise error if s is not a string
local function split(s,re,plain,n)
  local find,sub,append = string.find, string.sub, table.insert
  local i1,ls = 1,{}
  if not re then re = '%s+' end
  if re == '' then return {s} end
  while true do
      local i2,i3 = find(s,re,i1,plain)
      if not i2 then
          local last = sub(s,i1)
          if last ~= '' then append(ls,last) end
          if #ls == 1 and ls[1] == '' then
              return {}
          else
              return ls
          end
      end
      append(ls,sub(s,i1,i2-1))
      if n and #ls == n then
          ls[#ls] = sub(s,i1)
          return ls
      end
      i1 = i3+1
  end
end


--- checks the hostname type; ipv4, ipv6, or name.
-- Type is determined by exclusion, not by validation. So if it returns 'ipv6' then
-- it can only be an ipv6, but it is not necessarily a valid ipv6 address.
-- @param name the string to check (this may contain a portnumber)
-- @return string either; 'ipv4', 'ipv6', or 'name'
-- @usage hostname_type("123.123.123.123")  -->  "ipv4"
-- hostname_type("::1")              -->  "ipv6"
-- hostname_type("some::thing")      -->  "ipv6", but invalid...
_M.hostname_type = function(name)
  local remainder, colons = gsub(name, ":", "")
  if colons > 1 then
    return "ipv6"
  end
  if remainder:match("^[%d%.]+$") then
    return "ipv4"
  end
  return "name"
end

--- parses, validates and normalizes an ipv4 address.
-- @param address the string containing the address (formats; ipv4, ipv4:port)
-- @return normalized address (string) + port (number or nil), or alternatively nil+error
_M.normalize_ipv4 = function(address)
  local a,b,c,d,port
  if address:find(":") then
    -- has port number
    a,b,c,d,port = address:match("^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?):(%d+)$")
  else
    -- without port number
    a,b,c,d,port = address:match("^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$")
  end
  if not a then
    return nil, "invalid ipv4 address: " .. address
  end
  a,b,c,d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if a < 0 or a > 255 or b < 0 or b > 255 or c < 0 or
     c > 255 or d < 0 or d > 255 then
    return nil, "invalid ipv4 address: " .. address
  end
  if port then
    port = tonumber(port)
    if port > 65535 then
      return nil, "invalid port number"
    end
  end

  return fmt("%d.%d.%d.%d",a,b,c,d), port
end

--- parses, validates and normalizes an ipv6 address.
-- @param address the string containing the address (formats; ipv6, [ipv6], [ipv6]:port)
-- @return normalized expanded address (string) + port (number or nil), or alternatively nil+error
_M.normalize_ipv6 = function(address)
  local check, port = address:match("^(%b[])(.-)$")
  if port == "" then
    port = nil
  end
  if check then
    check = check:sub(2, -2)  -- drop the brackets
    -- we have ipv6 in brackets, now get port if we got something left
    if port then
      port = port:match("^:(%d-)$")
      if not port then
        return nil, "invalid ipv6 address"
      end
      port = tonumber(port)
      if port > 65535 then
        return nil, "invalid port number"
      end
    end
  else
    -- no brackets, so full address only; no brackets, no port
    check = address
    port = nil
  end
  -- check ipv6 format and normalize
  if check:sub(1,1) == ":" then
    check = "0" .. check
  end
  if check:sub(-1,-1) == ":" then
    check = check .. "0"
  end
  if check:find("::") then
    -- expand double colon
    local _, count = gsub(check, ":", "")
    local ins = ":" .. string.rep("0:", 8 - count)
    check = gsub(check, "::", ins, 1)  -- replace only 1 occurence!
  end
  local a,b,c,d,e,f,g,h = check:match("^(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?):(%x%x?%x?%x?)$")
  if not a then
    -- not a valid IPv6 address
    return nil, "invalid ipv6 address: " .. address
  end
  local zeros = "0000"
  return lower(fmt("%s:%s:%s:%s:%s:%s:%s:%s",
      zeros:sub(1, 4 - #a) .. a,
      zeros:sub(1, 4 - #b) .. b,
      zeros:sub(1, 4 - #c) .. c,
      zeros:sub(1, 4 - #d) .. d,
      zeros:sub(1, 4 - #e) .. e,
      zeros:sub(1, 4 - #f) .. f,
      zeros:sub(1, 4 - #g) .. g,
      zeros:sub(1, 4 - #h) .. h)), port
end

--- parses and validates a hostname.
-- @param address the string containing the hostname (formats; name, name:port)
-- @return hostname (string) + port (number or nil), or alternatively nil+error
_M.check_hostname = function(address)
  local name = address
  local port = address:match(":(%d+)$")
  if port then
    name = name:sub(1, -(#port+2))
    port = tonumber(port)
    if port > 65535 then
      return nil, "invalid port number"
    end
  end
  local match = name:match("^[%d%a%-%.%_]+$")
  if match == nil then
    return nil, "invalid hostname: " .. address
  end

  -- Reject prefix/trailing dashes and dots in each segment
  -- note: punycode allowes prefixed dash, if the characters before the dash are escaped
  for _, segment in ipairs(split(name, ".", true)) do
    if segment == "" or segment:match("-$") or segment:match("^%.") or segment:match("%.$") then
      return nil, "invalid hostname: " .. address
    end
  end
  return name, port
end

local verify_types = {
  ipv4 = _M.normalize_ipv4,
  ipv6 = _M.normalize_ipv6,
  name = _M.check_hostname,
}
--- verifies and normalizes ip adresses and hostnames. Supports ipv4, ipv4:port, ipv6, [ipv6]:port, name, name:port.
-- Returned ipv4 addresses will have no leading zero's, ipv6 will be fully expanded without brackets.
-- Note: a name will not be normalized!
-- @param address string containing the address
-- @return table with the following fields: `host` (string; normalized address, or name), `type` (string; 'ipv4', 'ipv6', 'name'), and `port` (number or nil), or alternatively nil+error on invalid input
_M.normalize_ip = function(address)
  local atype = _M.hostname_type(address)
  local addr, port = verify_types[atype](address)
  if not addr then
    return nil, port
  end
  return {
    type = atype,
    host = addr,
    port = port
  }
end

--- Formats an ip address or hostname with an (optional) port for use in urls.
-- Supports ipv4, ipv6 and names.
--
-- Explictly accepts 'nil+error' as input, to pass through any errors from the normalizing and name checking functions.
-- @param p1 address to format, either string with name/ip, table returned from `normalize_ip`, or from the `socket.url` library.
-- @param p2 port (optional) if p1 is a table, then this port will be inserted if no port-field is in the table
-- @return formatted address or nil+error
-- @usage
-- local addr, err = format_ip(normalize_ip("001.002.003.004:123"))  --> "1.2.3.4:123"
-- local addr, err = format_ip(normalize_ip("::1"))                  --> "[0000:0000:0000:0000:0000:0000:0000:0001]"
-- local addr, err = format_ip("::1", 80))                           --> "[::1]:80"
-- local addr, err = format_ip(check_hostname("//bad .. name\\"))    --> nil, "invalid hostname: ... "
_M.format_host = function(p1, p2)
  local t = type(p1)
  if t == "nil" then
    return p1, p2   -- just pass through any errors passed in
  end
  local host, port, typ
  if t == "table" then
    port = p1.port or p2
    host = p1.host
    typ = p1.type or _M.hostname_type(host)
  elseif t == "string" then
    port = p2
    host = p1
    typ = _M.hostname_type(host)
  else
    return nil, "cannot format type '" .. t .. "'"
  end
  if typ == "ipv6" and not find(host, "[", nil, true) then
    return "[" .. host .. "]" .. (port and ":" .. port or "")
  else
    return host ..  (port and ":" .. port or "")
  end
end

-----------------------------------------------
-- Example cache code
-----------------------------------------------

local Ncache = require "ncache"


--- Creates a IP/hostname based cache.
-- @return ncache object
local function name_cache(key_cache, value_cache, value_cache_non_evicting)

  local normalizer = function(hostname)
    -- normalizes hostnames, ipv4, and ipv6
    return _M.format_host(_M.normalize_ip(hostname))
  end

  return Ncache.new(normalizer, key_cache, value_cache, value_cache_non_evicting)
end


-----------------------------------------------
-- Test suite
-----------------------------------------------

describe("hostname/ip example", function()

  local test_count = 100000
  local now = require("socket").gettime
  local names = {
    ["::1"]        = "localhost ipv6",
    ["127.0.0.1"]  = "localhost ipv4",
    ["service.somedomain.com"] = "a generic hostname",
  }

  local function perf_test(key, expected)
    -- first test: non-cached
    collectgarbage()
    collectgarbage()
    local start_time = now()
    for _ = 1, test_count do
      assert(_M.format_host(_M.normalize_ip(key)) == expected)
    end
    local duration_plain = now() - start_time
    print("Plain time:", duration_plain, "seconds", 100 .. "%")

    -- second test: cached, but marked as evicting
    local cache = name_cache(nil, nil, false)
    for name, value in pairs(names) do
      assert(cache:set(name, value))
    end
    local target_value = names[key]
    collectgarbage()
    collectgarbage()
    local start_time = now()
    for _ = 1, test_count do
      assert(cache:get(key) == target_value)
    end
    local duration_evict = now() - start_time
    print("Evict time:", duration_evict, "seconds",
      math.floor((duration_evict/duration_plain * 100) + 0.5) .. "%", "100%")

    --third test: cached
    local cache = name_cache()
    for name, value in pairs(names) do
      assert(cache:set(name, value))
    end
    local target_value = names[key]
    collectgarbage()
    collectgarbage()
    local start_time = now()
    for _ = 1, test_count do
      assert(cache:get(key) == target_value)
    end
    local duration_cache = now() - start_time
    print("Cache time:", duration_cache, "seconds",
      math.floor((duration_cache/duration_plain * 100) + 0.5) .. "%",
      math.floor((duration_cache/duration_evict * 100) + 0.5) .. "%")
  end

  before_each(function()
  end)

  it("ipv6", function()
    perf_test("::1", "[0000:0000:0000:0000:0000:0000:0000:0001]")
  end)

  it("ipv4", function()
    perf_test("127.0.0.1", "127.0.0.1")
  end)

  it("name", function()
    perf_test("service.somedomain.com", "service.somedomain.com")
  end)

end)
