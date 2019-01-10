#!/bin/bash

## Shell Opts ----------------------------------------------------------------
set -e -u -x


## Variables -----------------------------------------------------------------
# Set the compatible version of ansible for RPC Toolstack projects
export ANSIBLE_VERSION="2.6.5"
export WORKING_DIR="/opt/magnanimous-turbo-chainsaw"
export SCRIPT_DIR="${WORKING_DIR}/scripts"
export PLAYBOOK_DIR="${WORKING_DIR}/playbooks"

# Use this environment variable to add additional options to all ansible runs.
export ANSIBLE_EXTRA_VARS=""

# Determine OS and validate curl is installed
source /etc/os-release
export ID="$(echo ${ID} | awk -F'-' '{print $1}')"


## Variables -----------------------------------------------------------------
function ssh_key_create {
  # Ensure that the ssh key exists and is an authorized_key
  key_path="${HOME}/.ssh"
  key_file="${key_path}/id_rsa"

  # Ensure that the .ssh directory exists and has the right mode
  if [ ! -d ${key_path} ]; then
    mkdir -p ${key_path}
    chmod 700 ${key_path}
  fi
  if [ ! -f "${key_file}" -a ! -f "${key_file}.pub" ]; then
    rm -f ${key_file}*
    ssh-keygen -t rsa -f ${key_file} -N ''
  fi

  # Ensure that the public key is included in the authorized_keys
  # for the default root directory and the current home directory
  key_content=$(cat "${key_file}.pub")
  if ! grep -q "${key_content}" ${key_path}/authorized_keys; then
    echo "${key_content}" | tee -a ${key_path}/authorized_keys
  fi
}


## Main ----------------------------------------------------------------------
if [[ ! -e $(which curl) ]]; then
  if [[ ${ID} = "ubuntu" ]]; then
    apt-get update
    apt-get -y install curl
  elif [[ ${ID} = "opensuse" ]] || [[ ${ID} = "suse" ]]; then
    zypper install -y curl
  elif [[ ${ID} = "centos" ]] || [[ ${ID} = "redhat" ]] || [[ ${ID} = "rhel" ]]; then
    yum install -y curl
  else
    echo "Unknown operating system"
    exit 99
  fi
fi

# Setup git for use with a proxy if one is found.
if [[ ! -z "${http_proxy:-}" ]] || [[ ! -z "${https_proxy:-}" ]]; then
  if [[ -f "${SCRIPT_DIR}/setup-proxy.sh" ]];  then
    bash "${SCRIPT_DIR}/setup-proxy.sh"
  else
    curl -D - https://raw.githubusercontent.com/rcbops/magnanimous-turbo-chainsaw/master/scripts/setup-proxy.sh -o /tmp/setup-proxy.sh
    bash /tmp/setup-proxy.sh
  fi
fi

# Generate keys if they are not currently setup
ssh_key_create

# If a pip config is present move it out of the way for the basic setup
if [[ -d "${HOME}/.pip" ]]; then
  mv "${HOME}/.pip" "${HOME}/.pip.bak"
fi

# Source the ops repo
if [[ ! -d "/opt/openstack-ansible-ops" ]]; then
  git clone https://github.com/openstack/openstack-ansible-ops /opt/openstack-ansible-ops
  pushd /opt/openstack-ansible-ops/bootstrap-embedded-ansible
    PS1=${PS1:-'\\u@\h \\W]\\$'} source bootstrap-embedded-ansible.sh
    # NOTICE(Cloudnull): This pip install is only required until we can sort out
    #                    why its needed for installation that use Hashicorp-Vault.
    pip install pyOpenSSL==16.2.0
  popd
fi

# Restore the pip config if found
if [[ -d "${HOME}/.pip.bak" ]]; then
  mv "${HOME}/.pip.bak" "${HOME}/.pip"
fi

# Get the environmental tools repo
if [[ -f "${PLAYBOOK_DIR}/get-mtc.yml" ]];  then
  ansible-playbook ${ANSIBLE_EXTRA_VARS} -i 'localhost,' "${PLAYBOOK_DIR}/get-mtc.yml"
else
  curl -D - https://raw.githubusercontent.com/rcbops/magnanimous-turbo-chainsaw/master/playbooks/get-mtc.yml -o /tmp/get-mtc.yml
  ansible-playbook ${ANSIBLE_EXTRA_VARS} -i 'localhost,' /tmp/get-mtc.yml
fi

# Get osa ops tools
ansible-playbook ${ANSIBLE_EXTRA_VARS} -i 'localhost,' "${PLAYBOOK_DIR}/get-osa-ops.yml"

# Generate the required variables
ansible-playbook ${ANSIBLE_EXTRA_VARS} \
                 -i 'localhost,' \
                 -e "http_proxy_server=${http_proxy:-'none://none:none'}" \
                 ${PLAYBOOK_DIR}/generate-environment-vars.yml
