# asus-wmi from Linux 7.2.9 with the kbd_max_brightness parameter
# (kbd-max-brightness.patch). Replaces the in-tree asus-wmi.ko.
obj-m += asus-wmi.o

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
PWD  := $(CURDIR)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

.PHONY: all clean
