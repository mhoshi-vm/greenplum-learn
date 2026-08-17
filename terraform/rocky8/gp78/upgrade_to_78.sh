#!/bin/bash
#
# In-place upgrade of an already deployed Greenplum cluster (gp77 and older
# rocky8 terraform deploys) to the gp78 state: Greenplum 7.8.3, GPCC 7.7.3 and
# every add-on the gp78 templates install.
#
# Run as root on cdw. Segment hosts are driven over gpssh/gpsync, they do not
# need internet access, everything is downloaded here and pushed out.
#
#   export PIVNET_API_TOKEN=<token>
#   ./upgrade_to_78.sh
#
# The database is stopped for the rpm swap. Take a backup first.
#
# Every step is idempotent and re-runnable. To resume after a failure:
#   ./upgrade_to_78.sh --only gpcc,pxf,gpcopy
# To list the step names:
#   ./upgrade_to_78.sh --list
#
set -eEuo pipefail

##########################################
# Target versions, keep in sync with common.tf
##########################################
GP_RELEASE_VERSION="${GP_RELEASE_VERSION:-7.8.3}"
GPCC_RELEASE_VERSION="${GPCC_RELEASE_VERSION:-7.7.3}"
GPCOPY_RELEASE_VERSION="${GPCOPY_RELEASE_VERSION:-2.8.0}"
PXF_PRODUCT_SLUG="${PXF_PRODUCT_SLUG:-greenplum-pxf}"
PXF_RELEASE_VERSION="${PXF_RELEASE_VERSION:-8.0.2}"
GPTEXT_PRODUCT_SLUG="${GPTEXT_PRODUCT_SLUG:-greenplum-text}"
GPTEXT_RELEASE_VERSION="${GPTEXT_RELEASE_VERSION:-3.10.1}"
PIVNET_URL="${PIVNET_URL:-https://github.com/pivotal-cf/pivnet-cli/releases/download/v4.1.1/pivnet-linux-amd64-4.1.1}"

DOWNLOAD_DIR=/home/gpadmin/gp_downloads
HOSTS_ALL=/home/gpadmin/hosts-all
HOSTS_SEGMENTS=/home/gpadmin/hosts-segments
GPHOME=/usr/local/greenplum-db
NEW_GPHOME="/usr/local/greenplum-db-${GP_RELEASE_VERSION}"
GPCC_HOME=/usr/local/greenplum-cc
NEW_GPCC_HOME="/usr/local/greenplum-cc-${GPCC_RELEASE_VERSION}"
LOG=/var/log/gp78_upgrade.log

ALL_STEPS=(preflight download stop os db start gpdr gpcc pxf gpcopy dsp madlib postgis plr gptext gpmlbot finish)
# The core upgrade fails fast. The add-ons only warn, one broken package should
# not leave the rest of the cluster half configured, resume them with --only.
OPTIONAL_STEPS=(gpdr gpcc pxf gpcopy dsp madlib postgis plr gptext gpmlbot)
ONLY=""
SKIP=""
ASSUME_YES=0

##########################################
# helpers
##########################################
log()  { echo -e "\n[$(date '+%F %T')] $*"; }
warn() { echo "[$(date '+%F %T')] WARNING: $*" >&2; }
die()  { echo "[$(date '+%F %T')] ERROR: $*" >&2; exit 1; }

trap 'rc=$?; [ $rc -ne 0 ] && echo "ERROR: line $LINENO exited with $rc, rerun with --only <step> after fixing" >&2' ERR

# Run a script fragment as gpadmin. Feed it on stdin, unquoted heredocs expand
# here first so the target versions land in the fragment.
as_gpadmin() {
  local tmp rc=0
  tmp=$(mktemp /tmp/gp78_upgrade_XXXXXX.sh)
  cat > "$tmp"
  chmod 755 "$tmp"
  su - gpadmin -c "bash $tmp" || rc=$?
  rm -f "$tmp"
  return $rc
}

# Download a product file unless it is already in DOWNLOAD_DIR. The glob works
# for both pivnet and ls.
fetch() {
  local slug=$1 version=$2 glob=$3
  if ls "$DOWNLOAD_DIR"/$glob >/dev/null 2>&1; then
    echo "  already downloaded: $glob"
    return 0
  fi
  pivnet download-product-files --accept-eula --product-slug="$slug" \
    --release-version="$version" -g "$glob" -d "$DOWNLOAD_DIR" \
    || warn "no product file matched '$glob' in $slug $version"
}

have() { ls $1 >/dev/null 2>&1; }

segments() { cat "$HOSTS_SEGMENTS"; }

selected() {
  local step=$1
  [[ -n "$SKIP" && ",$SKIP," == *",$step,"* ]] && return 1
  [[ -z "$ONLY" ]] && return 0
  [[ ",$ONLY," == *",$step,"* ]]
}

optional() {
  local step=$1 s
  for s in "${OPTIONAL_STEPS[@]}"; do [[ "$s" == "$step" ]] && return 0; done
  return 1
}

##########################################
# steps
##########################################
step_preflight() {
  [[ $EUID -eq 0 ]] || die "run as root on cdw"
  [[ "$(hostname -s)" == "cdw" ]] || die "run on cdw, this host is $(hostname -s)"
  id gpadmin >/dev/null 2>&1 || die "no gpadmin user, this is not a deployed coordinator"
  [[ -f "$HOSTS_ALL" && -f "$HOSTS_SEGMENTS" ]] || die "missing $HOSTS_ALL / $HOSTS_SEGMENTS"
  [[ -n "${PIVNET_API_TOKEN:-}" ]] || die "export PIVNET_API_TOKEN=<token> first"

  CURRENT_GPHOME=$(readlink -f "$GPHOME")
  CURRENT_VERSION="${CURRENT_GPHOME##*greenplum-db-}"
  CURRENT_GPCC=$(readlink -f "$GPCC_HOME" 2>/dev/null || echo "none")

  log "current  : GPDB $CURRENT_VERSION ($CURRENT_GPHOME), GPCC $CURRENT_GPCC"
  log "target   : GPDB $GP_RELEASE_VERSION, GPCC $GPCC_RELEASE_VERSION"
  log "segments : $(segments | tr '\n' ' ')"

  as_gpadmin <<'EOS' || die "cluster is not healthy, fix that before upgrading"
source /usr/local/greenplum-db/greenplum_path.sh
gpstate -s >/dev/null
EOS

  # Only worth asking when this run actually takes the database down
  if [[ $ASSUME_YES -eq 0 ]] && { selected stop || selected db; }; then
    echo
    echo "This stops the database and replaces the Greenplum rpm on every host."
    read -r -p "Continue? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || die "aborted"
  fi
}

step_download() {
  if ! command -v pivnet >/dev/null 2>&1; then
    wget -O /usr/local/bin/pivnet "$PIVNET_URL"
    chmod +x /usr/local/bin/pivnet
  fi
  pivnet login --api-token="$PIVNET_API_TOKEN"

  mkdir -p "$DOWNLOAD_DIR"

  fetch vmware-greenplum      "$GP_RELEASE_VERSION"     "greenplum-db-${GP_RELEASE_VERSION}-*el8-*.rpm"
  fetch vmware-greenplum      "$GP_RELEASE_VERSION"     "greenplum-db-clients-${GP_RELEASE_VERSION}-*el8-*.rpm"
  fetch vmware-greenplum      "$GP_RELEASE_VERSION"     "greenplum-disaster-recovery*el8*.rpm"
  fetch gpdb-command-center   "$GPCC_RELEASE_VERSION"   "greenplum-cc-web-*el8-*.zip"
  fetch gpdb-data-copy        "$GPCOPY_RELEASE_VERSION" "gpcopy-*.tar.gz"
  fetch "$PXF_PRODUCT_SLUG"   "$PXF_RELEASE_VERSION"    "pxf-gp7-*el8*.rpm"
  fetch vmware-greenplum      "$GP_RELEASE_VERSION"     "DataSciencePython*el8_x86_64.gppkg"
  fetch vmware-greenplum      "$GP_RELEASE_VERSION"     "madlib*el8-x86_64.tar.gz"
  fetch vmware-greenplum      "$GP_RELEASE_VERSION"     "postgis*el8-x86_64.gppkg"
  fetch vmware-greenplum      "$GP_RELEASE_VERSION"     "plr*gp7-rhel8-x86_64.gppkg"
  fetch "$GPTEXT_PRODUCT_SLUG" "$GPTEXT_RELEASE_VERSION" "greenplum-text*el8_x86_64.tar.gz"

  chown -R gpadmin:gpadmin "$DOWNLOAD_DIR"
}

step_stop() {
  as_gpadmin <<'EOS' || warn "gpcc was not running"
source /usr/local/greenplum-db/greenplum_path.sh
source /usr/local/greenplum-cc/gpcc_path.sh
gpcc stop
EOS

  as_gpadmin <<'EOS'
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gpstop -M fast -a
EOS
}

# Rocky Linux 8 package refresh, same 'yum update -y' the deploy does on every
# node. Runs with the database down. Segments go out through the squid proxy on
# cdw, which is already in their /etc/yum.conf.
step_os() {
  log "updating Rocky Linux 8 packages on the coordinator"
  yum -y update

  log "updating Rocky Linux 8 packages on the segment hosts"
  as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gpssh -f $HOSTS_SEGMENTS -e "sudo yum -y update"
EOS

  # A kernel or glibc update needs a reboot, but rebooting the cluster is the
  # operator's call, so only report it
  yum -y install yum-utils >/dev/null 2>&1 || true
  log "reboot check"
  needs-restarting -r || warn "cdw needs a reboot to finish the OS update"
  as_gpadmin <<EOS || true
source /usr/local/greenplum-db/greenplum_path.sh
gpssh -f $HOSTS_SEGMENTS -e "sudo needs-restarting -r || echo 'REBOOT REQUIRED'"
EOS
  log "if any host reports a reboot, do it now (gpstop first) and rerun with --skip download,os"
}

step_db() {
  if [[ "$(readlink -f "$GPHOME")" == "$NEW_GPHOME" ]]; then
    log "GPDB is already $GP_RELEASE_VERSION, skipping the rpm swap"
    return 0
  fi

  local rpm clients_rpm
  rpm=$(ls "$DOWNLOAD_DIR"/greenplum-db-${GP_RELEASE_VERSION}-*el8*.rpm | head -1)
  clients_rpm=$(ls "$DOWNLOAD_DIR"/greenplum-db-clients-${GP_RELEASE_VERSION}-*el8*.rpm | head -1)

  # Segments first, while the coordinator still has its old gpssh/gpsync
  log "pushing $(basename "$rpm") to the segment hosts"
  as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gpssh -f $HOSTS_SEGMENTS -e "mkdir -p $DOWNLOAD_DIR"
gpsync -f $HOSTS_SEGMENTS $rpm =:$DOWNLOAD_DIR/
gpssh -f $HOSTS_SEGMENTS -e "sudo yum -y install $DOWNLOAD_DIR/$(basename "$rpm")"
gpssh -f $HOSTS_SEGMENTS -e "sudo chown -R gpadmin:gpadmin /usr/local/greenplum-db*"
gpssh -f $HOSTS_SEGMENTS -e "sudo chgrp -R gpadmin /usr/local/greenplum-db*"
EOS

  log "installing on the coordinator"
  yum -y install "$rpm"
  yum -y install "$clients_rpm"
  chown -R gpadmin:gpadmin /usr/local/greenplum-db*
  chgrp -R gpadmin /usr/local/greenplum-db*

  [[ "$(readlink -f "$GPHOME")" == "$NEW_GPHOME" ]] \
    || die "$GPHOME still points at $(readlink -f "$GPHOME"), expected $NEW_GPHOME"

  # The proxy config lives inside GPHOME, so the new install needs it again
  log "restoring the segment proxy environment"
  cat > /tmp/20-proxy.conf <<'EOS'
export http_proxy=http://cdw:3128
export https_proxy=http://cdw:3128
export no_proxy=localhost,127.0.0.1
EOS
  chmod 644 /tmp/20-proxy.conf
  as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gpssh -f $HOSTS_SEGMENTS -e "mkdir -p $GPHOME/etc/environment.d"
gpsync -f $HOSTS_SEGMENTS /tmp/20-proxy.conf =:$GPHOME/etc/environment.d/20-proxy.conf
EOS
  rm -f /tmp/20-proxy.conf
}

step_start() {
  as_gpadmin <<'EOS'
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gpstart -a
psql -d postgres -c "select version()"
EOS
}

step_gpdr() {
  have "$DOWNLOAD_DIR/greenplum-disaster-recovery*" || { warn "no gpdr rpm downloaded, skipping"; return 0; }
  local rpm
  rpm=$(ls "$DOWNLOAD_DIR"/greenplum-disaster-recovery*.rpm | head -1)

  as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gpsync -f $HOSTS_SEGMENTS $rpm =:$DOWNLOAD_DIR/
gpssh -f $HOSTS_SEGMENTS -e "sudo rpm -Uvh --replacepkgs $DOWNLOAD_DIR/$(basename "$rpm")"
gpssh -f $HOSTS_SEGMENTS -e "sudo chown -R gpadmin:gpadmin /usr/local/gpdr"
EOS
  rpm -Uvh --replacepkgs "$rpm"
  chown -R gpadmin:gpadmin /usr/local/gpdr
}

step_gpcc() {
  # metrics_collector lives inside GPHOME, a GPDB upgrade always takes it with
  # it, so GPCC has to be installed again against the new GPHOME
  log "preparing $NEW_GPCC_HOME on every host"
  mkdir -p "$NEW_GPCC_HOME"
  chown -R gpadmin:gpadmin "$NEW_GPCC_HOME"
  ln -sfn "$NEW_GPCC_HOME" "$GPCC_HOME"
  chown -h gpadmin:gpadmin "$GPCC_HOME"

  # Segment side has to exist before gpccinstall runs, gpadmin cannot create it
  # under /usr/local itself. This is what left the agents dead on the 08-12 run.
  as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gpssh -f $HOSTS_SEGMENTS -e "sudo mkdir -p $NEW_GPCC_HOME"
gpssh -f $HOSTS_SEGMENTS -e "sudo chown -R gpadmin:gpadmin $NEW_GPCC_HOME"
gpssh -f $HOSTS_SEGMENTS -e "sudo ln -sfn $NEW_GPCC_HOME $GPCC_HOME"
gpssh -f $HOSTS_SEGMENTS -e "sudo chown -h gpadmin:gpadmin $GPCC_HOME"
EOS

  # Carry the old web certificate over, or make a fresh self signed one
  if [[ ! -f "$NEW_GPCC_HOME/server.pem" ]]; then
    local old_pem
    old_pem=$(ls /usr/local/greenplum-cc-*/server.pem 2>/dev/null | grep -v "$NEW_GPCC_HOME" | head -1 || true)
    if [[ -n "$old_pem" ]]; then
      cp "$old_pem" "$NEW_GPCC_HOME/server.pem"
    else
      openssl req -newkey rsa:2048 -nodes -keyout /tmp/domain.key -out /tmp/domain.csr -subj "/CN=localhost"
      openssl req -key /tmp/domain.key -new -x509 -days 3650 -out /tmp/domain.crt -subj "/CN=localhost"
      cat /tmp/domain.key /tmp/domain.crt > "$NEW_GPCC_HOME/server.pem"
      rm -f /tmp/domain.key /tmp/domain.csr /tmp/domain.crt
      [[ -s "$NEW_GPCC_HOME/server.pem" ]] || die "could not generate $NEW_GPCC_HOME/server.pem"
    fi
    chown gpadmin:gpadmin "$NEW_GPCC_HOME/server.pem"
  fi

  cat > /home/gpadmin/gpcc_config <<EOS
path = /usr/local
master_port = 5432
web_port = 28080
rpc_port = 8899
enable_ssl = true
ssl_cert_file = $GPCC_HOME/server.pem
enable_kerberos = false
enable_grpc_tls = false
# User interface language: 1=English, 2=Chinese, 3=Korean, 4=Russian, 5=Japanese
language = 5
EOS
  chown gpadmin:gpadmin /home/gpadmin/gpcc_config

  rm -rf /home/gpadmin/greenplum-cc-web-${GPCC_RELEASE_VERSION}-*
  # gpccinstall prompts for the mTLS settings, it is the last command in the
  # fragment on purpose so the prompts hit EOF and take their defaults
  as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gpconfig -c shared_preload_libraries -v 'metrics_collector'
unzip -o $DOWNLOAD_DIR/greenplum-cc-web-*.zip -d /home/gpadmin/
gpstop -M fast -r -a
cd /home/gpadmin/greenplum-cc-web-${GPCC_RELEASE_VERSION}-*
./gpccinstall-${GPCC_RELEASE_VERSION} -c /home/gpadmin/gpcc_config
EOS

  if ! have "$NEW_GPHOME/lib/postgresql/metrics_collector.so"; then
    log "installing the metrics_collector gppkg into $NEW_GPHOME"
    as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
source $GPCC_HOME/gpcc_path.sh
cd $GPCC_HOME/gppkg
gppkg install -a \$(ls *${GPCC_RELEASE_VERSION}* | tail -1)
EOS
  fi

  # Pin the grpc listener to the coordinator interface
  grep -q '^grpc_ip_allowlist' "$NEW_GPCC_HOME/conf/app.conf" \
    || echo 'grpc_ip_allowlist = cdw' >> "$NEW_GPCC_HOME/conf/app.conf"

  as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
source $GPCC_HOME/gpcc_path.sh
gpcc start
gpcc status
EOS
}

step_pxf() {
  have "$DOWNLOAD_DIR/pxf-gp7-*.rpm" || { warn "no pxf rpm downloaded, skipping"; return 0; }
  local rpm
  rpm=$(ls "$DOWNLOAD_DIR"/pxf-gp7-*.rpm | head -1)

  log "installing $(basename "$rpm") on every host"
  yum -y install java-11-openjdk.x86_64
  rpm -Uvh --replacepkgs "$rpm"

  as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gpsync -f $HOSTS_SEGMENTS $rpm =:$DOWNLOAD_DIR/
gpssh -f $HOSTS_SEGMENTS -e "sudo yum -y install java-11-openjdk.x86_64"
gpssh -f $HOSTS_SEGMENTS -e "sudo rpm -Uvh --replacepkgs $DOWNLOAD_DIR/$(basename "$rpm")"
gpssh -f $HOSTS_ALL -e "sudo chown -R gpadmin:gpadmin /usr/local/pxf-gp7"
EOS

  for var in 'export GP_MAJOR_VER=7' \
             'export PATH=$PATH:/usr/local/pxf-gp7/bin' \
             'export JAVA_HOME=/usr/lib/jvm/jre' \
             'export PXF_BASE=/usr/local/pxf-gp7'; do
    grep -qxF "$var" /home/gpadmin/.bashrc || echo "$var" >> /home/gpadmin/.bashrc
  done

  # register copies the pxf extension files into the new GPHOME
  as_gpadmin <<'EOS' || warn "pxf register/start failed, check pxf cluster status"
set -x
source /usr/local/greenplum-db/greenplum_path.sh
export JAVA_HOME=/usr/lib/jvm/jre
export PXF_BASE=/usr/local/pxf-gp7
/usr/local/pxf-gp7/bin/pxf cluster register
/usr/local/pxf-gp7/bin/pxf cluster start
EOS
}

step_gpcopy() {
  have "$DOWNLOAD_DIR/gpcopy-*.tar.gz" || { warn "no gpcopy tarball downloaded, skipping"; return 0; }

  tar xzf "$DOWNLOAD_DIR"/gpcopy-*.tar.gz -C /home/gpadmin
  cp /home/gpadmin/gpcopy-*/gpcopy* "$GPHOME/bin/"
  chmod 755 "$GPHOME"/bin/gpcopy*
  chown gpadmin:gpadmin "$GPHOME"/bin/gpcopy*

  as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gpsync -f $HOSTS_SEGMENTS $GPHOME/bin/gpcopy_helper =:$GPHOME/bin
EOS
}

step_dsp() {
  if have "$NEW_GPHOME/ext/DataSciencePython*"; then
    log "DataSciencePython already present in $NEW_GPHOME"
  else
    have "$DOWNLOAD_DIR/DataSciencePython*.gppkg" || { warn "no DataSciencePython gppkg downloaded, skipping"; return 0; }
    as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gppkg install -a $(ls "$DOWNLOAD_DIR"/DataSciencePython*el8_x86_64.gppkg | tail -1)
gpconfig -c shared_preload_libraries -v 'pgml,metrics_collector'
gpstop -M fast -r -a
EOS
  fi

  local dsp_dir dsp_lib dsp_lib64
  dsp_dir=$(ls -d "$GPHOME"/ext/DataSciencePython* | tail -1)
  dsp_lib=$(ls -d "$dsp_dir"/lib/python*/site-packages | tail -1)
  dsp_lib64=$(ls -d "$dsp_dir"/lib64/python*/site-packages | tail -1)

  as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gpconfig -c pgml.venv -v $dsp_dir
gpconfig -c plpython3.python_path -v '$dsp_lib:$dsp_lib64' --skipvalidation
gpstop -u
EOS
}

step_madlib() {
  if have "$NEW_GPHOME/share/postgresql/extension/madlib.control"; then
    log "madlib already installed in $NEW_GPHOME"
    return 0
  fi
  have "$DOWNLOAD_DIR/madlib*el8-x86_64.tar.gz" || { warn "no madlib tarball downloaded, skipping"; return 0; }

  tar xzf "$DOWNLOAD_DIR"/madlib*el8-x86_64.tar.gz -C "$DOWNLOAD_DIR"
  # madlib 2.2.x ships the package as madlib-<ver>-gp7.gppkg.tar.gz, the inner
  # name no longer carries the el8-x86_64 suffix
  local dir pkg
  dir=$(ls -d "$DOWNLOAD_DIR"/madlib*el8-x86_64 | tail -1)
  pkg=$(ls "$dir"/madlib*.gppkg 2>/dev/null | tail -1 || true)
  [[ -n "$pkg" ]] || pkg=$(ls "$dir"/madlib*.gppkg.tar.gz | tail -1)

  as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gppkg install -a $pkg
EOS
}

step_postgis() {
  if have "$NEW_GPHOME/share/postgresql/extension/postgis.control"; then
    log "postgis already installed in $NEW_GPHOME"
    return 0
  fi
  have "$DOWNLOAD_DIR/postgis*el8-x86_64.gppkg" || { warn "no postgis gppkg downloaded, skipping"; return 0; }

  chmod 644 "$DOWNLOAD_DIR"/postgis*el8-x86_64.gppkg
  # The glob matches both 2.5.x and 3.3.x, gppkg takes one package per call
  local pkg
  pkg=$(ls "$DOWNLOAD_DIR"/postgis*el8-x86_64.gppkg | sort -V | tail -1)

  as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gppkg install -a $pkg
gpstop -M fast -ra
EOS
}

step_plr() {
  if have "$NEW_GPHOME/share/postgresql/extension/plr.control"; then
    log "plr already installed in $NEW_GPHOME"
  else
    have "$DOWNLOAD_DIR/plr*gp7-rhel8-x86_64.gppkg" || { warn "no plr gppkg downloaded, skipping"; return 0; }
    as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gppkg install -a $(ls "$DOWNLOAD_DIR"/plr*gp7-rhel8-x86_64.gppkg | tail -1)
EOS
  fi

  # greenplum_path.sh is inside GPHOME, the R library path has to be added again
  as_gpadmin <<'EOS'
set -x
source /usr/local/greenplum-db/greenplum_path.sh
gpssh -f /home/gpadmin/hosts-all -e "grep -q 'ext/R-3.3.3/lib' /usr/local/greenplum-db/greenplum_path.sh || echo 'export LD_LIBRARY_PATH=\"\$GPHOME/ext/R-3.3.3/lib:\$LD_LIBRARY_PATH\"' >> /usr/local/greenplum-db/greenplum_path.sh"
EOS
}

step_gptext() {
  if ! have "$DOWNLOAD_DIR/greenplum-text*el8_x86_64.tar.gz"; then
    warn "no gptext tarball downloaded (check $GPTEXT_PRODUCT_SLUG / $GPTEXT_RELEASE_VERSION), skipping"
    return 0
  fi
  if have "/usr/local/greenplum-text-*/bin/gptext-start"; then
    log "gptext already installed"
    return 0
  fi

  local tarball version
  tarball=$(ls -t "$DOWNLOAD_DIR"/greenplum-text*el8_x86_64.tar.gz | head -1)
  version=$(basename "$tarball" | perl -pe 's/.*-(\d+\.\d+\.\d+)-.*/$1/')
  chmod 644 "$tarball"

  mkdir -p "/usr/local/greenplum-text-$version" /usr/local/greenplum-solr
  chown gpadmin:gpadmin "/usr/local/greenplum-text-$version" /usr/local/greenplum-solr
  chmod 775 "/usr/local/greenplum-text-$version" /usr/local/greenplum-solr

  as_gpadmin <<EOS
set -x
source /usr/local/greenplum-db/greenplum_path.sh

gpssh -f $HOSTS_SEGMENTS "sudo mkdir -p /usr/local/greenplum-text-$version /usr/local/greenplum-solr"
gpssh -f $HOSTS_SEGMENTS "sudo chown gpadmin:gpadmin /usr/local/greenplum-text-$version /usr/local/greenplum-solr"
gpssh -f $HOSTS_SEGMENTS "sudo chmod 775 /usr/local/greenplum-text-$version /usr/local/greenplum-solr"

gpssh -f $HOSTS_ALL "sudo yum install -y nc"
gpssh -f $HOSTS_ALL "sudo dnf install -y epel-release"
gpssh -f $HOSTS_ALL "sudo dnf install -y tesseract"
gpssh -f $HOSTS_ALL "sudo dnf install -y tesseract-langpack-jpn"

cd /home/gpadmin
tar xzf $tarball
chmod +x \$(ls -t greenplum-text-*.bin | head -1)

cp gptext_install_config gptext_install_config.orig
sed -i 's/^#GPTEXT_HOSTS/GPTEXT_HOSTS/g' gptext_install_config
sed -i 's/^# *GPTEXT_ENABLE_USER_AUTH/GPTEXT_ENABLE_USER_AUTH/g' gptext_install_config
sed -i 's/^# *GPTEXT_ADMIN_USER/GPTEXT_ADMIN_USER/g' gptext_install_config
sed -i 's/^# *GPTEXT_ADMIN_PWD/GPTEXT_ADMIN_PWD/g' gptext_install_config
sed -i 's@/data/gpdata@/gpdata@g' gptext_install_config
echo "declare -a ZOO_HOSTS=(sdw1 sdw1 sdw1)" >> gptext_install_config
echo 'JAVA_OPTS="-Xms256M -Xmx1024M -Dhttp.proxyHost=cdw -Dhttp.proxyPort=3128 -Dhttps.proxyHost=cdw -Dhttps.proxyPort=3128"' >> gptext_install_config

./greenplum-text-*.bin -c gptext_install_config -d /usr/local/greenplum-text-$version
EOS
}

step_gpmlbot() {
  local hba=/gpdata/coordinator/gpseg-1/pg_hba.conf
  for host in samehost 127.0.0.1/32 ::1/128; do
    grep -q "gpmlbot.*gpmlbot.*$host" "$hba" \
      || echo -e "host \t gpmlbot \t gpmlbot \t $host \t trust" >> "$hba"
  done

  as_gpadmin <<'EOS'
set -x
source /usr/local/greenplum-db/greenplum_path.sh
psql -d postgres -tAc "select 1 from pg_database where datname='gpmlbot'" | grep -q 1 || createdb gpmlbot
psql -d postgres -tAc "select 1 from pg_roles where rolname='gpmlbot'" | grep -q 1 || psql -d postgres -c "CREATE ROLE gpmlbot WITH LOGIN;"
psql --dbname gpmlbot -c "CREATE EXTENSION IF NOT EXISTS plpython3u;"
psql --dbname gpmlbot -c "CREATE EXTENSION IF NOT EXISTS madlib;"
psql --dbname gpmlbot -c "CREATE EXTENSION IF NOT EXISTS pgml;"
gpstop -u
EOS

  as_gpadmin <<'EOS' || warn "gpmlbot migrate/load-datasets failed, check that madlib and pgml are in place"
set -x
source /usr/local/greenplum-db/greenplum_path.sh
command -v gpmlbot >/dev/null || exit 0
gpmlbot migrate up --gphome /usr/local/greenplum-db --port 5432 --user gpadmin
gpmlbot load-datasets --gphome /usr/local/greenplum-db --port 5432 --user gpadmin --database gpmlbot
EOS
}

step_finish() {
  as_gpadmin <<'EOS'
set -x
source /usr/local/greenplum-db/greenplum_path.sh
source /usr/local/greenplum-cc/gpcc_path.sh
gpstop -M fast -ra
gpcc start
EOS

  log "upgrade summary"
  as_gpadmin <<'EOS'
source /usr/local/greenplum-db/greenplum_path.sh
source /usr/local/greenplum-cc/gpcc_path.sh
echo "GPHOME       : $(readlink -f /usr/local/greenplum-db)"
echo "GPCC_HOME    : $(readlink -f /usr/local/greenplum-cc)"
psql -d postgres -tAc "select version()"
echo
echo "installed gppkgs:"
gppkg query || true
echo
gpstate -s | grep -E "Total|status" || true
echo
gpcc status || true
EOS
  log "done, GPCC is at https://cdw:28080"
}

##########################################
# main
##########################################
usage() {
  cat <<EOS
usage: $(basename "$0") [options]

  --only  a,b,c   run only these steps
  --skip  a,b,c   run everything except these steps
  --list          print the step names and exit
  -y, --yes       do not ask before stopping the database

steps: ${ALL_STEPS[*]}
EOS
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --skip) SKIP="$2"; shift 2 ;;
    --list) printf '%s\n' "${ALL_STEPS[@]}"; exit 0 ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown argument: $1" ;;
  esac
done

# A --only resume still gets the host validation, --skip preflight still wins
[[ -n "$ONLY" && ",$ONLY," != *",preflight,"* ]] && ONLY="preflight,$ONLY"

exec > >(tee -a "$LOG") 2>&1
log "gp78 upgrade started, logging to $LOG"

FAILED=()
for step in "${ALL_STEPS[@]}"; do
  if selected "$step"; then
    log "===== $step ====="
    if optional "$step"; then
      "step_$step" || { FAILED+=("$step"); warn "step '$step' failed, continuing"; }
    else
      "step_$step"
    fi
  else
    echo "----- skipping $step -----"
  fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  warn "these steps failed: ${FAILED[*]}"
  warn "fix the cause and rerun: $(basename "$0") --only $(IFS=,; echo "${FAILED[*]}")"
  exit 1
fi
log "all selected steps completed"
