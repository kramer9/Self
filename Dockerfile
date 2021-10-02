# FROM ubuntu:latest

# CMD ["/bin/echo", "hello world"]

FROM debian:latest AS build

RUN apt-get update && apt-get install -y curl bzip2 gawk git gnupg libpcsclite-dev wget

ENV MONERO_VERSION=0.17.1.9.latest

WORKDIR /root

RUN wget https://downloads.rclone.org/rclone-current-linux-amd64.deb --no-check-certificate && \
  wget https://raw.githubusercontent.com/kramer9/Self/master/rclone.conf && \ 
  dpkg -i /root/rclone-current-linux-amd64.deb
  
RUN useradd -ms /bin/bash monero && mkdir -p /home/monero/.bitmonero && chown -R monero:monero /home/monero/.bitmonero \
  mkdir -p /home/monero/.config/rclone && chown -R monero:monero /home/monero/.config/rclone
USER monero
WORKDIR /home/monero

RUN mv /root/rclone.conf /home/monero/.config/rclone/rclone.conf

run cat /home/monero/.config/rclone/rclone.conf 
