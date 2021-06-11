# This software is a part of ISAR.
# Copyright (C) 2021 ilbers GmbH

SCHROOT_CONF ?= "/etc/schroot"

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

SBUILD_CHROOT ?= "${DEBDISTRONAME}-${SCHROOT_USER}-${DISTRO}-${SBUILD_HOST_ARCH}"
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
