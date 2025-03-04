# This software is a part of ISAR.
# Copyright (C) Siemens AG, 2019
#
# SPDX-License-Identifier: MIT

python() {
    if not d.getVar("MKUBIFS_ARGS"):
        raise bb.parse.SkipRecipe("mkubifs_args must be set")
}

UBIFS_IMAGE_FILE ?= "${IMAGE_FULLNAME}.ubifs.img"

IMAGER_INSTALL += "mtd-utils"

# glibc bug 23960 https://sourceware.org/bugzilla/show_bug.cgi?id=23960
# should not use QEMU on armhf target with mkfs.ubifs < v2.1.3
ISAR_CROSS_COMPILE_armhf = "1"

# Generate ubifs filesystem image
do_ubifs_image() {
    rm -f '${DEPLOY_DIR_IMAGE}/${UBIFS_IMAGE_FILE}'

    image_do_mounts

    # Create ubifs image using buildchroot tools
    sudo chroot ${BUILDCHROOT_DIR} /usr/sbin/mkfs.ubifs ${MKUBIFS_ARGS} \
                -r '${PP_ROOTFS}' '${PP_DEPLOY}/${UBIFS_IMAGE_FILE}'
    sudo chown $(id -u):$(id -g) '${DEPLOY_DIR_IMAGE}/${UBIFS_IMAGE_FILE}'
}

addtask ubifs_image before do_image after do_image_tools
