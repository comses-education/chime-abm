FROM comses/osg-netlogo:6.3.0

LABEL maintainer="CoMSES Net <support@comses.net>"

RUN mkdir -p /srv/results

WORKDIR /code
COPY . /code
