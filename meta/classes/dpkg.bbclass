# This software is a part of ISAR.
# Copyright (C) 2015-2018 ilbers GmbH

inherit dpkg-base

PACKAGE_ARCH ?= "${DISTRO_ARCH}"

# Install build dependencies for package
do_install_builddeps() {
    dpkg_do_mounts
    E="${@ isar_export_proxies(d)}"
    distro="${DISTRO}"
    if [ ${ISAR_CROSS_COMPILE} -eq 1 ]; then
       distro="${HOST_DISTRO}"
    fi
    deb_dl_dir_import "${BUILDCHROOT_DIR}" "${distro}"
    sudo -E chroot ${BUILDCHROOT_DIR} /isar/deps.sh \
        ${PP}/${PPS} ${PACKAGE_ARCH} --download-only
    deb_dl_dir_export "${BUILDCHROOT_DIR}" "${distro}"
    sudo -E chroot ${BUILDCHROOT_DIR} /isar/deps.sh \
        ${PP}/${PPS} ${PACKAGE_ARCH}
    dpkg_undo_mounts
}

addtask install_builddeps after do_prepare_build before do_dpkg_build
# apt and reprepro may not run in parallel, acquire the Isar lock
do_install_builddeps[lockfiles] += "${REPO_ISAR_DIR}/isar.lock"

addtask devshell after do_install_builddeps

ISAR_APT_REPO ?= "deb [trusted=yes] file:///isar-apt/${DISTRO}-${DISTRO_ARCH}/apt/${DISTRO} ${DEBDISTRONAME} main"

# Build package from sources using build script
dpkg_runbuild() {
    E="${@ isar_export_proxies(d)}"
    export PARALLEL_MAKE="${PARALLEL_MAKE}"

    schroot_create_configs

    sbuild -A -n -c ${SBUILD_CHROOT} --extra-repository="${ISAR_APT_REPO}" \
        --host=${PACKAGE_ARCH} --build=${SBUILD_HOST_ARCH} \
        --starting-build-commands="runuser -u ${SCHROOT_USER} -- sh -c \"${SBUILD_PREBUILD:-:}\"" \
        --no-run-lintian --no-run-piuparts --no-run-autopkgtest \
        --build-dir=${WORKDIR} ${WORKDIR}/${PPS}

    schroot_delete_configs
}
