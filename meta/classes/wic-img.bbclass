# This software is a part of ISAR.
# Copyright (C) 2018 Siemens AG
#
# this class is heavily inspired by OEs ./meta/classes/image_types_wic.bbclass
#

WKS_FILE_CHECKSUM = "${@'${WKS_FULL_PATH}:%s' % os.path.exists('${WKS_FULL_PATH}')}"

do_copy_wks_template[file-checksums] += "${WKS_FILE_CHECKSUM}"
do_copy_wks_template () {
    cp -f '${WKS_TEMPLATE_PATH}' '${WORKDIR}/${WKS_TEMPLATE_FILE}'
}

python () {
    import itertools
    import re

    wks_full_path = None

    wks_file = d.getVar('WKS_FILE', True)
    if not wks_file:
        bb.fatal("WKS_FILE must be set")
    if not wks_file.endswith('.wks') and not wks_file.endswith('.wks.in'):
        wks_file += '.wks'

    if os.path.isabs(wks_file):
        if os.path.exists(wks_file):
            wks_full_path = wks_file
    else:
        bbpaths = d.getVar('BBPATH', True).split(':')
        corebase_paths = bbpaths

        corebase = d.getVar('COREBASE', True)
        if corebase is not None:
            corebase_paths.append(corebase)

        search_path = ":".join(itertools.chain(
            (p + "/wic" for p in bbpaths),
            (l + "/scripts/lib/wic/canned-wks"
             for l in (corebase_paths)),
        ))
        wks_full_path = bb.utils.which(search_path, wks_file)

    if not wks_full_path:
        bb.fatal("WKS_FILE '{}' not found".format(wks_file))

    d.setVar('WKS_FULL_PATH', wks_full_path)

    wks_file_u = wks_full_path
    wks_file = wks_full_path
    base, ext = os.path.splitext(wks_file)
    if ext == '.in' and os.path.exists(wks_file):
        wks_out_file = os.path.join(d.getVar('WORKDIR'), os.path.basename(base))
        d.setVar('WKS_FULL_PATH', wks_out_file)
        d.setVar('WKS_TEMPLATE_PATH', wks_file_u)
        d.setVar('WKS_FILE_CHECKSUM', '${WKS_TEMPLATE_PATH}:True')

        wks_template_file = os.path.basename(base) + '.tmpl'
        d.setVar('WKS_TEMPLATE_FILE', wks_template_file)
        d.appendVar('TEMPLATE_FILES', " {}".format(wks_template_file))

        # We need to re-parse each time the file changes, and bitbake
        # needs to be told about that explicitly.
        bb.parse.mark_dependency(d, wks_file)

        expand_var_regexp = re.compile(r"\${(?P<name>[^{}@\n\t :]+)}")

        try:
            with open(wks_file, 'r') as f:
                d.appendVar("TEMPLATE_VARS", " {}".format(
                    " ".join(expand_var_regexp.findall(f.read()))))
        except (IOError, OSError) as exc:
            pass
        else:
            bb.build.addtask('do_copy_wks_template', 'do_transform_template do_wic_image', None, d)
            bb.build.addtask('do_transform_template', 'do_wic_image', None, d)
}

inherit buildchroot

IMAGER_INSTALL += "${WIC_IMAGER_INSTALL}"
# wic comes with reasonable defaults, and the proper interface is the wks file
ROOTFS_EXTRA ?= "0"

STAGING_DATADIR ?= "/usr/lib/"
STAGING_LIBDIR ?= "/usr/lib/"
STAGING_DIR ?= "${TMPDIR}"
IMAGE_BASENAME ?= "${PN}-${DISTRO}"
FAKEROOTCMD ?= "${SCRIPTSDIR}/wic_fakeroot"
RECIPE_SYSROOT_NATIVE ?= "/"
BUILDCHROOT_DIR = "${BUILDCHROOT_TARGET_DIR}"

WIC_CREATE_EXTRA_ARGS ?= ""

# taken from OE, do not touch directly
WICVARS += "\
           BBLAYERS IMGDEPLOYDIR DEPLOY_DIR_IMAGE FAKEROOTCMD IMAGE_BASENAME IMAGE_BOOT_FILES \
           IMAGE_LINK_NAME IMAGE_ROOTFS INITRAMFS_FSTYPES INITRD INITRD_LIVE ISODIR RECIPE_SYSROOT_NATIVE \
           ROOTFS_SIZE STAGING_DATADIR STAGING_DIR STAGING_LIBDIR TARGET_SYS TRANSLATED_TARGET_ARCH"

# Isar specific vars used in our plugins
WICVARS += "DISTRO DISTRO_ARCH"

python do_rootfs_wicenv () {
    wicvars = d.getVar('WICVARS', True)
    if not wicvars:
        return

    stdir = d.getVar('STAGING_DIR', True)
    outdir = os.path.join(stdir, d.getVar('MACHINE', True), 'imgdata')
    bb.utils.mkdirhier(outdir)
    basename = d.getVar('IMAGE_BASENAME', True)
    with open(os.path.join(outdir, basename) + '.env', 'w') as envf:
        for var in wicvars.split():
            value = d.getVar(var, True)
            if value:
                envf.write('{}="{}"\n'.format(var, value.strip()))

    # this part is stolen from OE ./meta/recipes-core/meta/wic-tools.bb
    with open(os.path.join(outdir, "wic-tools.env"), 'w') as envf:
        for var in ('RECIPE_SYSROOT_NATIVE', 'STAGING_DATADIR', 'STAGING_LIBDIR'):
            envf.write('{}="{}"\n'.format(var, d.getVar(var, True).strip()))

}

addtask do_rootfs_wicenv after do_rootfs before do_wic_image
do_rootfs_wicenv[vardeps] += "${WICVARS}"
do_rootfs_wicenv[prefuncs] = 'set_image_size'

WIC_IMAGE_FILE ="${DEPLOY_DIR_IMAGE}/${IMAGE_FULLNAME}.wic.img"

python check_for_wic_warnings() {
    with open("{}/log.do_wic_image".format(d.getVar("T"))) as f:
        for line in f.readlines():
            if line.startswith("WARNING"):
                bb.warn(line.strip())
}

do_wic_image[file-checksums] += "${WKS_FILE_CHECKSUM}"
python do_wic_image() {
    cmds = ['wic_do_mounts', 'generate_wic_image', 'check_for_wic_warnings']
    weights = [5, 90, 5]
    progress_reporter = bb.progress.MultiStageProgressReporter(d, weights)

    for cmd in cmds:
        progress_reporter.next_stage()
        bb.build.exec_func(cmd, d)
    progress_reporter.finish()
}
addtask wic_image before do_image after do_image_tools

wic_do_mounts() {
    buildchroot_do_mounts
    sudo -s <<'EOSUDO'
        ( flock 9
        for dir in ${BBLAYERS} ${STAGING_DIR} ${SCRIPTSDIR} ${BITBAKEDIR}; do
            mkdir -p ${BUILDCHROOT_DIR}/$dir
            if ! mountpoint ${BUILDCHROOT_DIR}/$dir >/dev/null 2>&1; then
                mount --bind --make-private $dir ${BUILDCHROOT_DIR}/$dir
            fi
        done
        ) 9>${MOUNT_LOCKFILE}
EOSUDO
}

generate_wic_image() {
    export FAKEROOTCMD=${FAKEROOTCMD}
    export BUILDDIR=${BUILDDIR}
    export MTOOLS_SKIP_CHECK=1
    mkdir -p ${IMAGE_ROOTFS}/../pseudo
    touch ${IMAGE_ROOTFS}/../pseudo/files.db

    # create the temp dir in the buildchroot to ensure uniqueness
    WICTMP=$(cd ${BUILDCHROOT_DIR}; mktemp -d -p tmp)

    sudo -E chroot ${BUILDCHROOT_DIR} \
        sh -c ' \
          BITBAKEDIR="$1"
          SCRIPTSDIR="$2"
          WKS_FULL_PATH="$3"
          STAGING_DIR="$4"
          MACHINE="$5"
          WICTMP="$6"
          IMAGE_FULLNAME="$7"
          IMAGE_BASENAME="$8"
          shift 8
          # The python path is hard-coded as /usr/bin/python3-native/python3 in wic. Handle that.
          mkdir -p /usr/bin/python3-native/
          if [ $(head -1 $(which bmaptool) | grep python3) ];then
            ln -fs /usr/bin/python3 /usr/bin/python3-native/python3
          else
            ln -fs /usr/bin/python2 /usr/bin/python3-native/python3
          fi
          export PATH="$BITBAKEDIR/bin:$PATH"
          "$SCRIPTSDIR"/wic create "$WKS_FULL_PATH" \
            --vars "$STAGING_DIR/$MACHINE/imgdata/" \
            -o "/$WICTMP/${IMAGE_FULLNAME}.wic/" \
            --bmap \
            -e "$IMAGE_BASENAME" $@' \
              my_script "${BITBAKEDIR}" "${SCRIPTSDIR}" "${WKS_FULL_PATH}" "${STAGING_DIR}" \
              "${MACHINE}" "${WICTMP}" "${IMAGE_FULLNAME}" "${IMAGE_BASENAME}" \
              ${WIC_CREATE_EXTRA_ARGS}

    sudo chown -R $(stat -c "%U" ${LAYERDIR_core}) ${LAYERDIR_core} ${LAYERDIR_isar} ${SCRIPTSDIR} || true
    sudo chown -R $(id -u):$(id -g) ${BUILDCHROOT_DIR}/${WICTMP}
    find ${BUILDCHROOT_DIR}/${WICTMP} -type f -name "*.direct*" | while read f; do
        suffix=$(basename $f | sed 's/\(.*\)\(\.direct\)\(.*\)/\3/')
        mv -f ${f} ${WIC_IMAGE_FILE}${suffix}
    done
    rm -rf ${BUILDCHROOT_DIR}/${WICTMP}
    rm -rf ${IMAGE_ROOTFS}/../pseudo
}
