# This software is a part of ISAR.
inherit dpkg-raw

DESCRIPTION = "Configuration to exclude most documentation"
MAINTAINER = "isar-users <isar-users@googlegroups.com>"

SRC_URI = "file://${PN} \
	   file://postinst"

do_install[cleandirs] += "${D}/etc/dpkg/dpkg.conf.d/"

do_install() {
    install -v -m 644 "${WORKDIR}/${PN}" "${D}/etc/dpkg/dpkg.conf.d/99${PN}"
}
