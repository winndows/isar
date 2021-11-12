# This software is a part of ISAR.
# Copyright (C) 2015-2018 ilbers GmbH

inherit dpkg-base

PACKAGE_ARCH ?= "${DISTRO_ARCH}"

ISAR_APT_REPO ?= "deb [trusted=yes] file:///home/builder/${PN}/isar-apt/${DISTRO}-${DISTRO_ARCH}/apt/${DISTRO} ${DEBDISTRONAME} main"

# Install build dependencies for package
do_install_isarapt() {
    # Make local copy of isar-apt not affected by other parallel tasks
    mkdir -p ${WORKDIR}/isar-apt/${DISTRO}-${DISTRO_ARCH}
    rm -rf ${WORKDIR}/isar-apt/${DISTRO}-${DISTRO_ARCH}/*
    cp -Rl ${REPO_ISAR_DIR} ${WORKDIR}/isar-apt/${DISTRO}-${DISTRO_ARCH}
}

addtask install_isarapt after do_prepare_build before do_dpkg_build
do_install_isarapt[lockfiles] += "${REPO_ISAR_DIR}/isar.lock"

# Build package from sources using build script
dpkg_runbuild() {
    E="${@ isar_export_proxies(d)}"
    export PARALLEL_MAKE="${PARALLEL_MAKE}"

    distro="${DISTRO}"
    if [ ${ISAR_CROSS_COMPILE} -eq 1 ]; then
        distro="${HOST_DISTRO}"
    fi

    deb_dl_dir_import "${WORKDIR}/rootfs" "${distro}"

    deb_dir="/var/cache/apt/archives/"
    ext_deb_dir="/home/builder/${PN}/rootfs/${deb_dir}"

    ( flock 9
        grep -qxF '$apt_keep_downloaded_packages = 1;' ${SCHROOT_USER_HOME}/.sbuildrc ||
            echo '$apt_keep_downloaded_packages = 1;' >> ${SCHROOT_USER_HOME}/.sbuildrc
    ) 9>"${TMPDIR}/sbuildrc.lock"

    sbuild -A -n -c ${SBUILD_CHROOT} --extra-repository="${ISAR_APT_REPO}" \
        --host=${PACKAGE_ARCH} --build=${SBUILD_HOST_ARCH} \
        --starting-build-commands="runuser -u ${SCHROOT_USER} -- sh -c \"${SBUILD_PREBUILD:-:}\"" \
        --no-run-lintian --no-run-piuparts --no-run-autopkgtest \
        --chroot-setup-commands="cp -n --no-preserve=owner ${ext_deb_dir}/*.deb -t ${deb_dir}/" \
        --finished-build-commands="rm -f ${deb_dir}/sbuild-build-depends-main-dummy_*.deb" \
        --finished-build-commands="cp -n --no-preserve=owner ${deb_dir}/*.deb -t ${ext_deb_dir}/" \
        --build-dir=${WORKDIR} ${WORKDIR}/${PPS}

    deb_dl_dir_export "${WORKDIR}/rootfs" "${distro}"
}
