# Headwind MDM V7 Docker image

Headwind MDM is an open source mobile device management software for Android
devices. This image runs Headwind MDM V7 on any Linux.

Headwind MDM project URL: https://h-mdm.com

## Summary

The image is based on Ubuntu 24.04, Tomcat 11 and Java 17 (Temurin).

The image contains the V7 shared libraries and the setup templates; the
Community or Premium WAR is downloaded at container startup and cached in the
persistent `volumes/work` directory.

The image does not include PostgreSQL and certbot, so they need to be started
in separate containers or on the host machine. As an alternative, you can use
Docker Compose to run Headwind MDM and all required packages (certbot,
PostgreSQL) on a fresh virtual machine with the most common options (see
below).

## Pull the image

The published image is available on Docker Hub:

    docker pull freepoint360/hmdm:7.03.3-ubuntu24-tomcat11

## Building the image from the source code

Before building the image, review the default variables (in particular the
Headwind MDM URL) in the Dockerfile and change them if required.

The build command is:

    docker build -t freepoint360/hmdm:7.03.3-ubuntu24-tomcat11 .

Build the Docker Compose service with:

    docker compose build hmdm

## Prerequisites

1. Create the PostgreSQL database for Headwind MDM, and use the environment
variables SQL_HOST, SQL_BASE, SQL_USER, SQL_PASS to define the database access
credentials.

Default values are: SQL_HOST=postgresql, SQL_PORT=5432, SQL_BASE=hmdm,
SQL_USER=hmdm, SQL_PASS=Ch@nGeMe

**Important: change SQL_PASS, SHARED_SECRET and SQL_USER before the first start
in production. The default values are publicly known.**

2. If you want to use HTTPS, install certbot and generate the certificate for
the domain where Headwind MDM should be installed.

    certbot certonly --standalone --force-renewal -d mdm.your-domain.com

## Running the Docker container

**Works with the external PostgreSQL database only. Default database
installation on localhost DOES NOT WORK!**

**Please set up your domain name when running Headwind MDM!**

To create the container, use the command:

    docker run -d -p 443:8443 -p 31000:31000 -e SQL_HOST=database.host -e SQL_PORT=5432 -e SQL_BASE=hmdm -e SQL_USER=hmdm -e SQL_PASS=password -e BASE_DOMAIN=mdm.your-domain.com -v /etc/letsencrypt:/etc/letsencrypt -v $(pwd)/volumes/work:/usr/local/tomcat/work --name="hmdm" freepoint360/hmdm:7.03.3-ubuntu24-tomcat11

If everything is fine, Headwind MDM will become available via the url
`https://mdm.your-domain.com` in a few seconds.

To view logs, use the command:

    docker logs hmdm

Stop and start the container:

    docker stop hmdm
    docker start hmdm

Connect to the container for debugging:

    docker exec -it hmdm /bin/bash

## Configuration of Headwind MDM

The container is configured by the environment variables.

The full list of variables can be found in the Dockerfile.

## First start and subsequent starts

At first start, Headwind MDM performs the initialization:

  - Downloads the WAR and the mobile client files
  - Creates the config files using the environment
  - Initializes the database
  - Converts the LetsEncrypt's (or your own) SSL certificates to a JKS keystore

Subsequent starts of the container skip this step, but you can force the
configuration renewal by setting the following environment variable:

FORCE_RECONFIGURE=true

When this variable is set to true, the configuration is always re-created by
the Headwind MDM entry point script.

<a id="quickstart"></a>
## Running with the most common options by Docker Compose

Docker Compose requires just two files to start Headwind MDM:

    .env
    docker-compose.yaml

For a simple start of Headwind MDM on a fresh virtual machine, run the
following commands. Install the Docker Compose plugin if it is not already
available.

    apt install -y docker-compose-plugin
    cd hmdm-docker-v7
    cp .env.example .env
    vim .env              # Replace ADMIN_EMAIL, BASE_DOMAIN to your values
    docker compose up

The command `docker compose up` will start Headwind MDM in the interactive
mode where you can easily trace and fix errors.

Once Headwind MDM start is successful, you can start it in the background
(detached) mode by using the command:

    docker compose up -d

To view logs, use the command:

    docker compose logs hmdm -f

To stop (but not remove) the service, use the command:

    docker compose stop

The certbot service requests the LetsEncrypt certificate in the standalone
mode on the first start, so port 80 must be free and the domain must point to
the server. The hmdm container waits for the certificate before starting
Tomcat.

## Community version

The Community version is enabled by default. Keep `HMDM_VARIANT=os`, leave
`DOWNLOAD_CREDENTIALS` empty, and use the Community `HMDM_URL` from
`.env.example`.

## Ubuntu 24.04 and Tomcat 11

The image uses Ubuntu 24.04 (Noble), Tomcat 11 and Java 17 (Temurin), and is
published as `freepoint360/hmdm:7.03.3-ubuntu24-tomcat11`.

## Updating the software

To update Headwind MDM web panel, sign in, and download the new version through
**admin -> check for updates** (click "Update" to download updates).

Once the update is downloaded, restart the container - it should install the
new version.

    docker compose restart hmdm

Notice: using start and stop instead of restart WILL NOT run the update.

In the browser, reload the Headwind MDM web application (Ctrl-F5 in Chrome),
and check the version through **admin -> About**. If you still see the old
version, try clearing the browser cache.

To update both Headwind MDM and Tomcat services, compare the version of the
hmdm container in docker-compose.yaml with the latest tag at Docker Hub.
If your version is outdated, update the version number in docker-compose.yaml
and pull the changes:

    docker compose pull
    docker compose up -d

## Attaching to the container

You may need to attach to the container to change the Headwind MDM
configuration in order to adjust some advanced settings.

To find the container ID, use the command

    docker ps

Find the container ID of the image `freepoint360/hmdm:7.03.3-ubuntu24-tomcat11`, then run the
command

    docker exec -it containerid /bin/bash

For example:

    docker exec -it e81d47acec21 /bin/bash

Notice: the container needs to be started before attaching to it.

## Resetting the container

If something goes wrong, you may wish to reset the container and reinstall it
from scratch. The command

    docker compose down

may not be enough, as it doesn't clear the downloaded files and initialized
database.

To wipe all data, remove all entries in the `volumes` subdirectory:

    rm -rf volumes/db volumes/work

(we recommend to keep the `volumes/letsencrypt` subdirectory to avoid problems
with exceeding the LetsEncrypt certificate generation threshold).

As an alternative, you can set the parameter in the .env file:

    FORCE_RECONFIGURE=true

Important: this parameter should be unset after the initial setup, otherwise
you may lose the application settings.

## Persistence

The PostgreSQL database and application files are persisted under `volumes/`.
The Headwind MDM config file is mapped to `volumes/hmdm-config/ROOT.xml`.
Restarting the container applies the changes. To avoid loss of changes, make
sure the `FORCE_RECONFIGURE` flag is not set in the `.env` file (this flag
forces the container to reset the XML config file to its default state).

## Using custom SSL certificates in Docker Compose

To use custom SSL certificates

- Comment out the whole certbot: section in docker-compose.yaml
- Create the subdirectory ./volumes/letsencrypt/live/your-domain.com/
- Copy the private key, certificate, and full certificate chain
- in the PEM (base64) format to that subdirectory. Use the following names:
- cert.pem, fullchain.pem, privkey.pem

To use plain HTTP, edit the contents of the docker-compose.yaml:

- Comment out the certbot: section
- Set the environment variable in the .env file: PROTOCOL=http

## Versions

The image tag follows the Docker image version (`7.03.3`), while the web
application version is defined by `HMDM_URL` and `CLIENT_VERSION` in the
`.env` file. The default Community URL downloads the WAR `7.03.3`, which is
tested with this image; the Premium build is available for the version
matching your license.

## License

The project is distributed under the Apache License 2.0, see `LICENSE`. Third
party libraries in `lib/` are distributed under their own licenses.
# hmdm-v7-docker
