# SPDX-License-Identifier: GPL-2.0-only

MYIR_BOARD="myir,mys-rzg2l-wifi"
MYIR_IMAGE_BOARD="myir_mys_rzg2l_wifi"
MYIR_BOOT_MOUNT="/tmp/myir-sysupgrade-boot"
MYIR_BOOT_MOUNTED=0

if [ "$(board_name)" = "$MYIR_BOARD" ]; then
	RAMFS_COPY_BIN="df e2fsck head jsonfilter resize2fs"
	RAMFS_COPY_DATA="/etc/e2fsck.conf"
	REQUIRE_IMAGE_METADATA=1
fi

myir_payload() {
	fwtool -q -T -i /dev/null "$1" | gzip -dc
}

myir_member_magic() {
	myir_payload "$1" 2>/dev/null |
		tar -xOf - "$2" 2>/dev/null |
		dd bs=1 skip="$3" count="$4" 2>/dev/null |
		hexdump -v -e '1/1 "%02x"'
}

myir_member_size() {
	myir_payload "$1" 2>/dev/null |
		tar -tvf - "$2" 2>/dev/null |
		awk -v member="$2" '$NF == member { print $3; exit }'
}

myir_version_ge() {
	local have="$1" need="$2" have_part need_part

	[ -n "$have" ] && [ -n "$need" ] || return 1
	case "$have:$need" in
		*[!0-9.:]* | *..* | .* | *.:* | :.* | *.) return 1 ;;
	esac

	while [ -n "$have$need" ]; do
		case "$have" in
			*.*) have_part="${have%%.*}"; have="${have#*.}" ;;
			*) have_part="${have:-0}"; have= ;;
		esac
		case "$need" in
			*.*) need_part="${need%%.*}"; need="${need#*.}" ;;
			*) need_part="${need:-0}"; need= ;;
		esac

		[ "$have_part" -gt "$need_part" ] && return 0
		[ "$have_part" -lt "$need_part" ] && return 1
	done

	return 0
}

myir_check_image_tools() {
	local image="$1" installed metadata required

	metadata="$(fwtool -q -i /dev/stdout "$image" 2>/dev/null)" || return 1
	required="$(printf '%s' "$metadata" |
		jsonfilter -e '@.myir_e2fsprogs_min')" || return 1
	[ -n "$required" ] || return 1

	installed="$(e2fsck -V 2>&1 | awk 'NR == 1 { print $2; exit }')"
	myir_version_ge "$installed" "$required" || {
		echo "e2fsck $installed is older than the required version $required" >&2
		return 1
	}

	fwtool -q -T -i /dev/null "$image" 2>/dev/null |
		gzip -t 2>/dev/null
}

myir_prepare_image() {
	local image="$1"
	local contents control board_dir member

	myir_check_image_tools "$image" || return 1
	contents="$(myir_payload "$image" 2>/dev/null | tar -tf - 2>/dev/null)" ||
		return 1
	board_dir="$(printf '%s\n' "$contents" |
		sed -n 's#^\(sysupgrade-[^/]*/\)$#\1#p' | head -n 1)"
	board_dir="${board_dir%/}"
	[ "$board_dir" = "sysupgrade-${MYIR_IMAGE_BOARD}" ] || return 1

	for member in CONTROL kernel dtb root; do
		[ "$(printf '%s\n' "$contents" |
			grep -xc "${board_dir}/${member}")" = "1" ] || return 1
	done

	control="$(myir_payload "$image" 2>/dev/null |
		tar -xOf - "${board_dir}/CONTROL" 2>/dev/null)" || return 1
	[ "$control" = "BOARD=${MYIR_IMAGE_BOARD}" ] || return 1

	[ "$(myir_member_magic "$image" "${board_dir}/kernel" 56 4)" = "41524d64" ] ||
		return 1
	[ "$(myir_member_magic "$image" "${board_dir}/dtb" 0 4)" = "d00dfeed" ] ||
		return 1
	[ "$(myir_member_magic "$image" "${board_dir}/root" 1080 2)" = "53ef" ] ||
		return 1

	MYIR_KERNEL_SIZE="$(myir_member_size "$image" "${board_dir}/kernel")"
	MYIR_DTB_SIZE="$(myir_member_size "$image" "${board_dir}/dtb")"
	MYIR_ROOT_SIZE="$(myir_member_size "$image" "${board_dir}/root")"
	case "$MYIR_KERNEL_SIZE:$MYIR_DTB_SIZE:$MYIR_ROOT_SIZE" in
		*[!0-9:]* | *::* | :* | *:) return 1 ;;
	esac

	MYIR_BOARD_DIR="$board_dir"
	return 0
}

myir_find_upgrade_devices() {
	local diskdev bootdev rootdev removable rootarg

	export_bootdevice && export_partdevice diskdev 0 || return 1
	export_partdevice bootdev 1 || return 1
	export_partdevice rootdev 2 || return 1

	case "$diskdev" in
		mmcblk[0-9]*) ;;
		*) return 1 ;;
	esac

	removable="$(cat "/sys/class/block/${diskdev}/removable" 2>/dev/null)"
	[ "$removable" = "0" ] || return 1

	MYIR_DISKDEV="/dev/${diskdev}"
	MYIR_BOOTDEV="/dev/${bootdev}"
	MYIR_ROOTDEV="/dev/${rootdev}"

	rootarg="$(cmdline_get_var root)"
	[ "$rootarg" = "$MYIR_ROOTDEV" ] || return 1
	part_magic_fat "$MYIR_BOOTDEV" || return 1
	[ "$(dd if="$MYIR_ROOTDEV" bs=1 skip=1080 count=2 2>/dev/null |
		hexdump -v -e '1/1 "%02x"')" = "53ef" ] || return 1

	return 0
}

myir_check_capacity() {
	local sectors root_capacity

	sectors="$(cat "/sys/class/block/${MYIR_ROOTDEV##*/}/size" 2>/dev/null)"
	case "$sectors" in
		'' | *[!0-9]*) return 1 ;;
	esac
	root_capacity=$((sectors * 512))
	[ "$MYIR_ROOT_SIZE" -le "$root_capacity" ]
}

myir_unmount_boot() {
	if [ "$MYIR_BOOT_MOUNTED" = "1" ]; then
		umount "$MYIR_BOOT_MOUNT" 2>/dev/null || true
		MYIR_BOOT_MOUNTED=0
	fi
}

myir_upgrade_fail() {
	set +o pipefail 2>/dev/null || true
	echo "MYIR sysupgrade failed: $*" >&2
	sync
	myir_unmount_boot
	exit 1
}

myir_mount_boot() {
	mkdir -p "$MYIR_BOOT_MOUNT" || return 1
	mount -t vfat -o rw,noatime "$MYIR_BOOTDEV" "$MYIR_BOOT_MOUNT" ||
		return 1
	MYIR_BOOT_MOUNTED=1
}

myir_check_boot_space() {
	local available_kb required_size backup_size=0

	myir_mount_boot || return 1
	rm -f "$MYIR_BOOT_MOUNT/Image.new" \
		"$MYIR_BOOT_MOUNT/mys-rzg2l-wifi.dtb.new" \
		"$MYIR_BOOT_MOUNT/$BACKUP_FILE" \
		"$MYIR_BOOT_MOUNT/$BACKUP_FILE.new"

	[ -n "$UPGRADE_BACKUP" ] && [ -f "$UPGRADE_BACKUP" ] &&
		backup_size="$(wc -c < "$UPGRADE_BACKUP")"
	[ "$MYIR_KERNEL_SIZE" -ge "$MYIR_DTB_SIZE" ] &&
		required_size="$MYIR_KERNEL_SIZE" || required_size="$MYIR_DTB_SIZE"
	required_size=$((required_size + backup_size + 1048576))
	available_kb="$(df -Pk "$MYIR_BOOT_MOUNT" | awk 'END { print $4 }')"
	myir_unmount_boot

	case "$available_kb" in
		'' | *[!0-9]*) return 1 ;;
	esac
	[ $((available_kb * 1024)) -ge "$required_size" ]
}

myir_check_fsck_result() {
	case "$1" in
		0 | 1 | 2 | 3) return 0 ;;
		*) return 1 ;;
	esac
}

myir_check_image() {
	local image="$1" tool

	[ "$(board_name)" = "$MYIR_BOARD" ] || {
		echo "Sysupgrade is not supported on $(board_name)"
		return 74
	}

	for tool in fwtool gzip tar e2fsck jsonfilter resize2fs; do
		command -v "$tool" >/dev/null 2>&1 || {
			echo "Required upgrade tool is missing: $tool"
			return 74
		}
	done

	myir_prepare_image "$image" || {
		echo "The image is not a MYIR MYS-RZG2L sysupgrade archive"
		return 74
	}
	myir_find_upgrade_devices || {
		echo "The running system is not using the expected eMMC FAT/ext4 layout"
		return 74
	}
	myir_check_capacity || {
		echo "The root filesystem image does not fit in the eMMC root partition"
		return 74
	}

	return 0
}

myir_do_upgrade() {
	local image="$1" rc written_size

	[ "$(board_name)" = "$MYIR_BOARD" ] ||
		myir_upgrade_fail "unsupported board $(board_name)"
	myir_prepare_image "$image" || myir_upgrade_fail "invalid upgrade archive"
	myir_find_upgrade_devices || myir_upgrade_fail "unexpected eMMC layout"
	myir_check_capacity || myir_upgrade_fail "root filesystem image is too large"
	myir_check_boot_space || myir_upgrade_fail "not enough free space in the boot partition"
	umount "$MYIR_ROOTDEV" 2>/dev/null || true
	awk -v device="$MYIR_ROOTDEV" '$1 == device { mounted = 1 } END { exit mounted ? 0 : 1 }' \
		/proc/mounts && myir_upgrade_fail "root filesystem is still mounted"

	echo "Writing root filesystem to $MYIR_ROOTDEV..."
	set -o pipefail
	myir_payload "$image" |
		tar -xOf - "${MYIR_BOARD_DIR}/root" |
		dd of="$MYIR_ROOTDEV" bs=1M conv=fsync ||
		myir_upgrade_fail "writing root filesystem"
	set +o pipefail
	sync

	[ "$(dd if="$MYIR_ROOTDEV" bs=1 skip=1080 count=2 2>/dev/null |
		hexdump -v -e '1/1 "%02x"')" = "53ef" ] ||
		myir_upgrade_fail "root filesystem verification"

	e2fsck -f -y "$MYIR_ROOTDEV"
	rc=$?
	myir_check_fsck_result "$rc" || myir_upgrade_fail "checking root filesystem ($rc)"
	resize2fs "$MYIR_ROOTDEV" || myir_upgrade_fail "resizing root filesystem"
	e2fsck -f -p "$MYIR_ROOTDEV"
	rc=$?
	myir_check_fsck_result "$rc" || myir_upgrade_fail "verifying root filesystem ($rc)"

	myir_mount_boot || myir_upgrade_fail "mounting boot partition"
	echo "Updating device tree..."
	set -o pipefail
	myir_payload "$image" |
		tar -xOf - "${MYIR_BOARD_DIR}/dtb" \
		> "$MYIR_BOOT_MOUNT/mys-rzg2l-wifi.dtb.new" ||
		myir_upgrade_fail "extracting device tree"
	set +o pipefail
	written_size="$(wc -c < "$MYIR_BOOT_MOUNT/mys-rzg2l-wifi.dtb.new")"
	[ "$written_size" = "$MYIR_DTB_SIZE" ] || myir_upgrade_fail "device tree size mismatch"
	sync
	mv -f "$MYIR_BOOT_MOUNT/mys-rzg2l-wifi.dtb.new" \
		"$MYIR_BOOT_MOUNT/mys-rzg2l-wifi.dtb" ||
		myir_upgrade_fail "installing device tree"

	echo "Updating kernel..."
	set -o pipefail
	myir_payload "$image" |
		tar -xOf - "${MYIR_BOARD_DIR}/kernel" \
		> "$MYIR_BOOT_MOUNT/Image.new" ||
		myir_upgrade_fail "extracting kernel"
	set +o pipefail
	written_size="$(wc -c < "$MYIR_BOOT_MOUNT/Image.new")"
	[ "$written_size" = "$MYIR_KERNEL_SIZE" ] || myir_upgrade_fail "kernel size mismatch"
	sync
	mv -f "$MYIR_BOOT_MOUNT/Image.new" "$MYIR_BOOT_MOUNT/Image" ||
		myir_upgrade_fail "installing kernel"
	sync
	myir_unmount_boot
}

myir_copy_config() {
	[ "$(board_name)" = "$MYIR_BOARD" ] || return 0
	myir_find_upgrade_devices || myir_upgrade_fail "unable to locate boot partition for config backup"
	myir_mount_boot || myir_upgrade_fail "mounting boot partition for config backup"
	cp -f "$UPGRADE_BACKUP" "$MYIR_BOOT_MOUNT/$BACKUP_FILE.new" ||
		myir_upgrade_fail "writing config backup"
	sync
	mv -f "$MYIR_BOOT_MOUNT/$BACKUP_FILE.new" \
		"$MYIR_BOOT_MOUNT/$BACKUP_FILE" ||
		myir_upgrade_fail "installing config backup"
	sync
	myir_unmount_boot
}

renesas_sdcard_check_image() {
	local diskdev partdev diff

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}

	get_partitions "/dev/$diskdev" bootdisk
	get_image_dd "$1" of=/tmp/image.bs count=1 bs=512b
	get_partitions /tmp/image.bs image
	diff="$(grep -F -x -v -f /tmp/partmap.bootdisk /tmp/partmap.image)"
	rm -f /tmp/image.bs /tmp/partmap.bootdisk /tmp/partmap.image

	if [ -n "$diff" ]; then
		echo "Partition layout has changed. Full image will be written."
		ask_bool 0 "Abort" && exit 1
		return 0
	fi
}

renesas_sdcard_copy_config() {
	local partdev

	if export_partdevice partdev 1; then
		mkdir -p /mnt
		mount -o rw,noatime "/dev/$partdev" /mnt
		cp -af "$UPGRADE_BACKUP" "/mnt/$BACKUP_FILE"
		sync
		umount /mnt
	fi
}

renesas_sdcard_do_upgrade() {
	local diskdev partdev diff

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}

	sync
	if [ "$UPGRADE_OPT_SAVE_PARTITIONS" = "1" ]; then
		get_partitions "/dev/$diskdev" bootdisk
		get_image_dd "$1" of=/tmp/image.bs count=1 bs=512b
		get_partitions /tmp/image.bs image
		diff="$(grep -F -x -v -f /tmp/partmap.bootdisk /tmp/partmap.image)"
	else
		diff=1
	fi

	if [ -n "$diff" ]; then
		get_image_dd "$1" of="/dev/$diskdev" bs=4096 conv=fsync
		partx -d - "/dev/$diskdev"
		partx -a - "/dev/$diskdev"
		return 0
	fi

	get_image_dd "$1" of="/dev/$diskdev" bs=1024 skip=8 seek=8 count=1016 conv=fsync
	while read -r part start size; do
		if export_partdevice partdev "$part"; then
			echo "Writing image to /dev/$partdev..."
			get_image_dd "$1" of="/dev/$partdev" ibs=512 obs=1M \
				skip="$start" count="$size" conv=fsync
		else
			echo "Unable to find partition $part device, skipped."
		fi
	done < /tmp/partmap.image

	echo "Writing new UUID to /dev/$diskdev..."
	get_image_dd "$1" of="/dev/$diskdev" bs=1 skip=440 count=4 seek=440 conv=fsync
}

platform_check_image() {
	case "$(board_name)" in
	"$MYIR_BOARD") myir_check_image "$@" ;;
	*) renesas_sdcard_check_image "$@" ;;
	esac
}

platform_do_upgrade() {
	case "$(board_name)" in
	"$MYIR_BOARD") myir_do_upgrade "$@" ;;
	*) renesas_sdcard_do_upgrade "$@" ;;
	esac
}

platform_copy_config() {
	case "$(board_name)" in
	"$MYIR_BOARD") myir_copy_config "$@" ;;
	*) renesas_sdcard_copy_config "$@" ;;
	esac
}
