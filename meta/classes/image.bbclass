# This software is a part of ISAR.
# Copyright (C) 2015-2017 ilbers GmbH

# Replace possible multiple spaces with single underscores
IMAGE_SUFFIX = "${@'_'.join(d.getVar("IMAGE_FSTYPES", True).split())}"
# Make workdir and stamps machine-specific without changing common PN target
WORKDIR = "${TMPDIR}/work/${DISTRO}-${DISTRO_ARCH}/${PN}-${MACHINE}-${IMAGE_SUFFIX}/${PV}-${PR}"
STAMP = "${STAMPS_DIR}/${DISTRO}-${DISTRO_ARCH}/${PN}-${MACHINE}-${IMAGE_SUFFIX}/${PV}-${PR}"
STAMPCLEAN = "${STAMPS_DIR}/${DISTRO}-${DISTRO_ARCH}/${PN}-${MACHINE}-${IMAGE_SUFFIX}/*-*"

# Sstate also needs to be machine-specific
SSTATE_MANIFESTS = "${TMPDIR}/sstate-control/${MACHINE}-${DISTRO}-${DISTRO_ARCH}-${IMAGE_SUFFIX}"

IMAGE_INSTALL ?= ""
IMAGE_FSTYPES ?= "${@ d.getVar("IMAGE_TYPE", True) if d.getVar("IMAGE_TYPE", True) else "ext4-img"}"
IMAGE_ROOTFS ?= "${WORKDIR}/rootfs"

IMAGE_INSTALL += "${@ ("linux-image-" + d.getVar("KERNEL_NAME", True)) if d.getVar("KERNEL_NAME", True) else ""}"

# Name of the image including distro&machine names
IMAGE_FULLNAME = "${PN}-${DISTRO}-${MACHINE}"

# These variables are used by wic and start_vm
KERNEL_IMAGE ?= "${IMAGE_FULLNAME}-${KERNEL_FILE}"
INITRD_IMAGE ?= "${IMAGE_FULLNAME}-initrd.img"

# This defines the deployed dtbs for reuse by imagers
DTB_FILES ?= ""

# Useful variables for imager implementations:
PP = "/home/builder/${PN}"
PP_DEPLOY = "${PP}/deploy"
PP_ROOTFS = "${PP}/rootfs"
PP_WORK = "${PP}/work"

BUILDROOT = "${BUILDCHROOT_DIR}${PP}"
BUILDROOT_DEPLOY = "${BUILDCHROOT_DIR}${PP_DEPLOY}"
BUILDROOT_ROOTFS = "${BUILDCHROOT_DIR}${PP_ROOTFS}"
BUILDROOT_WORK = "${BUILDCHROOT_DIR}${PP_WORK}"

python(){
    if (d.getVar('IMAGE_TRANSIENT_PACKAGES')):
        bb.warn("IMAGE_TRANSIENT_PACKAGES is set and no longer supported")
    if (d.getVar('IMAGE_TYPE')):
        bb.warn("IMAGE_TYPE is deprecated, please switch to IMAGE_FSTYPES")
}

def cfg_script(d):
    cf = d.getVar('DISTRO_CONFIG_SCRIPT', True) or ''
    if cf:
        return 'file://' + cf
    return ''

FILESPATH =. "${LAYERDIR_core}/conf/distro:"
SRC_URI += "${@ cfg_script(d) }"

DEPENDS += "${IMAGE_INSTALL}"

ISAR_RELEASE_CMD_DEFAULT = "git -C ${LAYERDIR_core} describe --tags --dirty --match 'v[0-9].[0-9]*'"
ISAR_RELEASE_CMD ?= "${ISAR_RELEASE_CMD_DEFAULT}"

image_do_mounts() {
    sudo flock ${MOUNT_LOCKFILE} -c ' \
        mkdir -p "${BUILDROOT_DEPLOY}" "${BUILDROOT_ROOTFS}" "${BUILDROOT_WORK}"
        mount --bind "${DEPLOY_DIR_IMAGE}" "${BUILDROOT_DEPLOY}"
        mount --bind "${IMAGE_ROOTFS}" "${BUILDROOT_ROOTFS}"
        mount --bind "${WORKDIR}" "${BUILDROOT_WORK}"
    '
    buildchroot_do_mounts
}

ROOTFSDIR = "${IMAGE_ROOTFS}"
ROOTFS_FEATURES += "clean-package-cache generate-manifest export-dpkg-status clean-log-files"
ROOTFS_PACKAGES += "${IMAGE_PREINSTALL} ${IMAGE_INSTALL}"
ROOTFS_MANIFEST_DEPLOY_DIR ?= "${DEPLOY_DIR_IMAGE}"
ROOTFS_DPKGSTATUS_DEPLOY_DIR ?= "${DEPLOY_DIR_IMAGE}"

ROOTFS_POSTPROCESS_COMMAND_prepend = "${@bb.utils.contains('BASE_REPO_FEATURES', 'cache-deb-src', 'cache_deb_src', '', d)} "

inherit rootfs
inherit image-sdk-extension
inherit image-tools-extension
inherit image-postproc-extension
inherit image-locales-extension
inherit image-account-extension
inherit image-container-extension

# Extra space for rootfs in MB
ROOTFS_EXTRA ?= "64"

def get_rootfs_size(d):
    import subprocess
    rootfs_extra = int(d.getVar("ROOTFS_EXTRA", True))

    output = subprocess.check_output(
        ["sudo", "du", "-xs", "--block-size=1k", d.getVar("IMAGE_ROOTFS", True)]
    )
    base_size = int(output.split()[0])

    return base_size + rootfs_extra * 1024

# here we call a command that should describe your whole build system,
# this could be "git describe" or something similar.
# set ISAR_RELEASE_CMD to customize, or override do_mark_rootfs to do something
# completely different
get_build_id() {
	if [ $(echo ${BBLAYERS} | wc -w) -ne 2 ] &&
	   [ "${ISAR_RELEASE_CMD}" = "${ISAR_RELEASE_CMD_DEFAULT}" ]; then
		bbwarn "You are using external layers that will not be" \
		       "considered in the build_id. Consider changing" \
		       "ISAR_RELEASE_CMD."
	fi
	if ! ( ${ISAR_RELEASE_CMD} ) 2>/dev/null; then
		bbwarn "\"${ISAR_RELEASE_CMD}\" failed, returning empty build_id."
		echo ""
	fi
}

python set_image_size () {
    rootfs_size = get_rootfs_size(d)
    d.setVar('ROOTFS_SIZE', str(rootfs_size))
    d.setVarFlag('ROOTFS_SIZE', 'export', '1')
}

ROOTFS_CONFIGURE_COMMAND += "image_configure_fstab"
image_configure_fstab[weight] = "2"
image_configure_fstab() {
    sudo tee '${IMAGE_ROOTFS}/etc/fstab' << EOF
# Begin /etc/fstab
/dev/root	/		auto		defaults		0	0
proc		/proc		proc		nosuid,noexec,nodev	0	0
sysfs		/sys		sysfs		nosuid,noexec,nodev	0	0
devpts		/dev/pts	devpts		gid=5,mode=620		0	0
tmpfs		/run		tmpfs		defaults		0	0
devtmpfs	/dev		devtmpfs	mode=0755,nosuid	0	0

# End /etc/fstab
EOF
}

do_copy_boot_files[dirs] = "${DEPLOY_DIR_IMAGE}"
do_copy_boot_files() {
    kernel="$(realpath -q '${IMAGE_ROOTFS}'/vmlinu[xz])"
    if [ ! -f "$kernel" ]; then
        kernel="$(realpath -q '${IMAGE_ROOTFS}'/boot/vmlinu[xz])"
    fi
    if [ -f "$kernel" ]; then
        sudo cat "$kernel" > "${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGE}"
    fi

    initrd="$(realpath -q '${IMAGE_ROOTFS}/initrd.img')"
    if [ ! -f "$initrd" ]; then
        initrd="$(realpath -q '${IMAGE_ROOTFS}/boot/initrd.img')"
    fi
    if [ -f "$initrd" ]; then
        cp -f "$initrd" '${DEPLOY_DIR_IMAGE}/${INITRD_IMAGE}'
    fi

    for file in ${DTB_FILES}; do
        dtb="$(find '${IMAGE_ROOTFS}/usr/lib' -type f \
                    -iwholename '*linux-image-*/'${file} | head -1)"

        if [ -z "$dtb" -o ! -e "$dtb" ]; then
            die "${file} not found"
        fi

        cp -f "$dtb" "${DEPLOY_DIR_IMAGE}/"
    done
}
addtask copy_boot_files before do_rootfs_postprocess after do_rootfs_install

python do_image_tools() {
    """Virtual task"""
    pass
}
addtask image_tools before do_build after do_rootfs

python do_image() {
    """Virtual task"""
    pass
}
addtask image before do_build after do_image_tools

python do_deploy() {
    """Virtual task"""
    pass
}
addtask deploy before do_build after do_image

do_rootfs_finalize() {
    sudo -s <<'EOSUDO'
        set -e
        test -e "${ROOTFSDIR}/chroot-setup.sh" && \
            "${ROOTFSDIR}/chroot-setup.sh" "cleanup" "${ROOTFSDIR}"
        rm -f "${ROOTFSDIR}/chroot-setup.sh"

        test ! -e "${ROOTFSDIR}/usr/share/doc/qemu-user-static" && \
            find "${ROOTFSDIR}/usr/bin" \
                -maxdepth 1 -name 'qemu-*-static' -type f -delete

        mountpoint -q '${ROOTFSDIR}/isar-apt' && \
            umount -l ${ROOTFSDIR}/isar-apt && \
            rmdir --ignore-fail-on-non-empty ${ROOTFSDIR}/isar-apt

        mountpoint -q '${ROOTFSDIR}/base-apt' && \
            umount -l ${ROOTFSDIR}/base-apt && \
            rmdir --ignore-fail-on-non-empty ${ROOTFSDIR}/base-apt

        mountpoint -q '${ROOTFSDIR}/dev' && \
            umount -l ${ROOTFSDIR}/dev
        mountpoint -q '${ROOTFSDIR}/proc' && \
            umount -l ${ROOTFSDIR}/proc
        mountpoint -q '${ROOTFSDIR}/sys' && \
            umount -l ${ROOTFSDIR}/sys

        rm -f "${ROOTFSDIR}/etc/apt/apt.conf.d/55isar-fallback.conf"

        rm -f "${ROOTFSDIR}/etc/apt/sources.list.d/isar-apt.list"
        rm -f "${ROOTFSDIR}/etc/apt/preferences.d/isar-apt"
        rm -f "${ROOTFSDIR}/etc/apt/sources.list.d/base-apt.list"

        mv "${ROOTFSDIR}/etc/apt/sources-list" \
            "${ROOTFSDIR}/etc/apt/sources.list.d/bootstrap.list"

        rm -f "${ROOTFSDIR}/etc/apt/sources-list"
EOSUDO
}
addtask rootfs_finalize before do_rootfs after do_rootfs_postprocess

# Last so that the image type can overwrite tasks if needed
inherit ${IMAGE_FSTYPES}
