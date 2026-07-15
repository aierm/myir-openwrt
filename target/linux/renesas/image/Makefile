# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

define Build/Compile
	$(CP) $(LINUX_DIR)/COPYING $(KDIR)/COPYING.linux
endef

### Image scripts ###
define Build/boot-common
	# This creates a new folder copies the dtb 
	# and the kernel image (as Image)
	rm -fR $@.boot
	mkdir -p $@.boot

	$(CP) $(KDIR)/image-$(notdir $(DEVICE_DTS)).dtb $@.boot/$(notdir $(DEVICE_DTS)).dtb
	$(CP) $(KDIR)/$(KERNEL_NAME) $@.boot
endef

define Build/export-device-dtb
	$(CP) $(KDIR)/image-$(notdir $(DEVICE_DTS)).dtb $@
endef

define Build/boot-image
	# Creates the final SD/eMMC images, 
	# combining boot partition, root partition.

	PADDING=1 $(SCRIPT_DIR)/gen_image_generic.sh \
		$@ \
		$(CONFIG_TARGET_KERNEL_PARTSIZE) $@.boot \
		$(CONFIG_TARGET_ROOTFS_PARTSIZE) $(IMAGE_ROOTFS) \
		32768

endef

define Build/myir-emmc-image
	# Match the MYIR U-Boot layout: a FAT boot partition at 10 MiB,
	# followed by the ext4 root filesystem at the next aligned boundary.
	FAT_TYPE=32 KERNELPARTTYPE=0c PARTOFFSET=10m PADDING=1 \
		$(SCRIPT_DIR)/gen_image_generic.sh \
		$@ \
		$(CONFIG_TARGET_KERNEL_PARTSIZE) $@.boot \
		$(CONFIG_TARGET_ROOTFS_PARTSIZE) $(IMAGE_ROOTFS) \
		1024
endef

### Devices ###
define Device/Default
  PROFILES := Default
  IMAGES := sdcard.img.gz
  ARTIFACTS :=
  KERNEL_NAME := Image
  KERNEL := kernel-bin
  DEVICE_DTS = renesas/$$(SOC)-$$(DEVICE_VENDOR)-$(lastword $(subst _, ,$(1)))
endef

include $(SUBTARGET).mk

$(eval $(call BuildImage))
