ARG RECIPES_IMAGE=t3hn3rd/moderne-asuro-recipes:0.1.1@sha256:eaf54188053511dad9c620a8fb98b0f50c41770cd49a0b3d71a0538386522011
FROM ${RECIPES_IMAGE}

VOLUME ["/code"]

ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386
RUN apt-get update && apt-get install -y \
	curl dos2unix wget git make nasm binutils xorriso grub-pc-bin gcc gcc-multilib \
	python3 python3-pip python3-pil && \
	apt-get clean && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir --break-system-packages "mkdocs>=1.6,<2" mkdocs-material

SHELL ["/bin/bash", "-c"]
ARG FPC_VERSION=3.2.2
RUN curl -sL https://sourceforge.net/projects/freepascal/files/Linux/$FPC_VERSION/fpc-$FPC_VERSION.i386-linux.tar/download | tar -xf - && \
	pushd fpc-$FPC_VERSION.i386-linux && ./install.sh && popd && \
	rm -rf fpc-$FPC_VERSION.i386-linux

ADD https://raw.githubusercontent.com/fsaintjacques/semver-tool/master/src/semver /usr/bin/semver
RUN chmod +x /usr/bin/semver
WORKDIR /code
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["find toolchain -name '*.sh' -exec dos2unix {} + 2>/dev/null; find toolchain -name '*.sh' -exec chmod +x {} +; bash toolchain/compile.sh"]
