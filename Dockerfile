ARG RECIPES_IMAGE=t3hn3rd/moderne-asuro-recipes:0.1.1@sha256:eaf54188053511dad9c620a8fb98b0f50c41770cd49a0b3d71a0538386522011
FROM ${RECIPES_IMAGE}

VOLUME ["/code"]

ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386
RUN apt-get update && apt-get install -y \
	curl dos2unix wget git make nasm binutils xorriso grub-pc-bin gcc gcc-multilib ninja-build rsync \
	python3 python3-pip python3-pil && \
	apt-get clean && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir --break-system-packages "mkdocs>=1.6,<2" mkdocs-material

SHELL ["/bin/bash", "-c"]
ARG FPC_VERSION=3.2.2
RUN apt-get update && apt-get install -y --no-install-recommends fp-compiler && \
    rm -rf /var/lib/apt/lists/*
RUN curl -sL https://sourceforge.net/projects/freepascal/files/Linux/$FPC_VERSION/fpc-$FPC_VERSION.i386-linux.tar/download | tar -xf - && \
	pushd fpc-$FPC_VERSION.i386-linux && ./install.sh && popd && \
	rm -rf fpc-$FPC_VERSION.i386-linux

WORKDIR /code
RUN curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -o /tmp/packages-microsoft-prod.deb && \
    dpkg -i /tmp/packages-microsoft-prod.deb && \
    apt-get update && apt-get install -y --no-install-recommends powershell-lts && \
    rm -rf /var/lib/apt/lists/* /tmp/packages-microsoft-prod.deb

ENTRYPOINT ["pwsh", "-NoLogo", "-NoProfile", "-File", "/code/toolchain/build.ps1"]
