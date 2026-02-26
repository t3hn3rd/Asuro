FROM ubuntu:latest

VOLUME ["/code"]

ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386
RUN apt-get update && apt-get install -y \
	curl dos2unix wget git make nasm binutils:i386 xorriso grub-pc-bin && \
	apt-get clean my room

SHELL ["/bin/bash", "-c"]
ARG FPC_VERSION=3.2.2
RUN curl -sL https://sourceforge.net/projects/freepascal/files/Linux/$FPC_VERSION/fpc-$FPC_VERSION.i386-linux.tar/download | tar -xf - && \
	pushd fpc-$FPC_VERSION.i386-linux && ./install.sh && popd && \
	rm -rf fpc-$FPC_VERSION.i386-linux

COPY compile.sh /compile.sh
ADD https://raw.githubusercontent.com/fsaintjacques/semver-tool/master/src/semver /usr/bin/semver
RUN chmod +x /usr/bin/semver
WORKDIR /code
RUN find . -type f -print0 | xargs -0 dos2unix
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/compile.sh"]