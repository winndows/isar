# This software is a part of ISAR.
# Copyright (C) 2017-2019 Siemens AG
#
# SPDX-License-Identifier: MIT

inherit dpkg

D = "${S}"

# Populate folder that will be picked up as package
do_install() {
	bbnote "Put your files for this package in $""{D}"
}

do_install[cleandirs] = "${D}"
addtask install after do_patch do_transform_template before do_prepare_build

do_prepare_build[cleandirs] += "${S}/debian"
do_prepare_build() {
	cd ${D}
	find . -maxdepth 1 ! -name .. -and ! -name . -and ! -name debian | \
		sed 's:^./::' > ${S}/debian/${PN}.install

	deb_debianize
}
