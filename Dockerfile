FROM ubuntu:20.04

USER root
RUN apt-get update && \
    mkdir -p /usr/share/man/man1 && \
    apt-get install -y \
    git mercurial xvfb \
    locales sudo openssh-client ca-certificates tar gzip parallel \
    net-tools netcat unzip zip bzip2 gnupg curl wget python3 python3-pip python3-dev netstat libudev-dev libusb-1.0-0-dev vim

RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

RUN locale-gen C.UTF-8 || true
ENV LANG=C.UTF-8

RUN useradd --shell /bin/bash --create-home ubuntu && adduser ubuntu sudo && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER ubuntu
WORKDIR /home/ubuntu
