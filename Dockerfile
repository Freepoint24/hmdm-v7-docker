# syntax=docker/dockerfile:1

FROM tomcat:11.0-jdk17-temurin-noble

RUN apt-get update \
    && apt-get install -y --no-install-recommends aapt postgresql-client wget \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /usr/local/tomcat/conf/Catalina/localhost /usr/local/tomcat/ssl /opt/hmdm/lib /usr/local/tomcat/work/cache

COPY lib/ /usr/local/tomcat/lib/
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY update-web-app-docker.sh /opt/hmdm/update-web-app-docker.sh
COPY tomcat_conf/server.xml /usr/local/tomcat/conf/server.xml
COPY templates/ /opt/hmdm/templates/

ENV FORCE_RECONFIGURE= \
    INSTALL_LANGUAGE=en \
    ADMIN_EMAIL= \
    HMDM_VARIANT=os \
    CLIENT_VARIANT=os \
    DOWNLOAD_CREDENTIALS= \
    HMDM_URL=https://h-mdm.com/files/hmdm-7.03.3-os.war \
    CLIENT_VERSION=6.40 \
    SQL_HOST=postgresql \
    SQL_PORT=5432 \
    SQL_BASE=hmdm \
    SQL_USER=hmdm \
    SQL_PASS=Ch@nGeMe \
    PROTOCOL=https \
    BASE_DOMAIN=your-domain.com \
    BASE_PATH= \
    SHARED_SECRET=changeme-C3z9vi54 \
    HTTPS_LETSENCRYPT=true \
    HTTPS_CERT=cert.pem \
    HTTPS_FULLCHAIN=fullchain.pem \
    HTTPS_PRIVKEY=privkey.pem

EXPOSE 8080 8443 31000

ENTRYPOINT ["/docker-entrypoint.sh"]
