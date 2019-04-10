FROM centos:latest
RUN yum update -y && yum groupinstall -y 'Development Tools' && \
	yum install -y glibc-devel.i686 libgcc.i686 libstdc++-devel.i686 \
	ncurses-devel.i686 readline-devel.i686 readline-static.i686 readline.i686 \
	wget which
RUN mkdir -p /opt; wget -P /tmp --quiet https://www.lua.org/ftp/lua-5.2.4.tar.gz && \
	tar -C /opt -xf /tmp/lua-5.2.4.tar.gz  && rm /tmp/lua-5.2.4.tar.gz && \ 
	make -C /opt/lua-5.2.4 MYLDFLAGS=-m32 MYCFLAGS=-m32 linux install
COPY ./ /opt/
