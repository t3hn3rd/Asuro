FROM ubuntu:latest

VOLUME ["/code"]

RUN dpkg --add-architecture i386 && \
	apt-get update
RUN apt-get install nasm curl make:i386 binutils:i386 xorriso grub-pc-bin dos2unix -y
RUN apt-get clean
RUN curl https://sourceforge.net/projects/freepascal/files/Linux/2.6.4/fpc-2.6.4.i386-linux.tar/download --output fpc.tar -L && \
	tar -xf fpc.tar

WORKDIR ./fpc-2.6.4.i386-linux
RUN ./install.sh

COPY compile.sh /compile.sh
RUN mkdir /code
WORKDIR /code
RUN find . -type f -print0 | xargs -0 dos2unix
ENTRYPOINT ["/bin/bash", "/compile.sh"]