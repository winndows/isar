# This software is a part of ISAR.
# Copyright (c) Siemens AG, 2019
#
# SPDX-License-Identifier: MIT

inherit dpkg

S = "${WORKDIR}/git"

PATCHTOOL ?= "git"

GBP_DEPENDS ?= "git-buildpackage pristine-tar"
GBP_EXTRA_OPTIONS ?= "--git-pristine-tar"

do_install_builddeps_append() {
    schroot_install "${GBP_DEPENDS}"
}

SCHROOT_MOUNTS = "${WORKDIR}:${PP} ${GITDIR}:/home/.git-downloads"

dpkg_runbuild_prepend() {
    schroot_run -d ${PP}/${PPS} -c ${SBUILD_CHROOT} -- \
        gbp buildpackage --git-builder=/bin/true ${GBP_EXTRA_OPTIONS}
    # NOTE: `buildpackage --git-builder=/bin/true --git-pristine-tar` is used
    # for compatibility with gbp version froms debian-stretch. In newer distros
    # it's possible to use a subcommand `export-orig --pristine-tar`
}
