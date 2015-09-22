FROM ubuntu:14.04

RUN apt-get update && apt-get install -y \
  rsync

COPY etc /etc

EXPOSE 873
CMD ["/usr/bin/rsync", "--no-detach", "--daemon"]
