#!/usr/bin/env bash

set -e

cd "${BASH_SOURCE%/*}"

docker build -t galley-integration-base base

docker build -t galley-integration-backend:original backend
docker build -t galley-integration-application:original application
docker build -t galley-integration-config:original config
docker build -t galley-integration-database:original database
docker build -t galley-integration-rsync:original rsync
