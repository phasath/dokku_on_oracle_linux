#!/bin/bash

if [[ $EUID != 0 ]] ; 
then
    echo "You are not root. Please run it with sudo\n" ;
    exit 1
fi

DOKKU_VERSION=0.14.5

export DOKKU_REPO=${DOKKU_REPO:-"https://github.com/dokku/dokku.git"}

PROCFILE_VERSION=0.4.0
SSHCOMMAND_VERSION=0.7.0
HEROKUISH_VERSION=0.4.7
PLUGN_VERSION=0.3.0
SIGIL_VERSION=0.4.0
MERCURIAL_VERSION=4.7.1-1
HELP2MAN_VERSION=1.47.8

SSHCOMMAND_URL=https://raw.githubusercontent.com/dokku/sshcommand/v${SSHCOMMAND_VERSION}/sshcommand
PROCFILE_UTIL_URL=https://github.com/josegonzalez/go-procfile-util/releases/download/v${PROCFILE_VERSION}/procfile-util_${PROCFILE_VERSION}_linux_x86_64.tgz
HEROKUISH_URL=https://github.com/gliderlabs/herokuish/releases/download/v${HEROKUISH_VERSION}/herokuish_${HEROKUISH_VERSION}_linux_x86_64.tgz
PLUGN_URL=https://github.com/dokku/plugn/releases/download/v${PLUGN_VERSION}/plugn_${PLUGN_VERSION}_linux_x86_64.tgz
SIGIL_URL=https://github.com/gliderlabs/sigil/releases/download/v${SIGIL_VERSION}/sigil_${SIGIL_VERSION}_Linux_x86_64.tgz
MERCURIAL_URL=https://www.mercurial-scm.org/release/centos7/RPMS/x86_64/mercurial-${MERCURIAL_VERSION}.x86_64.rpm
HELP2MAN_URL=https://ftp.gnu.org/gnu/help2man/help2man-${HELP2MAN_VERSION}.tar.xz

STACK_URL=https://github.com/gliderlabs/herokuish.git
PREBUILT_STACK_URL=gliderlabs/herokuish:latest
BUILD_STACK_TARGETS=build-in-docker

# adicionando o repositório rhel do nginx

cat << EOF > /etc/yum.repos.d/nginx.repo
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/mainline/centos/7/\$basearch/
gpgcheck=0
enabled=1
EOF

# instalando o pacote epel do fedora
wget -qO /tmp/epel_package.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum install /tmp/epel_package.rpm
yum install -y epel-release

yum update -y

# install nginx, nc, git, bind-utils and man-db
yum install -y nginx nc git bind-utils man-db

# instalando o plugn - atualizar o link 
wget -qO /tmp/plugn_latest.tgz ${PLUGN_URL}
tar xzf /tmp/plugn_latest.tgz -C /usr/local/bin
sudo chown root:root /usr/local/bin/plugn 
sudo ln -s /usr/local/bin/plugn /usr/bin

# instalando o docker
yum install -y docker-engine
systemctl start docker
systemctl enable docker

# instalando o help2man 
wget -O /tmp/help2man.tar.xz ${HELP2MAN_URL}
pushd /tmp
tar -xvf /tmp/help2man.tar.xz
cd /tmp/help2man-${HELP2MAN_VERSION}
./configure
make
make install
sudo chown root:root /usr/local/bin/help2man 
sudo ln -s /usr/local/bin/help2man /usr/bin

# instalando o sigil
wget -qO /tmp/sigil_latest.tgz ${SIGIL_URL}
tar xzf /tmp/sigil_latest.tgz -C /usr/local/bin
sudo chown root:root /usr/local/bin/sigil 
sudo ln -s /usr/local/bin/sigil /usr/bin

# instalando o herokuish
docker images | grep gliderlabs/herokuish || (git clone ${STACK_URL} /tmp/herokuish && cd /tmp/herokuish && IMAGE_NAME=gliderlabs/herokuish BUILD_TAG=latest VERSION=master make -e ${BUILD_STACK_TARGETS} && rm -rf /tmp/herokuish)
curl --location --silent ${HEROKUISH_URL} | tar -xzC /bin

# instalando o dokku
curl -s https://packagecloud.io/install/repositories/dokku/dokku/script.rpm.sh | sudo bash
sudo yum install -y herokuish dokku

cd /root
if [[ ! -d /root/dokku ]]; then
git clone "$DOKKU_REPO" /root/dokku
fi

cd /root/dokku
git fetch origin

# copiando o binario do dokku para o sistema
cp dokku /usr/bin

# useradd -m syslog

# instalando o sshcommand
wget -qO /usr/local/bin/sshcommand ${SSHCOMMAND_URL}
chmod +x /usr/local/bin/sshcommand
chown root:root /usr/local/bin/sshcommand
ln -s /usr/local/bin/sshcommand /usr/bin
sshcommand create dokku /usr/bin/dokku

# realizando os passos do make de versionamento e copia de arquivos - haverá um erro aqui porque ele chama um comando que executa um apt-get
make version copyfiles

# seta as pastas do dokku e atribui o owner pra ele
DOKKU_LIB_ROOT=/var/lib/dokku
PLUGINS_PATH=${DOKKU_LIB_ROOT}/plugins
CORE_PLUGINS_PATH=${DOKKU_LIB_ROOT}/core-plugins

chown dokku:dokku -R ${PLUGINS_PATH} ${CORE_PLUGINS_PATH} || true

# gera o man para o dokku
mkdir -p /usr/local/share/man/man1
help2man -Nh help -v version -n "configure and get information from your dokku installation" -o /usr/local/share/man/man1/dokku.1 dokku

# adiciona o usuário de syslog, mas ele provavelmente já terá sido criado
useradd -m syslog

# autoriza o dokku a usar os comandos do nginx sem senha do sudoer
cat << EOF > /etc/sudoers.d/dokku-nginx
%dokku ALL=(ALL) NOPASSWD:/usr/bin/systemctl reload nginx, /usr/sbin/nginx -t
Defaults:dokku !requiretty
EOF

# autoriza o dokku a usar os comandos do dokku sem senha de sudoer
cat << EOF > /etc/sudoers.d/dokku-user
%dokku ALL=(ALL:ALL) NOPASSWD:SETENV: /usr/bin/dokku
EOF

# roda os comandos referentes ao dokku extraídos do make 
make plugn procfile-util 
sudo -E dokku plugin:install-dependencies --core
make plugn procfile-util
sudo -E dokku plugin:install --core
egrep -i "^docker" /etc/group || groupadd docker

# adicionando o dokku aos devidos grupos
usermod -aG docker dokku
usermod -aG nginx dokku
usermod -aG wheel dokku

# copia de arquivos dos copyright
mkdir -p /usr/share/doc/dokku/copyright
cp LICENSE /usr/share/doc/dokku/copyright

# copia do bash-completion e do dokku installer
cp contrib/bash-completion /usr/share/bash-completion/completions/dokku
cp contrib/dokku-installer.py /usr/share/dokku/contrib

# roda o script de postinstall
bash rpm/dokku.postinst

# edita o comando do nginx para permitir reiniciar o nginx no oracle linux
pushd  ${PLUGINS_PATH}/available/nginx-vhosts
sed -i 's/arch | centos | rhel)/arch | centos | rhel | ol)/g' functions 
cd templates
sed -i '/listen      \[::\]/s/^/#/g' nginx.conf.sigil 
popd

pushd  ${PLUGINS_PATH}/enabled/nginx-vhosts
sed -i 's/arch | centos | rhel)/arch | centos | rhel | ol)/g' functions 
cd templates
sed -i '/listen      \[::\]/s/^/#/g' nginx.conf.sigil 
popd

servuice nginx restart