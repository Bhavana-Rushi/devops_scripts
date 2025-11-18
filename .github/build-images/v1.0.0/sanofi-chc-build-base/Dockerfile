
FROM sanofi-docker-chc-tibco-local.jfrog.io/build-images/baseimage-tibco:2.8.1

LABEL MAINTAINER="Sanofi-CHC Devops"

ENV http_proxy "http://emea-aws-webproxy.service.cloud.local:3128"
ENV https_proxy "http://emea-aws-webproxy.service.cloud.local:3128"
ENV no_proxy "*.cloud.local,sanofi.com,docker"

User root

# Install Basic Packages
RUN apt-get update && DEBIAN_FRONTEND="noninteractive" apt-get install -y \
 apt-transport-https \
 software-properties-common \
 bash \
 vim \
 supervisor \
 git \
 openssh-server \
 locales \
 build-essential \
 curl \
 sudo \
 wget \
 jq \
 bc \
 locales \
 zip \
 tree \
 gettext-base \
 xmlstarlet \
 python3.9 \
 python3-dev \
 python3-pip \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - \
 && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu artful stable" \
 && apt-get update \
 && apt-get install -y docker-ce \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Python Packages
ADD requirements.txt /opt
RUN cd /opt; pip install -r requirements.txt

ENV JAVA_HOME /usr/lib/jvm/adoptopenjdk-11-hotspot-amd64
RUN export JAVA_HOME
ENV PATH /usr/lib/jvm/adoptopenjdk-11-hotspot-amd64/bin:$PATH
RUN export PATH
ENV no_proxy repo.maven.apache.org
RUN export no_proxy

RUN wget -qO - https://adoptopenjdk.jfrog.io/adoptopenjdk/api/gpg/key/public | sudo apt-key add -  && \
add-apt-repository --yes https://adoptopenjdk.jfrog.io/adoptopenjdk/deb/  &&\
apt-get update &&\
apt-get install -y adoptopenjdk-11-hotspot

RUN java -version

RUN curl -L https://archive.apache.org/dist/maven/maven-3/3.6.0/binaries/apache-maven-3.6.0-bin.tar.gz | tar zx -C /opt && \
ln -s /opt/apache-maven-3.6.0 /opt/maven && \
ln -s /opt/maven/bin/mvn /usr/bin/mvn

RUN mvn -v

COPY settings.xml /opt/apache-maven-3.6.0/conf/
RUN mkdir -p /root/.m2/repository
COPY settings.xml /root/.m2/

RUN curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.12.13/openshift-client-linux.tar.gz | tar zx -C /opt && \
mv /opt/oc /usr/bin && \
mv /opt/kubectl /usr/bin 

RUN oc version

CMD tail -f /dev/null
