obj-m += asus_kbd_pwkb.o

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
PWD  := $(CURDIR)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

# Regenerate the embedded SSDT byte array from kpws.asl (needs iasl + python3)
aml: kpws.asl
	iasl -p kpws kpws.asl
	python3 mkaml.py kpws.aml kpws_method.aml
	python3 -c "d=open('kpws_method.aml','rb').read();\
	  L=['\t'+' '.join('0x%02x,'%b for b in d[i:i+12]) for i in range(0,len(d),12)];\
	  open('kpws_aml.h','w').write('/* generated -- do not edit */\nstatic u8 kpws_ssdt_aml[] = {\n'+'\n'.join(L)+'\n};\n')"

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	rm -f kpws.aml kpws_method.aml kpws_method.dsl

.PHONY: all aml clean
