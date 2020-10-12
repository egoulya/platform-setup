#! /bin/bash

set -e
set -o xtrace

organizationDeployment() {
if [  ! -z "$(snet organization list | grep "$orgID")" ];
    then
       echo -e "${orange}organization :$orgID:..is already deployed!!!."
       echo -e "${blue}Would you like to update the organization metadata ? y/n:${grey}"
       read update
       if [ $update == "y" ];
        then
          snet organization print-metadata snet $orgID > $orgID.json
          cat $orgID.json
            echo -e "${blue}Does the metadata look fine to you ? y/n:${grey}"
            read ok
            if [ $ok == "n" ];
            then
               echo -e "${blue}Please edit the metadata:${grey}"
                vi  $orgID.json
                snet organization update-metadata snet $orgID
            fi
       fi

 else
            if [ -e $orgID.json ]
              then
               rm $orgID.json
            fi
            echo -e "${blue}Please enter your organization name:${grey}"
            read orgName
            echo -e "${blue}Please enter description of your organization:${grey}"
            read $orgDescription
             echo -e "${green}<---------- Going to auto generate the metadata for your Organization  ---------->${grey}"
            snet organization metadata-init $orgName $orgID individual --metadata-file $orgID.json
            snet organization metadata-add-description --description "$orgDescription" --short-description  "$orgDescription" --url "" --metadata-file $orgID.json
            echo " you choose clusterETCDSetup $clusterETCDSetup"
            if [ $clusterETCDSetup == "n" ];
            then
              etcdendpoint="http://localhost:2379"
            else
               etcdendpoint="https://$domainName:2379"
            fi
            snet organization add-group default_group $walletAddress $etcdendpoint --metadata-file $orgID.json
            cat $orgID.json
            echo -e "${blue}Does the metadata look fine to you ? y/n:${grey}"
            read ok
            if [ $ok == "n" ];
            then
               echo -e "${blue}Please edit the metadata:${grey}"
               vi  $orgID.json
            fi
           echo -e "${green} Going to publish your organization on the block chain....${grey}"
           snet --print-traceback organization create $orgID --metadata-file $orgID.json
           echo -e "${green} Organization $orgID successfully published the block chain....${grey}"
 fi

}
serviceDeployment() {

echo `pwd`
echo -e "${blue}Please enter your service id:${grey}"
read serviceID

       echo -e "${blue}Please enter your daemon port:${grey}"
        read daemonPort

 #need to handle when the serviceID is same as orgID
    if [  ! -z "$(snet organization list-services $orgID | grep "$serviceID")" ];
    then
       echo -e "${green}\n service :$serviceID:..is already deployed!!!."
       echo -e "${blue}Would you like to update the service metadata ? y/n:${grey}"
       read update
       if [ update == "y" ];
        then
          snet service print-metadata $orgID $serviceID > $MD_FILE
          echo "Please Edit the metadata"
          vi $MD_FILE
          echo -e "${green}Updating service metadata on blockchain ...${grey}"
          snet --print-traceback service update-metadata $serviceID --metadata-file $MD_FILE
       fi

    else
        echo -e "${blue}\nPlease enter your service description:${grey}"
        read serviceDescription
        echo -e "${blue}Would you like to download an Existing example serivce and use ?:${grey}"
        read readExampleService
        if [ $readExampleService == "y" ];
        then
            protopath="example-service/tree/master/service/service_spec"
            get_gitrepo
        else
          echo -e "${blue}Please enter folder location of your proto:${grey}"
          read protopath
        fi


        echo -e "${blue}Please enter your domain name:${grey}"
        read domainName


        MD_FILE=`echo "$serviceID.service.json"`
        if [ -e MD_FILE ]
         then
         rm $MD_FILE
        fi
        snet --print-traceback service metadata-init --metadata-file $MD_FILE `pwd`/$protopath "$serviceID" --encoding proto --service-type grpc --group-name default_group
        printErrorAndExit
        snet --print-traceback service metadata-set-fixed-price default_group 0.00000001 --metadata-file $MD_FILE
        snet --print-traceback service metadata-add-endpoints default_group $domainName:$daemonPort --metadata-file $MD_FILE
        snet --print-traceback service metadata-add-description --metadata-file $MD_FILE --description "$serviceDescription" --url "" --short-description "$serviceDescription"
        snet --print-traceback service metadata-set-free-calls default_group 15 --metadata-file $MD_FILE
        snet --print-traceback service metadata-set-freecall-signer-address default_group 0x7DF35C98f41F3Af0df1dc4c7F7D4C19a71Dd059F --metadata-file $MD_FILE
        cat $MD_FILE
        echo -e "${blue}\nDoes the metadata look fine to you ? y/n:${grey}"
        read ok
        if [ $ok == "n" ];
        then
           echo -e "${blue}Please edit the metadata:${grey}"
           vi  $MD_FILE
        fi
        snet --print-traceback service publish $orgID $serviceID --metadata-file $MD_FILE
    fi

 # add these if etcd cluster is setup
 # "payment_channel_cert_path": "/home/adminuser/Downloads/client1.pem",
 # "payment_channel_ca_path": "/home/adminuser/Downloads/ca1.pem",
 # "payment_channel_key_path": "/home/adminuser/Downloads/client-key1.pem",
 #  need to handle the etcd cluster set up


}
daemonConfig() {

if [ $clusterETCDSetup == "n" ];
 then
    localETCDconfig=",\"payment_channel_storage_server\": {\"enabled\": true}"
else
    localETCDconfig=""
fi
cat > $orgID.$serviceID.snetd.config.json << EOF
 {
  "daemon_end_point": "0.0.0.0:$daemonPort",
  "passthrough_enabled":true,
  "ipfs_end_point": "http://ipfs.singularitynet.io:80",
  "blockchain_network_selected": "ropsten",
  "blockchain_enabled":true,
  "metering_enabled": false,
  "passthrough_endpoint": "http://localhost:7003",
  "organization_id": "$orgID",
  "service_id": "$serviceID",
  "log": {
    "level": "debug",
    "output": {
      "current_link": "./$orgID.$serviceID.log",
      "file_pattern": "./$orgID.$serviceID.%Y%m%d.log",
      "rotation_count": 0,
      "rotation_time_in_sec": 86400,
      "type": "file"
    }
  }
  	$localETCDconfig
}
EOF
  cat $orgID.$serviceID.snetd.config.json
  echo -e "${blue}\nDoes the daemon configuration look fine to you ? y/n:${grey}"
        read ok
        if [ $ok == "n" ];
        then
           echo -e "${blue}Please edit the config:${grey}"
           vi  $MD_FILE
        fi

  echo -e "${green}\nStarting Daemon.....:${grey}"
  nohup snetd --config $orgID.$serviceID.snetd.config.json &
  ps aux |grep $daemonPort
  if [ "$?" -ne 0 ];
  then
   echo -e "${red}\nDaemon Startup Failed, please check the logs:${grey}"
  else
   echo -e "${green}\nDaemon Successfully Started:${grey}"
 fi

}
get_gitrepo() {
    GITURL="https://github.com/singnet/example-service"
    YOURGITREPONAME="example-service"
    #Check if this repo is already downloaded
    if [ ! -d "$YOURGITREPONAME" ]
    then
        git clone $GITURL
        echo "Git Repo pulled successfully"
    else
        #update the git repo
        cd $YOURGITREPONAME
        git pull
        echo "Git Repo updated successfully"
        cd ..
    fi
    cd example-service
    pip3 install -r requirements.txt
    chmod 777 buildproto.sh
    ./buildproto.sh
    nohup python3 run_example_service.py --no-daemon &
    echo -e "${green}Started Example Service on port 7003!!!"
    protopath="example-service/service/service_spec"
    cd ..
}

installDaemon() {
    echo -e "${green}<---------- Installing snet Daemon ... ---------->"
    set -ex
    SNETD_VERSION=`curl -s https://api.github.com/repos/singnet/snet-daemon/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")' || echo "v4.0.0"`
    echo 'version' $SNETD_VERSION
    wget https://github.com/singnet/snet-daemon/releases/download/${SNETD_VERSION}/snet-daemon-${SNETD_VERSION}-linux-amd64.tar.gz
    tar -xvf snet-daemon-${SNETD_VERSION}-linux-amd64.tar.gz
    WITH_SUDO=$([ "$EUID" != 0 ] && echo "sudo" || echo "")
    $WITH_SUDO mv snet-daemon-${SNETD_VERSION}-linux-amd64/snetd /usr/bin/snetd
    echo -e "${green}<---------- snet daemon successfully installed ---------->"

}
installSnetCli() {

         pip3 install snet-cli
}



checkAndInstall() {
 echo -e "${green}\n Installing Dependencies!!!."
 WITH_SUDO=$([ "$EUID" != 0 ] && echo "sudo" || echo "")
 $WITH_SUDO apt-get update
 $WITH_SUDO apt-get install curl net-tools netcat unzip zip bzip2 gnupg curl wget python3 python3-pip python3-dev python3-venv libudev-dev libusb-1.0-0-dev vim -y;

 python3 -m venv env
 source env/bin/activate
 snet version || { installSnetCli; }
 snetd version || { installDaemon; }

}

identitySetUp() {

snet identity list
if [[ $(snet identity list | head -c1 | wc -c) -eq 0 ]];
then
    echo -e "${blue}Please enter a MNEMONIC to create an account that will be used for all block chain operations:${grey}"
    read mnemonic
    echo -e "${blue}Please enter a name to identity/account:${grey}"
    read identityname
    snet identity create --mnemonic $mnemonic --network ropsten $identityname mnemonic
    snet identity $identityname
    walletAddress=`snet account print`;
    echo "$walletAddress">req.json
    curl -X POST -H "Content-Type: application/json" -d @req.json https://faucet.metamask.io
else  echo -e "${blue}\nEnter the identity name to switch over ${grey}";
      snet identity list
      read identityname
      snet identity $identityname
      walletAddress=`snet account print`;
      echo "Wallet address is $walletAddress"
      snet account balance
      if [[ $( snet account balance |grep "ETH"|tr -d "ETH: ") == "0" ]];
      then
         echo -e "${red}Please add Ether on to you address from ether Faucet in Ropsten at https://faucet.ropsten.be/ for your address: $walletAddress "
         exit
      fi
fi

}

printErrorAndExit() {
 if [ "$?" -ne 0 ];
then
  echo -e "${red}ERROR: $?."
  exit 1
fi
}

green="\033[0;32m"
blue="\033[1;34m"
red="\033[0;31m"
grey="\033[1;37m"
current_path=`pwd`

uname -a | grep -i "ubuntu"
if [ "$?" -ne 0 ];
then
  echo -e "${red}ERROR: The installation/setup is currently supported for Ubuntu OS."
  exit 1
fi


echo -e "${green}<---------- SINGULARITY NET BASIC SETUP ---------->"
echo -e "${blue}Here are the list of prerequisite for the installation"
echo -e "${blue}\t 1. The Operating System has to be Ubuntu."
echo -e "${blue}\t 2. User should have root privileges."
echo -e "${green}"

echo -e "${blue}Checking for Dependencies and Installing ... ${grey}"
checkAndInstall

echo -e "${blue}Would you like to setup an ETCD cluster with a single node y/n ?:${grey}"
read clusterETCDSetup

if [ $clusterETCDSetup == "y" ];
then
  ./etcd-setup_sh.sh

  else
    echo "Please note your etcd client end point will be on port 2379 , http://localhost:2379"
fi

identitySetUp


echo -e "${blue}Please enter your organization id:${grey}"
read orgID
organizationDeployment

serviceDeployment

daemonConfig
#get all the services from the block chain




