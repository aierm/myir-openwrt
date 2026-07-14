ARCH:=aarch64
SUBTARGET:=armv8
BOARDNAME:=RZ/G2X MPU soc evk boards 

define Target/Description
	Build firmware image for Renesas RZ/G2X MPU devices.
	This firmware features a rz_linux-cip kernel.
endef
