FROM ubuntu:14.04

RUN apt-get update && apt-get install -y \
  curl \
  nodejs \
  npm

RUN ln -s /usr/bin/nodejs /usr/bin/node
RUN npm install -g http-server@0.7.4
