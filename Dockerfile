# FROM ubuntu:latest

# CMD ["/bin/echo", "hello world"]

FROM debian:latest AS build

RUN apt-get update && apt-get install -y curl bzip2 gawk git gnupg libpcsclite-dev wget

ENV MONERO_VERSION=0.17.1.9.latest

WORKDIR /root

RUN wget https://downloads.rclone.org/rclone-current-linux-amd64.deb --no-check-certificate && \
  wget https://raw.githubusercontent.com/kramer9/Self/master/rclone.conf 
  
RUN useradd -ms /bin/bash monero && mkdir -p /home/monero/.bitmonero && chown -R monero:monero /home/monero/.bitmonero
USER monero
WORKDIR /home/monero
RUN dpkg -i /root/rclone-current-linux-amd64.deb && \
  mv /root/rclone.conf /home/monero/.config/rclone/rclone.conf

run cat /home/monero/.config/rclone/rclone.conf 
