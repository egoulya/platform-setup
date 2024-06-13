#!/bin/bash

green="\033[0;32m"
blue="\033[1;34m"
red="\033[0;31m"
grey="\033[1;37m"
current_path=`pwd`

echo -e "${green}<---------- ETCD INSTALLATION ---------->"
echo -e "${blue}Here is the list of prerequisite for the installation"
echo -e "${blue}\t 1. The Operating System has to be Ubuntu."
echo -e "${blue}\t 2. User should have root previliges."
echo -e "${blue}\t 3. The Ports 2379 & 2380 should be accessible by Daemon and the Host"
echo -e "${green}"

awk -F= '/^NAME/{print $2}' /etc/os-release | grep -i ubuntu
if [ "$?" -ne 0 ];
then
  echo -e "${red}ERROR: The ETCD installation is currently supported for Ubuntu OS."
  exit 1
fi

groups `whoami` | grep sudo
if [ "$?" -ne 0 ];
then
  echo -e "${red}ERROR: User lacks sudo previliges. Switch to Root User"
  exit 1
fi

echo -e "${blue}Oragnization Name:${grey}"
read org_name
echo -e "${blue}Validity of the certificates in years:${grey}"
read years
echo -e "${green}"

validity=$((years*365*24))

cur_user=`whoami`
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg lsb-release -y
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sudo usermod -aG docker $cur_user

public_ip=`curl ifconfig.me`
private_ip=`hostname -I | awk '{print $1}'`

mkdir ~/bin
curl -s -L -o ~/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
curl -s -L -o ~/bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
chmod +x ~/bin/{cfssl,cfssljson}
export PATH=$PATH:~/bin

cert_folder="/var/lib/etcd/cfssl"
sudo mkdir -p ${cert_folder}
sudo chown -R ${cur_user} ${cert_folder}
sudo chmod 755 -R ${cert_folder}
cd ${cert_folder}
echo "{
    \"signing\": {
        \"default\": {
            \"expiry\": \"${validity}h\"
        },
        \"profiles\": {
            \"server\": {
                \"expiry\": \"${validity}h\",
                \"usages\": [
                    \"signing\",
                    \"key encipherment\",
                    \"server auth\",
                    \"client auth\"
                ]
            },
            \"client\": {
                \"expiry\": \"${validity}h\",
                \"usages\": [
                    \"signing\",
                    \"key encipherment\",
                    \"client auth\"
                ]
            },
            \"peer\": {
                \"expiry\": \"${validity}h\",
                \"usages\": [
                    \"signing\",
                    \"key encipherment\",
                    \"server auth\",
                    \"client auth\"
                ]
            }
        }
    }
}" > ca-config.json

echo "{
    \"CN\": \"${org_name} CA\",
    \"key\": {
        \"algo\": \"rsa\",
        \"size\": 2048
    },
    \"names\": [
        {
            \"C\": \"US\",
            \"L\": \"CA\",
            \"O\": \"${org_name} Name\",
            \"ST\": \"San Francisco\",
            \"OU\": \"Org Unit 1\",
            \"OU\": \"Org Unit 2\"
        }
    ]
}" > ca-csr.json
cfssl gencert -initca ca-csr.json | cfssljson -bare ca -

echo "{
    \"CN\": \"etcd-cluster\",
    \"hosts\": [
        \"${public_ip}\",
        \"${private_ip}\",
        \"127.0.0.1\"
    ],
    \"key\": {
        \"algo\": \"rsa\",
        \"size\": 2048
    },
    \"names\": [
        {
            \"C\": \"US\",
            \"L\": \"CA\",
            \"ST\": \"San Francisco\"
        }
    ]
}" > server.json
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=server server.json | cfssljson -bare server

echo "{
    \"CN\": \"member-1\",
    \"hosts\": [
      \"member-1\",
      \"member-1.local\",
      \"${private_ip}\",
      \"127.0.0.1\"
    ],
    \"key\": {
        \"algo\": \"rsa\",
        \"size\": 2048
    },
    \"names\": [
        {
            \"C\": \"US\",
            \"L\": \"CA\",
            \"ST\": \"San Francisco\"
        }
    ]
}" > member-1.json
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=peer member-1.json | cfssljson -bare member-1

echo "{
    \"CN\": \"client\",
    \"hosts\": [\"\"],
    \"key\": {
        \"algo\": \"rsa\",
        \"size\": 2048
    },
    \"names\": [
        {
            \"C\": \"US\",
            \"L\": \"CA\",
            \"ST\": \"San Francisco\"
        }
    ]
}" > client.json
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=client client.json | cfssljson -bare client

cd ${current_path}
mkdir etcd_data
data_folder=$current_path"/etcd_data"

VERSION=$(curl -s https://api.github.com/repos/singnet/snet-daemon/releases/latest | grep tag_name | cut -d ':' -f 2 | grep -Po "v[0-9]+\.[0-9]+\.[0-9]+")

echo "
services:
  etcd:
    image: quay.io/coreos/etcd:v3.5.0
    ports:
      - '2379:2379'
      - '2380:2380'
    restart: on-failure
    volumes:
      - ${data_folder}:/data.etcd
      - ${cert_folder}:/certs
    command: >
      etcd
      --name=node-1
      --data-dir=data.etcd
      --initial-advertise-peer-urls https://${private_ip}:2380
      --listen-peer-urls https://0.0.0.0:2380
      --listen-client-urls https://0.0.0.0:2379
      --advertise-client-urls https://${private_ip}:2379
      --initial-cluster node-1=https://${private_ip}:2380
      --initial-cluster-state=new
      --initial-cluster-token=etcd-cluster-1
      --client-cert-auth
      --trusted-ca-file=/certs/ca.pem
      --cert-file=/certs/server.pem
      --key-file=/certs/server-key.pem
      --peer-client-cert-auth
      --peer-trusted-ca-file=/certs/ca.pem
      --peer-cert-file=/certs/member-1.pem
      --peer-key-file=/certs/member-1-key.pem
  daemon:
    image: singnet-daemon:latest
    environment:
      VERSION: ${version}
    build:
      context: .
      dockerfile_inline: |
        FROM alpine:latest
        WORKDIR /workdir
        RUN apk update && apk upgrade && apk add curl grep python3 py3-pip
        RUN wget https://github.com/singnet/snet-daemon/releases/download/$VERSION/snetd-linux-amd64-$VERSION -O snetd && chmod +x ./snetd
        RUN pip install snet.cli --break-system-packages
        CMD ["./snetd", "-c", "config.json"]
    volumes:
      - ${current_path}/daemon-config.json:/workdir/config.json
    ports:
      - '8000:8000'
    restart: on-failure:3
    command: ./snetd -c config.json
" > docker-compose.yml

docker compose up -d etcd

sleep 30
curl --cacert ${cert_folder}/ca.pem --cert ${cert_folder}/client.pem --key ${cert_folder}/client-key.pem "https://${private_ip}:2379/health"

if [ "$?" -ne 0 ];
then
  echo -e "${red}ERROR: Port 2379 & 2380 seems to be not accessible from the host."
  rm -rf ~/bin
  docker compose down
  rm docker-compose.yml
  sudo rm -rf ${cert_folder}
  sudo rm -rf ${data_folder}
  docker rmi quay.io/coreos/etcd:v3.5.0
  sudo rm /etc/apt/keyrings/docker.gpg
  echo -e "${red}<---------- ETCD INSTALLATION FAILED---------->"
else
  echo -e "${green}"
  echo -e "<---------- ETCD INSTALLATED SUCCESSFULLY---------->"
  echo -e "${blue} 1. ETCD ENDPOINT: ${grey} https://${private_ip}:2379/health"
  echo -e "${blue} 2.1. CERTIFICATES PATH: ${grey} ${cert_folder}"
  echo -e "${blue} 2.2. ETCD DATA PATH: ${grey} ${data_folder}"
  echo -e "${blue} 3. COMMAND TO TEST LOCALLY: ${grey} curl --cacert ${cert_folder}/ca.pem --cert ${cert_folder}/client.pem --key ${cert_folder}/client-key.pem https://${private_ip}:2379/health"
  echo -e "${blue} 4. TO START ETCD: ${grey} docker compose start etcd"
  echo -e "${blue} 5. TO STOP ETCD: ${grey} docker compose stop etcd"
  echo -e "${blue} 6. TO CHECK STATUS/LOGS OF ETCD: ${grey} docker compose logs etcd"
  echo -e "${blue} 7. TO DELETE ETCD: ${grey} docker compose down etcd\n"
  echo -e "${blue} DAEMON: To start daemon place deamon config file near docker-compose file and run: ${grey} docker compose up -d daemon"
fi
