# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2020 Tobias Maedel
define Device/smarc_rzg2l
  DEVICE_VENDOR := smarc
  DEVICE_MODEL := rzg2l
  SOC := r9a07g044l2
  IMAGE/sdcard.img.gz := boot-common | boot-image | gzip | append-metadata
  DEVICE_DTS = renesas/$$(SOC)-$$(DEVICE_VENDOR)
endef
TARGET_DEVICES += smarc_rzg2l

define Device/smarc_rzg2lc
  DEVICE_VENDOR := smarc
  DEVICE_MODEL := rzg2lc
  SOC := r9a07g044c2
  IMAGE/sdcard.img.gz := boot-common | boot-image | gzip | append-metadata
  DEVICE_DTS = renesas/$$(SOC)-$$(DEVICE_VENDOR)
endef
TARGET_DEVICES += smarc_rzg2lc

define Device/smarc_rzg2ul
  DEVICE_VENDOR := smarc
  DEVICE_MODEL := rzg2ul
  SOC := r9a07g043u11
  IMAGE/sdcard.img.gz := boot-common | boot-image | gzip | append-metadata
  DEVICE_DTS = renesas/$$(SOC)-$$(DEVICE_VENDOR)
endef
TARGET_DEVICES += smarc_rzg2ul

define Device/hihope_rzg2h
  DEVICE_VENDOR := hihope
  DEVICE_MODEL := rzg2h
  SOC := r8a774e1
  IMAGE/sdcard.img.gz := boot-common | boot-image | gzip | append-metadata
endef
TARGET_DEVICES += hihope_rzg2h

define Device/hihope_rzg2m
  DEVICE_VENDOR := hihope
  DEVICE_MODEL := rzg2m
  SOC := r8a774a1
  IMAGE/sdcard.img.gz := boot-common | boot-image | gzip | append-metadata
endef
TARGET_DEVICES += hihope_rzg2m

define Device/hihope_rzg2n
  DEVICE_VENDOR := hihope
  DEVICE_MODEL := rzg2n
  SOC := r8a774b1
  IMAGE/sdcard.img.gz := boot-common | boot-image | gzip | append-metadata
endef
TARGET_DEVICES += hihope_rzg2n

define Device/myir_mys_rzg2l_wifi
  DEVICE_VENDOR := MYiR
  DEVICE_MODEL := MYS-RZG2L
  DEVICE_VARIANT := WiFi
  DEVICE_DTS := renesas/mys-rzg2l-wifi
  SUPPORTED_DEVICES := myir,mys-rzg2l-wifi
  DEVICE_COMPAT_VERSION := 1.1
  IMAGE_METADATA := "myir_e2fsprogs_min": "1.47.4"
  IMAGES += sysupgrade.tar.gz
  IMAGE/sdcard.img.gz := boot-common | myir-emmc-image | gzip | append-metadata
  IMAGE/sysupgrade.tar.gz := sysupgrade-tar \
	dtb=$$(KDIR)/image-$$(notdir $$(firstword $$(DEVICE_DTS))).dtb | \
	gzip | append-metadata
  ARTIFACTS := device-tree.dtb
  ARTIFACT/device-tree.dtb := export-device-dtb
  DEVICE_PACKAGES := \
	kmod-renesas-net-avb kmod-phy-micrel \
	kmod-rtw88-8822cs kmod-rt2800-usb \
	hostapd-utils iw wifi-scripts wireless-regdb wpa-cli wpad-basic-mbedtls \
	kmod-usb2 kmod-usb-ohci kmod-usb-storage
  DEVICE_PACKAGES += e2fsprogs resize2fs
endef
TARGET_DEVICES += myir_mys_rzg2l_wifi
