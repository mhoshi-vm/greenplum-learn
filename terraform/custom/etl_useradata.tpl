#cloud-config
runcmd:
  - |
    set -x
    tdnf install docker -y
    
    systemctl  start docker
    mkdir -p /rabbitmq
    
    cat <<EOF > /rabbitmq/rabbitmq.conf
    management.load_definitions = /etc/rabbitmq/definitions.json
    EOF
    
    cat <<EOF > /rabbitmq/definitions.json
    {
       "users": [
          {
            "name": "guest",
            "password_hash": "BMfxN8drrYcIqXZMr+pWTpDT0nMcOagMduLX0bjr4jwud/pN",
            "hashing_algorithm": "rabbit_password_hashing_sha256",
            "tags": [
              "administrator"
            ],
            "limits": {}
          }
        ],
        "vhosts": [
          {
            "name": "/"
          }
        ],
        "permissions": [
          {
            "user": "guest",
            "vhost": "/",
            "configure": ".*",
            "write": ".*",
            "read": ".*"
          }
        ],
        "queues":[
            {"name":"gpss","vhost":"/","durable":true,"auto_delete":false,"arguments":{}}
        ]
    }
    EOF
    
    chmod 644 /rabbitmq/rabbitmq.conf /rabbitmq/definitions.json
    
    docker run -d -v /rabbitmq/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf -v /rabbitmq/definitions.json:/etc/rabbitmq/definitions.json --rm -it -p 15672:15672 -p 5672:5672  harbor.lespaulstudioplus.info/dockerhub/library/rabbitmq:3-management

    tdnf install -y nfs-utils
    systemctl enable rpcbind
    systemctl start rpcbind
    systemctl enable nfs-server
    systemctl start nfs-server
    mkdir /nfs
    echo '/nfs *(rw,no_root_squash,no_subtree_check)' >> /etc/exports
    exportfs -r
