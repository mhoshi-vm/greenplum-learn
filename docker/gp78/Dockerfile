FROM rockylinux:8

# Arguments & Env Vars
ARG GP_RELEASE_VERSION=7.8.1
# PXF moved to its own Pivnet product (greenplum-pxf) starting with GP 7.8.
# PXF 8 requires Java 17 or 21 (Java 8/11 are no longer supported).
ARG PXF_RELEASE_VERSION=8.0.0
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
    # GP 7.8 ships both PostGIS 2.5.4 and 3.3.2; pin to the 3.x package.
    pivnet download-product-files --accept-eula --product-slug=vmware-greenplum --release-version=${GP_RELEASE_VERSION} -g 'postgis-3*el8-x86_64.gppkg' -d /home/gpadmin && \
    # PXF: separate product (greenplum-pxf). Downloaded to /home/gpadmin so the
    # RPM cleanup in step 4 (which only touches ${PIVNET_DL_DIR}) leaves it.
    pivnet download-product-files --accept-eula --product-slug=greenplum-pxf --release-version=${PXF_RELEASE_VERSION} -g "pxf-gp${GP_MAJOR_VER}-*el8*.rpm" -d /home/gpadmin && \
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

# 5. Install MADlib & PostGIS payloads into GPHOME
# NOTE: GP7's 'gppkg' tool uses a bundled libssh2 that cannot complete an SSH
# handshake under Rosetta/amd64 emulation on Apple Silicon. It always fails with
# "[Session(-9)] Error waiting on socket" even when connecting to localhost
# (the plain OpenSSH client works, but gppkg does not use it). Because this is a
# single-host image, we unpack the gppkg payloads straight into GPHOME instead of
# running 'gppkg install', which avoids SSH entirely.
RUN SHAREDIR="$(${GPHOME}/bin/pg_config --sharedir)" && \
    # PostGIS: the payload tree (bin/lib/share/etc) maps straight into GPHOME
    tar xzf /home/gpadmin/postgis-3*-x86_64.gppkg -C ${GPHOME} bin lib share etc && \
    # MADlib: unwrap the outer tarball, then unpack the inner gppkg payload
    tar xzf /home/gpadmin/madlib-*el8-x86_64.tar.gz -C /home/gpadmin && \
    tar xzf /home/gpadmin/madlib-*/*.gppkg.tar.gz -C ${GPHOME} lib share && \
    # MADlib post-install (from its pkgspec): materialize madlib--*.sql from the
    # .sql.in templates and substitute the shared-library directory.
    find "${SHAREDIR}" -name 'madlib--*.sql.in' | awk '{ old=$0; sub(/.in$/, "", $0); printf "cp %s %s\n", old, $0 }' | sh && \
    find "${SHAREDIR}" -name 'madlib--*.sql' -exec sed -i "s#MADLIB_SHAREDIR#${SHAREDIR}/madlib/modules#g" {} + && \
    chown -R gpadmin:gpadmin /usr/local/greenplum-db* && \
    rm -rf /home/gpadmin/madlib-*/ /home/gpadmin/postgis-*.gppkg /home/gpadmin/madlib-*el8-x86_64.tar.gz

# 6. Install NLTK and common corpora
# plpython3u uses this same python3.11, so NLTK is callable from SQL. Bundle the
# punkt_tab tokenizer and the stopwords corpus (~15 MB) into gpadmin's NLTK data
# directory so the common functions work without a separate download.
RUN python3.11 -m ensurepip --default-pip && \
    python3.11 -m pip install nltk && \
    su gpadmin -c "python3.11 -m nltk.downloader -d /home/gpadmin/nltk_data punkt_tab stopwords"

# 7. Install PXF (Platform Extension Framework) + Java 21
# PXF is a JVM service, so it needs a JDK. The rpm was downloaded in step 3.
RUN yum -y install java-21-openjdk && \
    yum clean all && \
    rpm -Uvh /home/gpadmin/pxf-gp${GP_MAJOR_VER}-*.rpm && \
    rm -f /home/gpadmin/pxf-gp${GP_MAJOR_VER}-*.rpm && \
    chown -R gpadmin:gpadmin /usr/local/pxf-gp${GP_MAJOR_VER} && \
    echo "export GP_MAJOR_VER=${GP_MAJOR_VER}" >> /home/gpadmin/.bashrc && \
    echo "export JAVA_HOME=/usr/lib/jvm/jre-21" >> /home/gpadmin/.bashrc && \
    echo "export PXF_BASE=/usr/local/pxf-gp${GP_MAJOR_VER}" >> /home/gpadmin/.bashrc && \
    echo 'export PATH=$PATH:/usr/local/pxf-gp'"${GP_MAJOR_VER}"'/bin' >> /home/gpadmin/.bashrc

# 8. Build-Time Initialization
# NOTE: gpinitsystem can intermittently deadlock under Rosetta/amd64 emulation
# while restarting the cluster in production mode. Each attempt is therefore
# bounded by a timeout and retried from a clean slate, so an emulation hang
# fails fast and recovers instead of wedging the build forever.
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
    # Init System (bounded by a timeout, retried from a clean slate on hang)
    ( for attempt in 1 2 3; do \
        echo ">>> gpinitsystem attempt $attempt/3"; \
        if timeout -s KILL 420 su gpadmin -c "source /usr/local/greenplum-db/greenplum_path.sh; gpinitsystem -a -I /home/gpadmin/gpinitsystem_config"; then \
            echo ">>> gpinitsystem succeeded on attempt $attempt"; break; \
        fi; \
        if [ "$attempt" = "3" ]; then echo ">>> gpinitsystem failed after 3 attempts" >&2; exit 1; fi; \
        echo ">>> attempt $attempt hung/failed; cleaning up partial cluster before retry"; \
        pkill -9 -u gpadmin || true; sleep 2; \
        rm -rf ${COORDINATOR_DATA_DIRECTORY} /gpdata/primary/gpseg0 /home/gpadmin/gpAdminLogs/* /tmp/.s.PGSQL.* 2>/dev/null || true; \
        sleep 3; \
      done ) && \
    # Config Auth
    echo "host all all 0.0.0.0/0 trust" >> ${COORDINATOR_DATA_DIRECTORY}/pg_hba.conf && \
    # Enable MADlib & PostGIS in template1 so every database inherits them.
    # The package payloads were already unpacked into GPHOME in step 5.
    su gpadmin -c "source /usr/local/greenplum-db/greenplum_path.sh; psql -d template1 -c 'CREATE EXTENSION IF NOT EXISTS postgis;'" && \
    su gpadmin -c "source /usr/local/greenplum-db/greenplum_path.sh; psql -d template1 -c 'CREATE EXTENSION IF NOT EXISTS madlib CASCADE;'" && \
    # Register PXF (installs its extension into GPHOME and sets pxf.pxf_base),
    # then enable it in template1. PGDATABASE=template1 is used because no
    # gpadmin database exists yet; the PXF server itself is started at runtime
    # by the entrypoint, not here.
    su gpadmin -c "source /usr/local/greenplum-db/greenplum_path.sh; export JAVA_HOME=/usr/lib/jvm/jre-21 PXF_BASE=/usr/local/pxf-gp${GP_MAJOR_VER} PGDATABASE=template1; /usr/local/pxf-gp${GP_MAJOR_VER}/bin/pxf prepare; /usr/local/pxf-gp${GP_MAJOR_VER}/bin/pxf cluster register" && \
    su gpadmin -c "source /usr/local/greenplum-db/greenplum_path.sh; psql -d template1 -c 'CREATE EXTENSION IF NOT EXISTS pxf;'" && \
    # Create the gpadmin database (the default PGDATABASE) carrying all extensions.
    su gpadmin -c "source /usr/local/greenplum-db/greenplum_path.sh; createdb gpadmin" && \
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