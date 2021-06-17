# This software is a part of ISAR.
# Copyright (C) 2021 ilbers GmbH

SCHROOT_CONF ?= "/etc/schroot"

SCHROOT_MOUNTS ?= ""

python __anonymous() {
    import pwd
    d.setVar('SCHROOT_USER', pwd.getpwuid(os.geteuid()).pw_name)
    d.setVar('SCHROOT_USER_HOME', pwd.getpwuid(os.geteuid()).pw_dir)

    mode = d.getVar('ISAR_CROSS_COMPILE', True)
    distro_arch = d.getVar('DISTRO_ARCH')
    if mode == "0" or d.getVar('HOST_ARCH') ==  distro_arch or \
       (d.getVar('HOST_DISTRO') == "debian-stretch" and distro_arch == "i386"):
        d.setVar('SBUILD_HOST_ARCH', distro_arch)
    else:
        d.setVar('SBUILD_HOST_ARCH', d.getVar('HOST_ARCH'))
}

SBUILD_CHROOT ?= "${DEBDISTRONAME}-${SCHROOT_USER}-${@os.getpid()}"
SBUILD_CHROOT_RW ?= "${SBUILD_CHROOT}-rw"

SBUILD_CONF_DIR ?= "${SCHROOT_CONF}/${SBUILD_CHROOT}"
SCHROOT_CONF_FILE ?= "${SCHROOT_CONF}/chroot.d/${SBUILD_CHROOT}"

SCHROOT_DIR ?= "${DEPLOY_DIR_BOOTSTRAP}/${DISTRO}-${SBUILD_HOST_ARCH}"

schroot_create_configs() {
    sudo -s <<'EOSUDO'
        set -e

        cat << EOF > "${SCHROOT_CONF_FILE}"
[${SBUILD_CHROOT}]
type=directory
directory=${SCHROOT_DIR}
profile=${SBUILD_CHROOT}
users=${SCHROOT_USER}
groups=root,sbuild
root-users=${SCHROOT_USER}
root-groups=root,sbuild
source-root-users=${SCHROOT_USER}
source-root-groups=root,sbuild
union-type=overlay
preserve-environment=true

[${SBUILD_CHROOT_RW}]
type=directory
directory=${SCHROOT_DIR}
profile=${SBUILD_CHROOT}
users=${SCHROOT_USER}
groups=root,sbuild
root-users=${SCHROOT_USER}
root-groups=root,sbuild
preserve-environment=true
EOF

        mkdir -p "${SCHROOT_DIR}/etc/apt/preferences.d"
        cat << EOF > "${SCHROOT_DIR}/etc/apt/preferences.d/isar-apt"
Package: *
Pin: release n=${DEBDISTRONAME}
Pin-Priority: 1000
EOF

        # Prepare mount points
        cp -rf "${SCHROOT_CONF}/sbuild" "${SBUILD_CONF_DIR}"
        sbuild_fstab="${SBUILD_CONF_DIR}/fstab"

        fstab_isarapt="${DEPLOY_DIR}/isar-apt /isar-apt none rw,bind 0 0"
        grep -qxF "${fstab_isarapt}" ${sbuild_fstab} || echo "${fstab_isarapt}" >> ${sbuild_fstab}

        if [ -d ${DL_DIR} ]; then
            fstab_downloads="${DL_DIR} /downloads none rw,bind 0 0"
            grep -qxF "${fstab_downloads}" ${sbuild_fstab} || echo "${fstab_downloads}" >> ${sbuild_fstab}
        fi
EOSUDO
}

schroot_delete_configs() {
    sudo -s <<'EOSUDO'
        set -e
        if [ -d "${SBUILD_CONF_DIR}" ]; then
            rm -rf "${SBUILD_CONF_DIR}"
        fi
        rm -f "${SCHROOT_DIR}/etc/apt/preferences.d/isar-apt"
        rm -f "${SCHROOT_CONF_FILE}"
EOSUDO
}

sbuild_export() {
    SBUILD_CONFIG="${WORKDIR}/sbuild.conf"
    VAR_LINE="'${1%%=*}' => '${1#*=}',"
    if [ -s "${SBUILD_CONFIG}" ]; then
        sed -i -e "\$i\\" -e "${VAR_LINE}" ${SBUILD_CONFIG}
    else
        echo "\$build_environment = {" > ${SBUILD_CONFIG}
        echo "${VAR_LINE}" >> ${SBUILD_CONFIG}
        echo "};" >> ${SBUILD_CONFIG}
    fi
    export SBUILD_CONFIG="${SBUILD_CONFIG}"
}

schroot_install() {
    schroot_create_configs
    APTS="$1"
    #TODO deb_dl_dir_import "${BUILDCHROOT_DIR}" "${distro}"
    schroot -d / -c ${SBUILD_CHROOT_RW} -u root -- \
        apt install -y -o Debug::pkgProblemResolver=yes \
                    --no-install-recommends --download-only ${APTS}
    #TODO deb_dl_dir_export "${BUILDCHROOT_DIR}" "${distro}"
    schroot -d / -c ${SBUILD_CHROOT_RW} -u root -- \
        apt install -y -o Debug::pkgProblemResolver=yes \
                    --no-install-recommends ${APTS}
    schroot_delete_configs
}

insert_mounts() {
    sudo -s <<'EOSUDO'
        set -e
        for mp in ${SCHROOT_MOUNTS}; do
            FSTAB_LINE="${mp%%:*} ${mp#*:} none rw,bind 0 0"
            grep -qxF "${FSTAB_LINE}" ${SBUILD_CONF_DIR}/fstab || \
                echo "${FSTAB_LINE}" >> ${SBUILD_CONF_DIR}/fstab
        done
EOSUDO
}

remove_mounts() {
    sudo -s <<'EOSUDO'
        set -e
        for mp in ${SCHROOT_MOUNTS}; do
            FSTAB_LINE="${mp%%:*} ${mp#*:} none rw,bind 0 0"
            sed -i "\|${FSTAB_LINE}|d" ${SBUILD_CONF_DIR}/fstab
        done
EOSUDO
}

schroot_run() {
    schroot_create_configs
    insert_mounts
    schroot $@
    remove_mounts
    schroot_delete_configs
}
