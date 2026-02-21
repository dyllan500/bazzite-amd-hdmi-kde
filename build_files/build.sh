#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
# dnf5 install -y tmux 

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

# systemctl enable podman.socket

pushd /usr/lib/kernel/install.d
mv 05-rpmostree.install 05-rpmostree.install.bak
mv 50-dracut.install 50-dracut.install.bak
printf '%s\n' '#!/bin/sh' 'exit 0' > 05-rpmostree.install
printf '%s\n' '#!/bin/sh' 'exit 0' > 50-dracut.install
chmod +x  05-rpmostree.install 50-dracut.install
popd

pkgs=(
    kernel
    kernel-core
    kernel-modules
    kernel-modules-core
    kernel-modules-extra
    kernel-modules-akmods
    kernel-devel
    kernel-devel-matched
    kernel-tools
    kernel-tools-libs
    kernel-common
)

dnf5 -y remove --no-autoremove ${pkgs[@]}

cat /ctx/KF?? > /tmp/kernel-6.18.0+-11.x86_64.rpm

dnf5 --setopt=disable_excludes=* install -y /ctx/kernel-*.rpm /tmp/kernel-*.rpm

pushd /usr/lib/kernel/install.d
mv -f 05-rpmostree.install.bak 05-rpmostree.install
mv -f 50-dracut.install.bak 50-dracut.install
popd

# If images already installed cliwrap, use it. Only used in transition period, so it should be removed when base images like Ublue remove cliwrap
if [ -f "/usr/libexec/rpm-ostree/wrapped/dracut" ]; then
  DRACUT="/usr/libexec/rpm-ostree/wrapped/dracut"
else
  DRACUT="/usr/bin/dracut"
fi

# NOTE!
# This won't work when Fedora starts to utilize UKIs (Unified Kernel Images).
# UKIs will contain kernel + initramfs + bootloader.
# Refactor the module to support UKIs once they are starting to be used, if possible.
# That won't be soon, so this module should work for good period of time

kernel_count=0
for kernel_path in /usr/lib/modules/*/; do
  kernel_count=$(( kernel_count + 1 ))
done

if [ "${kernel_count}" -gt 1 ]; then
  echo "NOTE: There are several versions of kernel's initramfs."
  echo "      There is a possibility that you have multiple kernels installed in the image."
  echo "      It is most ideal to have only 1 kernel, to make initramfs regeneration faster."
fi

# Set dracut log levels using temporary configuration file.
# This avoids logging messages to the system journal, which can significantly
# impact performance in the default configuration.
temp_conf_file="$(mktemp '/etc/dracut.conf.d/zzz-loglevels-XXXXXXXXXX.conf')"
cat >"${temp_conf_file}" <<'EOF'
stdloglvl=4
sysloglvl=0
kmsgloglvl=0
fileloglvl=0
EOF

for kernel_path in /usr/lib/modules/*/; do
  kernel_path="${kernel_path%/}"
  initramfs_image="${kernel_path}/initramfs.img"
  qual_kernel=${kernel_path##*/}
  echo "Starting initramfs regeneration for kernel version: ${qual_kernel}"
  "${DRACUT}" \
    --kver "${qual_kernel}" \
    --force \
    --add 'ostree' \
    --no-hostonly \
    --reproducible \
    "${initramfs_image}"
  chmod 0600 "${initramfs_image}"
done

rm -- "${temp_conf_file}"

ostree container commit
