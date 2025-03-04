Recipe API Changelog
====================

Baseline: Release v0.5

Changes in v0.6
---------------

### Separate do_prepare_build task

All Debianizations of source trees and any further programmatic patching has to
be moved from the dpkg_runbuild() task to this new task.

### ISAR_CROSS_COMPILE support

Isar now supports cross-compilation. When enabled via `ISAR_CROSS_COMPILE = "1"`
in a global configuration file, all recipes that do not overwrite this variable
will build cross-compiled.

If a recipe is not cross-compatible, it should set `ISAR_CROSS_COMPILE = "0"`.
Then also all its dependencies that are built by Isar must opt out from
cross-building.

### wic image type, removal of manual wic invocation

Images that are described by wic files are now generated during the build by
setting `IMAGE_TYPE = "wic-img"`. The manual invocation of wic after the
bitbake run is no longer needed nor supported.

### Optional kernel installation

The installation of a Linux kernel into the isar-image-base can be skipped by
setting `KERNEL_NAME = ""`.

### Corrected semantic of `S`

The `S` variable is now defined as NOT including `WORKDIR`, like in OE, Gentoo
and others. If it was set to, e.g., `S = "sources"` in a recipe so far, it must
be defined as `S = ${WORKDIR}/sources` from now on.

### DISTRO and DISTRO_ARCH are available as OVERRIDES

Bitbake variables can now also refer to the DISTRO as well as the DISTRO_ARCH
for overrides.

### Set ISAR_RELEASE_CMD in own top-layer

Isar now populates /etc/os-release with information about the image. In order
to identify the revision of the top layer that controlled the image build with
all its dependencies, set ISAR_RELEASE_CMD so that it picks up the required
information.

If the top-layer is managed in git, set `LAYERDIR_mylayer = "${LAYERDIR}"` in
`conf/layer.conf` and add something along

    ISAR_RELEASE_CMD = "git -C ${LAYERDIR_mylayer} describe --tags --dirty \
                            --match 'v[0-9].[0-9]*'"

in the image recipe (or `isar-image-base.bbappend`) of that layer.

### ROOTFS_DEV and ROOTFS_TYPE no longer needed

These variables can be removed from own machine.conf or multiconfig files.

If you want to enable support for QEMU in your config (start_vm), specify the
`QEMU_ROOTFS_DEV` and `QEMU_DISK_ARGS` instead.

### KERNEL_NAME_PROVIDED replaces KERNEL_FLAVOR in custom kernels

The matching logic for custom kernel recipes to the selected kernel was
reworked and simplified. If your kernel recipe is called `linux-foo_4.18.bb`,
you now have to set `KERNEL_NAME = "foo"` in order to select that kernel.
Alternatively, a recipe with a different naming scheme can set
`KERNEL_NAME_PROVIDED = "foo"` in order to match as well.

Changes in v0.7
---------------

### dpkg-raw recipes build method changed

These packages are now built using the whole dpkg-buildpackage workflow, and
not just packaged as before.

 - all files will be owned by root:root before it might have been 1000:1000
   use postinst to change that (see example-raw)
 - a lot of debhelpers will help .. or complain
   fix the issues or override the helpers (see example-raw)

### Set LAYERSERIES_COMPAT_*  when an own layer is defined

When defining an own layer LAYERSERIES_COMPAT_mylayer_root_name has to be set,
the possible values are listed in the variable LAYERSERIES_CORENAMES.

If you need to express the fact that your layer requires the
layer version higher than existing release corename, use the value 'next'.

### location of image artifacts

Align with OpenEmbedded and place image artifacts in a per-machine folder placed
in tmp/deploy (to avoid collisions among other things).

### more consistent artifact names

multiconfig image artifacts are all placed in tmp/deploy/images. They include
kernel, initrd and ext4/wic images. A consistent naming scheme is now used:
`IMAGE-DISTRO-MACHINE.TYPE`. This scheme was already used for ext4/wic images
so no visible changes there. Kernel and initrd images are however affected; for
instance:

```
vmlinuz-4.9.0-8-armmp_debian-stretch-qemuarm
```

is now

```
isar-image-base-debian-stretch-qemuarm.vmlinuz-4.9.0-8-armmp
```

It should be noted that the `KERNEL_IMAGE` and `INITRD_IMAGE` variables were
updated hence recipes using them shouldn't be impacted per se.

### Append kernel name to custom module and u-boot-script packages

These packages depend on a specific kernel. Its identification is now appended
to the binary package names in the form "-${KERNEL_NAME}".

### PRESERVE_PERMS needed with dpkg-raw for implicit file permission setting

In order to use the same file permissions for an input file to a dpkg-raw
package on the build machine as well as on the target, its absolute target path
needs to be listed in the PRESERVE_PERMS variable (space-separated list of
files). Otherwise, default permissions are used.

### Reduce requirements on custom module makefiles

It's now sufficient to provide only kbuild rules. Makefile targets like modules
or modules_install as well as KDIR and DESTDIR evaluation are no longer needed.

### Remove setting of root passwords in custom packages

Custom packages that are not installed via the IMAGE_TRANSIENT_PACKAGES and set
a root password, leak that password via its script in /var/lib/dpkg/info.

Instead set the CFG_ROOT_PW variable to the encrypted password and use the
transient 'isar-cfg-rootpw' package (now installed as transient package per
default).

Changes in v0.8
---------------

### `apt://` SRC_URIs where added and briefly changed their version picking way

Recipes that use SRC_URIs with `apt://` and choose a version with `=` had a
partial matching feature for a short time between 0.7 and 0.8. In 0.8 the
version has to be the exact upsteam match.
It is probably best to not specify a version if you can.

### `isar-image.bbclass` class will be deprecated in future version of isar

The content of `isar-image.bbclass` was moved to the `image.bbclass` file.
Recipes that inherit `isar-image` should be modified to inherit from `image`
instead.

### Transient package support was removed

The `LOCALE_GEN` and `LOCALE_DEFAULT` variables are now handled by the
`image-locales-extension` class within the image recipe.

Setting of the root password can now be done by the `image-account-extension`
class within the image recipe. To set the root password to empty, you can
use this code snippet:

```
USERS += "root"
USER_root[password] = ""
USER_root[flags] = "allow-empty-password"
```

Otherwise set a encrypted root password like this:

```
USERS += "root"
USER_root[password] = "$6$rounds=10000$RXeWrnFmkY$DtuS/OmsAS2cCEDo0BF5qQsizIrq6jPgXnwv3PHqREJeKd1sXdHX/ayQtuQWVDHe0KIO0/sVH8dvQm1KthF0d/"
```

### Use FILESEXTRAPATHS to add custom paths to FILESPATH

Direct modification of FILESPATH variable is discouraged. Use FILESEXTRAPATHS
instead to add a custom search path for files and patches. This makes overriding
files and patches using bbappend a lot easier.

For example:
```
FILESEXTRAPATHS_prepend := "$THISDIR/files:"
```

### multiconfig build targets were renamed

bitbake was upgraded to version 1.44.0 where "multiconfig" build targets were
renamed "mc". As an example, builds for the qemuarm-stretch machine should now
be done as follows:

```
bitbake mc:qemuarm-stretch:isar-image-base
```

The old syntax is no longer supported and will produce an error:

```
bitbake multiconfig:qemuarm-stretch:isar-image-base
```

### Support for kernel config fragments

Kernels built via linux-custom.inc will now get configuration fragments listed
in SRC_URI automatically applied. Config fragment files need to end on .cfg.
If such a file should not by applied, append `;apply=no` to the respective
SRC_URI entry.

### Control over kernel's LOCALVERSION via LINUX_VERSION_EXTENSION

In order to get a LOCALVERSION appendix into both the kernel config and the
version information of the self-built packages, the LINUX_VERSION_EXTENSION is
now available. It remains empty by default unless a recipe sets it. The
appended version usually starts with a "-".

### Image task `cache_base_repo` was removed

That task used to be at the end of a cache-warming build, a follow-up build
with `ISAR_USE_CACHED_BASE_REPO` did use that. Now we cache all downloads
anyway, if `ISAR_USE_CACHED_BASE_REPO` is set a build will use all the
downloads from previous builds for the cache.

### Renamed DTB_FILE to DTB_FILES, adding support for multiple entries

DTB_FILES now allows to specify multiple DTBs that should be deployed for
consumption by imaging classes.

### Add DEBIAN_BUILD_DEPENDS as deb_debianize parameter

Additional build dependencies of auto-debianized packages can now be defined
by setting DEBIAN_BUILD_DEPENDS.

### Separation of ${S} and ${D} in dpkg-raw

${S} can now be used for checking out sources without being linked implicitly
with ${D} which needs to be filled explicitly in do_install as before.

### Remove ISARROOT from bitbake environment

ISARROOT variable is now removed from the bitbake environment. It is unset
after the initial setup. It is replaced with dedicated variables like
BITBAKEDIR, SCRIPTSDIR and TESTSUITEDIR.

### Wic adds /boot mountpoint to fstab

In the older version of wic, any mount point named /boot is skipped from adding
into the fstab entry.

With the latest wic, this is not the case. /boot mount point, if any, is added
to /etc/fstab for automount.

Any wks file which assumed that /boot would be skipped from /etc/fstab should
now be corrected. Otherwise, it might conflict with the original /boot contents,
i.e kernel initrd & config files will be unavailable after boot.

Below is an example wks entry that might cause an issue.
The efi partition created using bootimg-efi-isar plugin has only the efi stub in
it. The kernel and initrd are present in the root(/) partition.
Now with the latest wic which adds the /boot mount point to fstab, the /boot
contents of "part /" would be unavailable after boot. This would break the
kernel updates done via apt-get.

```
part /boot --source bootimg-efi-isar --sourceparams "loader=grub-efi" --ondisk sda --label efi --part-type EF00 --align 1024
part / --source rootfs --ondisk sda --fstype ext4 --label platform --align 1024 --use-uuid
```
In this case we can either drop the /boot mountpoint or use some other mountpoint
like /boot/efi to avoid such issues.

### Deprecate BUILD_DEPENDS in u-boot-custom.inc

Use DEBIAN_BUILD_DEPENDS instead, to align with deb_debianize.

### Default to PATCHTOOL ?= "git" for dpkg-gbp

Migrate your patches so they can be applied with "git am", or
"unset PATCHTOOL" to get old behaviour.

### Change kernel image name for arm64

Kernel image name for arm64 platforms is vmlinux now. Image format was
not changed (uncompressed executable) but now it is named correctly.

### wic plugins for efi and pcbios use seperate /boot partition

It used to depend on the bootloader whether stuff was in in the root partition or in the boot partition, now it will always be in the boot partition.

Kernel update with "apt-get" will not work since bootloader configuration will
not be updated. It used to "kind of work" for grub and efi, that hack is gone.

When using the plugins it is advised to name the partition "/boot" and to exclude boot from the follwing rootfs to not waste space.
