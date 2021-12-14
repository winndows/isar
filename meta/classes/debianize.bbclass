# This software is a part of ISAR.
# Copyright (C) 2017-2019 Siemens AG
# Copyright (C) 2021 Siemens Mobility GmbH
#
# SPDX-License-Identifier: MIT

CHANGELOG_V ??= "${PV}"
DPKG_ARCH ??= "any"
DEBIAN_BUILD_DEPENDS ??= ""
DEBIAN_DEPENDS ??= ""
DEBIAN_CONFLICTS ??= ""
DESCRIPTION ??= "must not be empty"
MAINTAINER ??= "Unknown maintainer <unknown@example.com>"

deb_add_changelog() {
	changelog_v="${CHANGELOG_V}"
	timestamp=0
	if [ -f ${S}/debian/changelog ]; then
		if [ ! -f ${WORKDIR}/changelog.orig ]; then
			cp ${S}/debian/changelog ${WORKDIR}/changelog.orig
		fi
		orig_version=$(dpkg-parsechangelog -l ${WORKDIR}/changelog.orig -S Version)
		changelog_v=$(echo "${changelog_v}" | sed 's/<orig-version>/'${orig_version}'/')
		orig_date=$(dpkg-parsechangelog -l ${WORKDIR}/changelog.orig -S Date)
		orig_seconds=$(date --date="${orig_date}" +'%s')
		timestamp=$(expr ${orig_seconds} + 42)
	fi

	date=$(LANG=C date -R -d @${timestamp})
	cat <<EOF > ${S}/debian/changelog
${PN} (${changelog_v}) UNRELEASED; urgency=low

  * generated by Isar

 -- ${MAINTAINER}  ${date}
EOF
	if [ -f ${WORKDIR}/changelog ]; then
		latest_version=$(dpkg-parsechangelog -l ${WORKDIR}/changelog -S Version)
		if [ "${latest_version}" = "${changelog_v}" ]; then
			# entry for our version already there, use unmodified
			rm ${S}/debian/changelog
		else
			# prepend our entry to an existing changelog
			echo >> ${S}/debian/changelog
		fi
		cat ${WORKDIR}/changelog >> ${S}/debian/changelog
	fi
}

deb_create_compat() {
	echo 10 > ${S}/debian/compat
}

deb_create_control() {
	compat=$( cat ${S}/debian/compat )
	cat << EOF > ${S}/debian/control
Source: ${PN}
Section: misc
Priority: optional
Standards-Version: 3.9.6
Maintainer: ${MAINTAINER}
Build-Depends: debhelper (>= ${compat}), ${DEBIAN_BUILD_DEPENDS}

Package: ${PN}
Architecture: ${DPKG_ARCH}
Depends: ${DEBIAN_DEPENDS}
Conflicts: ${DEBIAN_CONFLICTS}
Description: ${DESCRIPTION}
EOF
}

DH_FIXPERM_EXCLUSIONS = \
    "${@' '.join(['-X ' + x for x in \
                  (d.getVar('PRESERVE_PERMS', False) or '').split()])}"

deb_create_rules() {
	cat << EOF > ${S}/debian/rules
#!/usr/bin/make -f

override_dh_fixperms:
	dh_fixperms ${DH_FIXPERM_EXCLUSIONS}

%:
	dh \$@
EOF
	chmod +x ${S}/debian/rules
}

deb_debianize() {
	install -m 755 -d ${S}/debian

	# create the compat-file if there is no file with that name in WORKDIR
	if [ -f ${WORKDIR}/compat ]; then
		install -v -m 644 ${WORKDIR}/compat ${S}/debian/compat
	else
		deb_create_compat
	fi
	# create the control-file if there is no control-file in WORKDIR
	if [ -f ${WORKDIR}/control ]; then
		install -v -m 644 ${WORKDIR}/control ${S}/debian/control
	else
		deb_create_control
	fi
	# create rules if WORKDIR does not contain a rules-file
	if [ -f ${WORKDIR}/rules ]; then
		install -v -m 755 ${WORKDIR}/rules ${S}/debian/rules
	else
		deb_create_rules
	fi
	# prepend a changelog-entry unless an existing changelog file already
	# contains an entry with CHANGELOG_V
	deb_add_changelog

	# copy all hooks from WORKDIR into debian/, hooks are not generated
	for t in pre post
	do
		for a in inst rm
		do
			if [ -f ${WORKDIR}/${t}${a} ]; then
				install -v -m 755 ${WORKDIR}/${t}${a} \
					${S}/debian/${t}${a}
			fi
		done
	done
}
