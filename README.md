# Lua 5.2 sandbox escape
**Note:** docker file assume x86_64 hostx
## x86 environment
### Create docker image
```
docker build --tag lua-escape/x86:latest x86
```
## x86_64 environment 
### Create docker image
```
docker build --tag lua-escape/x86_64:latest x86_64
```

### Run exploit
First, run container
```
#From host shell, run either x86 version or x86_64 version
docker run -ti lua-escape/x86:latest /bin/bash  # x86 version
#OR
docker run -ti lua-escape/x86_64:latest /bin/bash  # x86_64 version 
```
Find relative address of target function, *system*
``` 
#On container
#!/bin/bash
#Setup
/opt/setup.sh
```
Exploit
```
#!/bin/bash
#Exploit!
lua /opt/exploit.lua
```

