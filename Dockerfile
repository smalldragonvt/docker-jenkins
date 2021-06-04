FROM ubuntu:focal

# Install git lfs on Debian stretch per https://github.com/git-lfs/git-lfs/wiki/Installation#debian-and-ubuntu
# Avoid JENKINS-59569 - git LFS 2.7.1 fails clone with reference repository
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get upgrade -y && apt-get install -y git vim curl openjdk-11-jdk && curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash && apt-get install -y git-lfs && git lfs install && rm -rf /var/lib/apt/lists/*

ARG USER
ARG GROUP
ARG UID
ARG GID
ARG HTTP_PORT
ARG AGENT_PORT
ARG JENKINS_HOME
ARG REF
ARG JENKINS_VERSION
ARG JENKINS_SHA

ENV USER=${USER:-cuong}
ENV GROUP=${GROUP:-cuong}
ENV UID=${UID:-1000}
ENV GID=${GID:-1000}
ENV HTTP_PORT=${HTTP_PORT:-8080}
ENV AGENT_PORT=${AGENT_PORT:-50000}
ENV JENKINS_HOME=${JENKINS_HOME:-/var/jenkins_home}
ENV JENKINS_SLAVE_AGENT_PORT=${AGENT_PORT:-50000}
ENV REF=${REF:-/usr/share/jenkins/ref}
ENV JENKINS_VERSION=${JENKINS_VERSION:-2.289.1}
ENV JENKINS_SHA=${JENKINS_SHA:-70f9cc6ff1ac59aeeb831b980709a9ddb0ee70d216ee50625a8508b9840f75f2}

# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container,
# ensure you use the same uid
RUN mkdir -p $JENKINS_HOME \
  && chown ${UID}:${GID} $JENKINS_HOME \
  && groupadd -g ${GID} ${GROUP} \
  && useradd -d "$JENKINS_HOME" -u ${UID} -g ${GID} -m -s /bin/bash ${USER}

# Jenkins home directory is a volume, so configuration and build history
# can be persisted and survive image upgrades
VOLUME ${JENKINS_HOME}

# $REF (defaults to `/usr/share/jenkins/ref/`) contains all reference configuration we want
# to set on a fresh new installation. Use it to bundle additional plugins
# or config file with your custom jenkins Docker image.
RUN mkdir -p ${REF}/init.groovy.d

# Use tini as subreaper in Docker container to adopt zombie processes
ARG TINI_VERSION=v0.16.1
COPY tini_pub.gpg ${JENKINS_HOME}/tini_pub.gpg
RUN curl -fsSL https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-$(dpkg --print-architecture) -o /sbin/tini \
  && curl -fsSL https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-$(dpkg --print-architecture).asc -o /sbin/tini.asc \
  && gpg --no-tty --import ${JENKINS_HOME}/tini_pub.gpg \
  && gpg --verify /sbin/tini.asc \
  && rm -rf /sbin/tini.asc /root/.gnupg \
  && chmod +x /sbin/tini

# jenkins version being bundled in this docker image

# jenkins.war checksum, download will be validated using it

# Can be used to customize where jenkins.war get downloaded from
ARG JENKINS_URL=https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war

# could use ADD but this one does not check Last-Modified header neither does it allow to control checksum
# see https://github.com/docker/docker/issues/8331
RUN curl -fsSL ${JENKINS_URL} -o /usr/share/jenkins/jenkins.war

ENV JENKINS_UC https://updates.jenkins.io
ENV JENKINS_UC_EXPERIMENTAL=https://updates.jenkins.io/experimental
ENV JENKINS_INCREMENTALS_REPO_MIRROR=https://repo.jenkins-ci.org/incrementals
ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log
RUN touch $JENKINS_HOME/copy_reference_file.log
RUN chown -R ${USER} "$JENKINS_HOME" "$REF"

# for main web interface:
EXPOSE ${HTTP_PORT}

# will be used by attached slave agents:
EXPOSE ${AGENT_PORT}

USER ${USER}

COPY jenkins-support /usr/local/bin/jenkins-support
COPY jenkins.sh /usr/local/bin/jenkins.sh
COPY tini-shim.sh /bin/tini
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/jenkins.sh"]

# from a derived Dockerfile, can use `RUN plugins.sh active.txt` to setup ${REF}/plugins from a support bundle
COPY plugins.sh /usr/local/bin/plugins.sh
COPY install-plugins.sh /usr/local/bin/install-plugins.sh
