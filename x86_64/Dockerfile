FROM centos:latest
RUN yum update -y && yum groupinstall -y 'Development Tools' && \
	yum install -y ncurses-devel readline-devel readline-static readline \
	wget which && yum clean all
RUN mkdir -p /opt; wget -P /tmp --quiet https://www.lua.org/ftp/lua-5.2.4.tar.gz && \
	tar -C /opt -xf /tmp/lua-5.2.4.tar.gz  && rm /tmp/lua-5.2.4.tar.gz && \ 
	make -C /opt/lua-5.2.4  linux install
COPY ./ /opt/
