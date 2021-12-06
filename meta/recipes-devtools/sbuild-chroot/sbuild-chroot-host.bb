# Root filesystem for packages building
#
# This software is a part of ISAR.
# Copyright (C) 2015-2021 ilbers GmbH

DESCRIPTION = "Isar sbuild/schroot filesystem for host"

SBUILD_VARIANT = "host"

require sbuild-chroot.inc

ROOTFS_ARCH = "${HOST_ARCH}"
ROOTFS_DISTRO = "${HOST_DISTRO}"
