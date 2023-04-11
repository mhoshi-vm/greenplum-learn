#cloud-config
runcmd:
  - |
    set -x
    export HOME=/root
    sleep 180
    wget -O /usr/local/bin/pivnet ${pivnet_url}
    chmod +x /usr/local/bin/pivnet
    pivnet login --api-token='${pivnet_api_token}'
    pivnet download-product-files --product-slug='greenplum-streaming-server' --release-version='${pivnet_release_version}' --product-file-id=${pivnet_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${pivnet_file_name}

    cat <<EOC > /home/gpadmin/gpsscfg1.json
    {
        "ListenAddress": {
            "Host": "",
            "Port": 5019,
            "DebugPort": 9998
        },
        "Gpfdist": {
            "Host": "",
            "Port": 8319,
            "ReuseTables": false
        },
        "Shadow": {
            "Key": "a_very_secret_key"
        }
    }
    EOC

    chown gpadmin:gpadmin /home/gpadmin/gpsscfg1.json

    su - gpadmin <<EOF
      . /usr/local/greenplum-db/greenplum_path.sh
      gppkg -i /home/gpadmin/${pivnet_file_name}
      createdb "gpss"
      psql -d gpss -c "CREATE EXTENSION gpss"
      psql -d gpss -c "CREATE USER gpss_user WITH PASSWORD 'password'"
      psql -d gpss -c "GRANT ALL PRIVILEGES ON DATABASE gpss TO gpss_user"
      psql -d gpss -c "CREATE TABLE social_message_data(origin varchar (200),id varchar (200),text varchar (65535),lang varchar (200), names json) DISTRIBUTED BY (id)"
      psql -d gpss -c "ALTER ROLE gpss_user CREATEEXTTABLE(type = 'readable', protocol = 'gpfdist')"
    EOF
