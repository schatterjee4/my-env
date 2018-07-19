set -e
help_message="$0 <download|mkdir :ip|export :nix_package|import :ip :nix_package|start :ip :nix_package [--:arg-name arg-value]+>"

my=$(cd -P -- "$(dirname -- "${BASH_SOURCE-$0}")" > /dev/null && pwd -P)
mkdir -p $my/{nix.sh.d,nix.sh.out}

nix_name=nix-2.0.4
nix_tar=${nix_name}-x86_64-linux.tar.bz2

if [ "$1" == "download" ]; then
  echo "[action] download ${nix_name}"
  if [ ! -e $my/${nix_tar} ]; then
    wget -O $my/${nix_tar}.tmp https://nixos.org/releases/nix/${nix_name}/${nix_tar}
    mv $my/nix.sh.d/${nix_tar}.tmp $my/nix.sh.d/${nix_tar}
  else
    echo "[info] file exist already!"
  fi
elif [ "$1" == "export" ]; then
  nix_package=$2
  if [ "${nix_package}" = "" ]; then
    echo "${help_message}"
    echo "[error]: nix_package is missing"
    exit 1
  fi
  echo "[action] export ${nix_package}..."
  if [ -e nix.sh.out/${nix_package}.closure ]; then
    echo "---->[info] ${nix_package} exist already!"
  else
    nix-store --export $(nix-store -qR /nix/store/*${nix_package}*) | bzip2 > nix.sh.out/${nix_package}.closure.bz2
  fi
elif [ "$1" == "init" ]; then
  remote_ip=$2
  echo "[action] init $remote_ip"
  ssh root@$remote_ip "
    if [ ! -e /nix ]; then
      useradd -m op
      echo 'op:op' | chpasswd
      install -d -m755 -o op -g op /nix
    else
      echo '---->[${remote_ip}-info] /nix exist already!'
    fi
  "
elif [ "$1" == "install" ]; then
  remote_ip=$2
  echo "[action] install $remote_ip"
  echo "#=> mkdir my-env directory"
  ssh op@${remote_ip} "mkdir -p my-env/nix.sh.d"
  echo "#=> sync local file"
  rsync -av ${my}/nix.sh.d/ op@${remote_ip}:my-env/nix.sh.d
  echo "#=> install nix"
  ssh op@${remote_ip} "
    if [ -e '.nix-profile/bin/nix' ]; then
      echo '---->[info] remote_ip:${remote_ip} install nix already!'
    else
      cd my-env/nix.sh.d && tar -xvf ${nix_tar} && cd nix* && cp ../_install . && ./_install
    fi
  "
elif [ "$1" == "import" ]; then
  remote_ip=$2
  nix_package=$3
  if [ "${nix_package}" = "" ]; then
    echo "${help_message}"
    echo "[error]: nix_package is missing"
    exit 1
  fi
  echo "[action] import ${remote_ip} ${nix_package}"
  echo "--> check whether remote package exist..."
  package_exist=$(ssh op@${remote_ip} "
    if compgen -G '/nix/store/*${nix_package}*' > /dev/null; then echo 1; else echo 0; fi
  ")
  if [ "$package_exist" == "1" ]; then 
    echo "---->[${remote_ip}-info] ${nix_package} imported already"
  else
    echo "--> import ${nix_package} need to cost a little time, please be patient..."
    echo "cat nix.sh.out/${nix_package}.closure.bz2 | ssh op@${remote_ip} \"bunzip2 | .nix-profile/bin/nix-store -v --import\""
    cat nix.sh.out/${nix_package}.closure.bz2 | ssh op@${remote_ip} "bunzip2 | .nix-profile/bin/nix-store --import"
  fi
elif [ "$1" == "start" -o "$1" == "start-foreground" ]; then
  action=$1; remote_host=$2; nix_package=$3
  echo "[action] $action $remote_ip ${nix_package}"
  remote_ip=$(echo $remote_host | cut -d: -f1)
  if [ "${nix_package}" = "" ]; then
    echo "${help_message}"
    echo "[error]: nix_package is missing"
    exit 1
  fi

  echo "#=> mk directory: nix.conf/${nix_package}"
  ssh op@${remote_ip} "mkdir -p my-env/nix.conf/${nix_package}"
  echo "#=> sync conf file: $my/nix.conf/${nix_package}"
  rsync -av ${my}/nix.conf/${nix_package}/ op@${remote_ip}:my-env/nix.conf/${nix_package}
  ssh op@${remote_ip} "sh my-env/nix.conf/${nix_package}/run.sh $@"
else
  echo ${help_message}
fi
