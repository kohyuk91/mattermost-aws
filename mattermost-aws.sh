#!/bin/bash

# Docker 설치
sudo yum update -y
yum install -y docker

# Start the Docker service.
service docker start

# Docker Compose 설치
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Add the 'ec2-user' to the Docker group so you can execute Docker commands without using 'sudo'
usermod -a -G docker ec2-user

# Set the permissions.
chmod +x /usr/local/bin/docker-compose

# Clone the repository and enter the directory.
yum install -y git
git clone https://github.com/mattermost/docker
cd docker

# '.env' 파일 생성
cat << "EOF" > .env
# Container settings
## Timezone inside the containers. The value needs to be in the form 'Europe/Berlin'.
## A list of these tz database names can be looked up at Wikipedia
## https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TZ=UTC
RESTART_POLICY=unless-stopped

# Postgres settings
## Documentation for this image and available settings can be found on hub.docker.com
## https://hub.docker.com/_/postgres
## Please keep in mind this will create a superuser and it's recommended to use a less privileged
## user to connect to the database.
## A guide on how to change the database user to a nonsuperuser can be found in docs/creation-of-nonsuperuser.md
POSTGRES_IMAGE_TAG=13-alpine
POSTGRES_DATA_PATH=./volumes/db/var/lib/postgresql/data

POSTGRES_USER=mmuser
POSTGRES_PASSWORD=mmuser_password
POSTGRES_DB=mattermost

# Nginx
## The nginx container will use a configuration found at the NGINX_MATTERMOST_CONFIG. The config aims
## to be secure and uses a catch-all server vhost which will work out-of-the-box. For additional settings
## or changes ones can edit it or provide another config. Important note: inside the container, nginx sources
## every config file inside */etc/nginx/conf.d* ending with a *.conf* file extension.

## Inside the container the uid and gid is 101. The folder owner can be set with
## `sudo chown -R 101:101 ./nginx` if needed.
## Note that this repository requires nginx version 1.25.1 or later
NGINX_IMAGE_TAG=alpine

## The folder containing server blocks and any additional config to nginx.conf
NGINX_CONFIG_PATH=./nginx/conf.d
NGINX_DHPARAMS_FILE=./nginx/dhparams4096.pem

CERT_PATH=./volumes/web/cert/cert.pem
KEY_PATH=./volumes/web/cert/key-no-password.pem
#GITLAB_PKI_CHAIN_PATH=<path_to_your_gitlab_pki>/pki_chain.pem
#CERT_PATH=./certs/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
#KEY_PATH=./certs/etc/letsencrypt/live/${DOMAIN}/privkey.pem

## Exposed ports to the host. Inside the container 80, 443 and 8443 will be used
HTTPS_PORT=443
HTTP_PORT=80
CALLS_PORT=8443

# Mattermost settings
## Inside the container the uid and gid is 2000. The folder owner can be set with
## `sudo chown -R 2000:2000 ./volumes/app/mattermost`.
MATTERMOST_CONFIG_PATH=./volumes/app/mattermost/config
MATTERMOST_DATA_PATH=./volumes/app/mattermost/data
MATTERMOST_LOGS_PATH=./volumes/app/mattermost/logs
MATTERMOST_PLUGINS_PATH=./volumes/app/mattermost/plugins
MATTERMOST_CLIENT_PLUGINS_PATH=./volumes/app/mattermost/client/plugins
MATTERMOST_BLEVE_INDEXES_PATH=./volumes/app/mattermost/bleve-indexes

## Bleve index (inside the container)
MM_BLEVESETTINGS_INDEXDIR=/mattermost/bleve-indexes

## This will be 'mattermost-enterprise-edition' or 'mattermost-team-edition' based on the version of Mattermost you're installing.
MATTERMOST_IMAGE=mattermost-enterprise-edition
## Update the image tag if you want to upgrade your Mattermost version. You may also upgrade to the latest one. The example is based on the latest Mattermost ESR version.
MATTERMOST_IMAGE_TAG=9.11.6

## Make Mattermost container readonly. This interferes with the regeneration of root.html inside the container. Only use
## it if you know what you're doing.
## See https://github.com/mattermost/docker/issues/18
MATTERMOST_CONTAINER_READONLY=false

## The app port is only relevant for using Mattermost without the nginx container as reverse proxy. This is not meant
## to be used with the internal HTTP server exposed but rather in case one wants to host several services on one host
## or for using it behind another existing reverse proxy.
APP_PORT=8065

## Configuration settings for Mattermost. Documentation on the variables and the settings itself can be found at
## https://docs.mattermost.com/administration/config-settings.html
## Keep in mind that variables set here will take precedence over the same setting in config.json. This includes
## the system console as well and settings set with env variables will be greyed out.

## Below one can find necessary settings to spin up the Mattermost container
MM_SQLSETTINGS_DRIVERNAME=postgres
MM_SQLSETTINGS_DATASOURCE=postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_ENDPOINT}:5432/${POSTGRES_DB}?sslmode=disable&connect_timeout=10

## Example settings (any additional setting added here also needs to be introduced in the docker-compose.yml)
MM_SERVICESETTINGS_SITEURL=https://${DOMAIN}

EOF

# 'docker-compose.yml' 파일 수정
cat << "EOF" > docker-compose.yml
# https://docs.docker.com/compose/environment-variables/
services:
  mattermost:
    image: mattermost/${MATTERMOST_IMAGE}:${MATTERMOST_IMAGE_TAG}
    restart: ${RESTART_POLICY}
    security_opt:
      - no-new-privileges:true
    pids_limit: 200
    read_only: ${MATTERMOST_CONTAINER_READONLY}
    tmpfs:
      - /tmp
    volumes:
      - ${MATTERMOST_CONFIG_PATH}:/mattermost/config:rw
      - ${MATTERMOST_DATA_PATH}:/mattermost/data:rw
      - ${MATTERMOST_LOGS_PATH}:/mattermost/logs:rw
      - ${MATTERMOST_PLUGINS_PATH}:/mattermost/plugins:rw
      - ${MATTERMOST_CLIENT_PLUGINS_PATH}:/mattermost/client/plugins:rw
      - ${MATTERMOST_BLEVE_INDEXES_PATH}:/mattermost/bleve-indexes:rw
      # When you want to use SSO with GitLab, you have to add the cert pki chain of GitLab inside Alpine
      # to avoid Token request failed: certificate signed by unknown authority 
      # (link: https://github.com/mattermost/mattermost-server/issues/13059 and https://github.com/mattermost/docker/issues/34)
      # - ${GITLAB_PKI_CHAIN_PATH}:/etc/ssl/certs/pki_chain.pem:ro
    environment:
      # timezone inside container
      - TZ

      # necessary Mattermost options/variables (see env.example)
      - MM_SQLSETTINGS_DRIVERNAME
      - MM_SQLSETTINGS_DATASOURCE

      # necessary for bleve
      - MM_BLEVESETTINGS_INDEXDIR

      # additional settings
      - MM_SERVICESETTINGS_SITEURL
    ports:
      - 80:8065
      - ${CALLS_PORT}:${CALLS_PORT}/udp
      - ${CALLS_PORT}:${CALLS_PORT}/tcp

EOF

# Create the required directories and set their permissions.
mkdir -p ./volumes/app/mattermost/{config,data,logs,plugins,client/plugins,bleve-indexes}
chown -R 2000:2000 ./volumes/app/mattermost

# Deploy Mattermost.
docker-compose -f docker-compose.yml up -d
