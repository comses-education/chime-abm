FROM comses/osg-netlogo:6.2.2

ENV JAVA_HOME=/usr/local/openjdk-11

LABEL maintainer="CoMSES Net <support@comses.net>"

WORKDIR /code
COPY . /code
