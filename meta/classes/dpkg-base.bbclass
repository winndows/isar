# This software is a part of ISAR.
# Copyright (C) 2017-2019 Siemens AG
# Copyright (C) 2019 ilbers GmbH
#
# SPDX-License-Identifier: MIT

inherit sbuild
inherit debianize
inherit terminal
inherit repository
inherit deb-dl-dir

DEPENDS ?= ""

DEPENDS_append_riscv64 = "${@' crossbuild-essential-riscv64' if d.getVar('ISAR_CROSS_COMPILE', True) == '1' and d.getVar('PN') != 'crossbuild-essential-riscv64' else ''}"

ISAR_APT_REPO ?= "deb [trusted=yes] file:///home/builder/${PN}/isar-apt/${DISTRO}-${DISTRO_ARCH}/apt/${DISTRO} ${DEBDISTRONAME} main"

python do_adjust_git() {
    import subprocess

    rootdir = d.getVar('WORKDIR', True)

    git_link = os.path.join(d.getVar('GIT_DL_LINK_DIR'), '.git-downloads')
    git_dl = os.path.join(d.getVar("DL_DIR"), "git")

    if not os.path.exists(git_link) or os.path.realpath(git_link) != git_dl:
        os.symlink(git_dl, git_link)

    for src_uri in (d.getVar("SRC_URI", True) or "").split():
        try:
            fetcher = bb.fetch2.Fetch([src_uri], d)
            ud = fetcher.ud[src_uri]
            if ud.type != 'git':
                continue

            if os.path.islink(ud.localpath):
                realpath = os.path.realpath(ud.localpath)
                filter_out = os.path.join(d.getVar("DL_DIR"), "git") + "/"
                if realpath.startswith(filter_out):
                    # make the link relative
                    link = realpath.replace(filter_out, '', 1)
                    os.unlink(ud.localpath)
                    os.symlink(link, ud.localpath)

            subdir = ud.parm.get("subpath", "")
            if subdir != "":
                def_destsuffix = "%s/" % os.path.basename(subdir.rstrip('/'))
            else:
                def_destsuffix = "git/"

            destsuffix = ud.parm.get("destsuffix", def_destsuffix)
            destdir = ud.destdir = os.path.join(rootdir, destsuffix)

            git_link_rel = os.path.relpath(git_link,
                                           os.path.join(destdir, ".git/objects"))

            alternates = os.path.join(destdir, ".git/objects/info/alternates")

            if os.path.exists(alternates):
                cmd = ["sed", "-i", alternates, "-e",
                       "s|{}|{}|".format(git_dl, git_link_rel)]
                bb.note(' '.join(cmd))
                if subprocess.call(cmd) != 0:
                    bb.fatal("git alternates adjustment failed")
        except bb.fetch2.BBFetchException as e:
            bb.fatal(str(e))
}

addtask adjust_git after do_unpack before do_patch
do_adjust_git[lockfiles] += "${DL_DIR}/git/isar.lock"

inherit patch
addtask patch after do_adjust_git before do_dpkg_build

SRC_APT ?= ""

# filter out all "apt://" URIs out of SRC_URI and stick them into SRC_APT
python() {
    src_uri = (d.getVar('SRC_URI') or "").split()

    prefix = "apt://"
    new_src_uri = []
    src_apt = []
    for u in src_uri:
        if u.startswith(prefix):
            src_apt.append(u[len(prefix) :])
        else:
            new_src_uri.append(u)

    d.setVar('SRC_URI', ' '.join(new_src_uri))
    d.prependVar('SRC_APT', ' '.join(src_apt))

    if d.getVar('SRC_APT').strip() == '':
        d.setVarFlag('do_apt_fetch', 'noexec', '1')
        d.setVarFlag('do_apt_unpack', 'noexec', '1')
        d.setVarFlag('do_cleanall_apt', 'noexec', '1')
}

do_apt_fetch() {
    schroot_create_configs
    for uri in "${SRC_APT}"; do
        schroot -d / -c ${SBUILD_CHROOT} -- \
            sh -c 'mkdir -p /downloads/deb-src/"$1"/"$2" && cd /downloads/deb-src/"$1"/"$2" && apt-get -y --download-only --only-source source "$2"' my_script "${DISTRO}" "${uri}"
    done
    schroot_delete_configs
}

addtask apt_fetch after do_unpack before do_apt_unpack
do_apt_fetch[lockfiles] += "${REPO_ISAR_DIR}/isar.lock"

# Add dependency from the correct schroot: host or target
do_apt_fetch[depends] = "${SCHROOT_DEP}"

do_apt_unpack() {
    rm -rf ${S}
    schroot_create_configs
    for uri in "${SRC_APT}"; do
        schroot -d / -c ${SBUILD_CHROOT} -- \
            sh -c ' \
                set -e
                dscfile="$(apt-get -y -qq --print-uris --only-source source "${2}" | cut -d " " -f2 | grep -E "*.dsc")"
                cd ${PP}
                cp /downloads/deb-src/"${1}"/"${2}"/* ${PP}
                dpkg-source -x "${dscfile}" "${PPS}"' \
                    my_script "${DISTRO}" "${uri}"
    done
    schroot_delete_configs
}

addtask apt_unpack after do_apt_fetch before do_patch

addtask cleanall_apt before do_cleanall
do_cleanall_apt[nostamp] = "1"
do_cleanall_apt() {
    for uri in "${SRC_APT}"; do
        rm -rf "${DEBSRCDIR}"/"${DISTRO}"/"$uri"
    done
}

def get_package_srcdir(d):
    s = os.path.abspath(d.getVar("S", True))
    workdir = os.path.abspath(d.getVar("WORKDIR", True))
    if os.path.commonpath([s, workdir]) == workdir:
        if s == workdir:
            bb.warn('S is not a subdir of WORKDIR debian package operations' +
                    ' will not work for this recipe.')
        return s[len(workdir)+1:]
    bb.warn('S does not start with WORKDIR')
    return s

# Each package should have its own unique build folder, so use
# recipe name as identifier
PP = "/home/builder/${PN}"
PPS ?= "${@get_package_srcdir(d)}"

# Empty do_prepare_build() implementation, to be overwritten if needed
do_prepare_build() {
    true
}

addtask prepare_build after do_patch do_transform_template before do_dpkg_build
# If Isar recipes depend on each other, they typically need the package
# deployed to isar-apt
do_prepare_build[deptask] = "do_deploy_deb"

do_prepare_build[depends] = "${SCHROOT_DEP}"

do_prepare_build_append() {
    # Make a local copy of isar-apt repo that is not affected by other parallel builds
    mkdir -p ${WORKDIR}/isar-apt/${DISTRO}-${DISTRO_ARCH}
    rm -rf ${WORKDIR}/isar-apt/${DISTRO}-${DISTRO_ARCH}/*
    cp -Rl ${REPO_ISAR_DIR} ${WORKDIR}/isar-apt/${DISTRO}-${DISTRO_ARCH}
}
do_prepare_build[lockfiles] += "${REPO_ISAR_DIR}/isar.lock"

# Placeholder for actual dpkg_runbuild() implementation
dpkg_runbuild() {
    die "This should never be called, overwrite it in your derived class"
}

python do_dpkg_build() {
    bb.build.exec_func('schroot_create_configs', d)
    try:
        bb.build.exec_func("dpkg_runbuild", d)
    finally:
        bb.build.exec_func('schroot_delete_configs', d)
}

addtask dpkg_build

SSTATETASKS += "do_dpkg_build"
DPKG_SSTATE = "${WORKDIR}/dpkg-sstate"
do_dpkg_build[dirs] += "${DPKG_SSTATE} ${S}/.."
do_dpkg_build[cleandirs] += "${DPKG_SSTATE}"
do_dpkg_build[sstate-plaindirs] = "${DPKG_SSTATE}"
do_dpkg_build[sstate-interceptfuncs] = "dpkg_build_sstate_prepare"

dpkg_build_sstate_prepare() {
    test -n "$(find ${S}/.. -maxdepth 1 -name '*.deb' -print -quit)" &&
        ln -f ${S}/../*.deb -t ${DPKG_SSTATE}
}

dpkg_build_sstate_finalize() {
    test -n "$(find ${DPKG_SSTATE} -maxdepth 1 -name '*.deb' -print -quit)" &&
        ln -f ${DPKG_SSTATE}/*.deb -t ${S}/..
}

python do_dpkg_build_setscene() {
    sstate_setscene(d)
    bb.build.exec_func('dpkg_build_sstate_finalize', d)
}

addtask dpkg_build_setscene
do_dpkg_build_setscene[dirs] += "${S}/.."

do_dpkg_build[depends] = "${SCHROOT_DEP}"

CLEANFUNCS += "deb_clean"

deb_clean() {
    DEBS=$( find ${S}/.. -maxdepth 1 -name "*.deb" || [ ! -d ${S} ] )
    if [ -n "${DEBS}" ]; then
        for d in ${DEBS}; do
            repo_del_package "${REPO_ISAR_DIR}"/"${DISTRO}" \
                "${REPO_ISAR_DB_DIR}"/"${DISTRO}" "${DEBDISTRONAME}" "${d}"
        done
    fi
}

do_deploy_deb() {
    deb_clean
    repo_add_packages "${REPO_ISAR_DIR}"/"${DISTRO}" \
        "${REPO_ISAR_DB_DIR}"/"${DISTRO}" "${DEBDISTRONAME}" ${S}/../*.deb
}

addtask deploy_deb after do_dpkg_build before do_build
do_deploy_deb[deptask] = "do_deploy_deb"
do_deploy_deb[depends] += "isar-apt:do_cache_config"
do_deploy_deb[lockfiles] = "${REPO_ISAR_DIR}/isar.lock"
do_deploy_deb[dirs] = "${S}"

python do_devshell() {
    bb.build.exec_func('schroot_create_configs', d)

    isar_export_proxies(d)

    schroot = d.getVar('SBUILD_CHROOT')
    isar_apt = d.getVar('ISAR_APT_REPO')
    pp_pps = os.path.join(d.getVar('PP'), d.getVar('PPS'))

    install_deps = ":" if d.getVar('BB_CURRENTTASK') == "devshell_nodeps" else "mk-build-deps -i -t \
        \"apt-get -y -q -o Debug::pkgProblemResolver=yes --no-install-recommends --allow-downgrades\" \
        debian/control"

    termcmd = "schroot -d / -c {0} -u root -- sh -c ' \
        cd {1}; \
        echo {2} > /etc/apt/sources.list.d/isar_apt.list; \
        apt-get -y -q update; \
        {3}; \
        $SHELL -i \
    '"
    oe_terminal(termcmd.format(schroot, pp_pps, isar_apt, install_deps), "Isar devshell", d)

    bb.build.exec_func('schroot_delete_configs', d)
}

addtask devshell after do_prepare_build
DEVSHELL_STARTDIR ?= "${S}"
do_devshell[dirs] = "${DEVSHELL_STARTDIR}"
do_devshell[nostamp] = "1"

python do_devshell_nodeps() {
    bb.build.exec_func('do_devshell', d)
}

# devshell may be placed after do_instell_builddeps in downstream classes.
# devshell_nodeps will always stay right after do_prepare_build.
addtask devshell_nodeps after do_prepare_build
do_devshell_nodeps[dirs] = "${DEVSHELL_STARTDIR}"
do_devshell_nodeps[nostamp] = "1"
