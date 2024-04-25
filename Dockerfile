FROM ubuntu:latest
RUN apt-get update && apt-get install -y inetutils-ping sysbench iproute2 python3