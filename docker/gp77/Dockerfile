FROM rockylinux:8

# Arguments & Env Vars
ARG GP_RELEASE_VERSION=7.7.0
# Token removed from default. Must be passed via --build-arg
ARG PIVNET_API_TOKEN

ENV GP_MAJOR_VER=7
ENV GPHOME=/usr/local/greenplum-db
ENV COORDINATOR_DATA_DIRECTORY=/gpdata/coordinator/gpseg-1
ENV PIVNET_DL_DIR=/home/gpadmin/gp_downloads

# 1. OS Setup & Dependencies
# Added 'libtiff' and 'libxml2' to fix PostGIS pre-install hook error
RUN dnf install -y epel-release && \
    dnf install -y openssh-server openssh-clients sudo which iproute net-tools \
    python39 python39-pip wget tar gzip unzip less apr apr-util libevent libyaml procps-ng \
    libtiff libxml2 && \
    dnf clean all

# 2. User & SSH Setup
RUN groupadd gpadmin && \
    useradd -g gpadmin -m -s /bin/bash gpadmin && \
    echo "gpadmin ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    ssh-keygen -A && \
    mkdir -p /home/gpadmin/.ssh && \
    ssh-keygen -t rsa -b 4096 -f /home/gpadmin/.ssh/id_rsa -N "" && \
    cat /home/gpadmin/.ssh/id_rsa.pub >> /home/gpadmin/.ssh/authorized_keys && \
    chmod 700 /home/gpadmin/.ssh && \
    chmod 600 /home/gpadmin/.ssh/authorized_keys && \
    chown -R gpadmin:gpadmin /home/gpadmin/.ssh && \
    echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config

# 3. Download Binaries & Cleanup .pivnetrc
RUN mkdir -p ${PIVNET_DL_DIR} && \
    wget -O /usr/local/bin/pivnet https://github.com/pivotal-cf/pivnet-cli/releases/download/v4.1.1/pivnet-linux-amd64-4.1.1 && \
    chmod +x /usr/local/bin/pivnet && \
    pivnet login --api-token=${PIVNET_API_TOKEN} && \
    pivnet download-product-files --accept-eula --product-slug='vmware-greenplum' --release-version=${GP_RELEASE_VERSION} -g "greenplum-db-${GP_RELEASE_VERSION}-*el8-*" -d ${PIVNET_DL_DIR} && \
    pivnet download-product-files --accept-eula --product-slug=vmware-greenplum --release-version=${GP_RELEASE_VERSION} -g 'madlib*el8-x86_64.tar.gz' -d /home/gpadmin && \
    pivnet download-product-files --accept-eula --product-slug=vmware-greenplum --release-version=${GP_RELEASE_VERSION} -g 'postgis*el8-x86_64.gppkg' -d /home/gpadmin && \
    chown -R gpadmin:gpadmin /home/gpadmin && \
    rm -f $HOME/.pivnetrc

# 4. Install RPMs & Prepare Dirs
RUN yum -y install ${PIVNET_DL_DIR}/greenplum-db-*.rpm && \
    chown -R gpadmin:gpadmin /usr/local/greenplum-db* && \
    rm -rf ${PIVNET_DL_DIR}/*.rpm && \
    echo "source /usr/local/greenplum-db/greenplum_path.sh" >> /home/gpadmin/.bashrc && \
    echo "export COORDINATOR_DATA_DIRECTORY=${COORDINATOR_DATA_DIRECTORY}" >> /home/gpadmin/.bashrc && \
    echo "export PGDATABASE=gpadmin" >> /home/gpadmin/.bashrc && \
    mkdir -p /gpdata/coordinator /gpdata/primary /var/run/sshd && \
    chown -R gpadmin:gpadmin /gpdata

# 5. Install NLTK
RUN python3.11 -m ensurepip --default-pip && \
    python3.11 -m pip install nltk

# 6. Build-Time Initialization
RUN rm -rf /run/nologin && \
    # --- MOCK PING START ---
    mv /usr/bin/ping /usr/bin/ping.orig && \
    echo '#!/bin/bash' > /usr/bin/ping && \
    echo 'exit 0' >> /usr/bin/ping && \
    chmod +x /usr/bin/ping && \
    # --- MOCK PING END ---
    BUILD_HOSTNAME=$(hostname) && \
    echo $BUILD_HOSTNAME > /home/gpadmin/.build_hostname && \
    echo "ARRAY_NAME='Greenplum Data Platform'" > /home/gpadmin/gpinitsystem_config && \
    echo "TRUSTED_SHELL=ssh" >> /home/gpadmin/gpinitsystem_config && \
    echo "CHECK_POINT_SEGMENTS=8" >> /home/gpadmin/gpinitsystem_config && \
    echo "ENCODING=UNICODE" >> /home/gpadmin/gpinitsystem_config && \
    echo "SEG_PREFIX=gpseg" >> /home/gpadmin/gpinitsystem_config && \
    echo "HEAP_CHECKSUM=on" >> /home/gpadmin/gpinitsystem_config && \
    echo "HBA_HOSTNAMES=0" >> /home/gpadmin/gpinitsystem_config && \
    echo "QD_PRIMARY_ARRAY=$BUILD_HOSTNAME~$BUILD_HOSTNAME~5432~${COORDINATOR_DATA_DIRECTORY}~0~-1" >> /home/gpadmin/gpinitsystem_config && \
    echo "declare -a PRIMARY_ARRAY=($BUILD_HOSTNAME~$BUILD_HOSTNAME~6000~/gpdata/primary/gpseg0~1~0)" >> /home/gpadmin/gpinitsystem_config && \
    # Start SSHD
    /usr/sbin/sshd && \
    # Init System
    su gpadmin -c "source /usr/local/greenplum-db/greenplum_path.sh; gpinitsystem -a -I /home/gpadmin/gpinitsystem_config" && \
    # Config Auth
    echo "host all all 0.0.0.0/0 trust" >> ${COORDINATOR_DATA_DIRECTORY}/pg_hba.conf && \
    # Install Extensions & Config
    # Extract MADlib (tarball is needed for gppkg)
    tar xzvf /home/gpadmin/madlib*el8-x86_64.tar.gz -C /home/gpadmin && \
    # Install MADlib
    su gpadmin -c "source /usr/local/greenplum-db/greenplum_path.sh; gppkg install -a /home/gpadmin/madlib*/*.gppkg.tar.gz" && \
    # Install PostGIS
    su gpadmin -c "source /usr/local/greenplum-db/greenplum_path.sh; gppkg install -a /home/gpadmin/postgis*.gppkg" && \
    # Final Shutdown
    su gpadmin -c "source /usr/local/greenplum-db/greenplum_path.sh; gpstop -a" && \
    # Cleanup
    pkill sshd && \
    # Restore Ping
    mv /usr/bin/ping.orig /usr/bin/ping

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN rm -f $COORDINATOR_DATA_DIRECTORY/log/*

EXPOSE 5432
USER gpadmin
WORKDIR /home/gpadmin
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]