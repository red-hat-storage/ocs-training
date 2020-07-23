FROM centos:latest
MAINTAINER JCL <jelopez@redhat.com>

RUN yum -y update && \
    yum install -y https://repo.percona.com/yum/percona-release-latest.noarch.rpm && \
    yum install -y git make gcc unzip wget sysbench

RUN mkdir /tmp/data

WORKDIR /tmp/data

COPY ./file-*.sh /tmp/

RUN chmod +x /tmp/*.sh

CMD ["/bin/bash","-c","sleep 3600"]
