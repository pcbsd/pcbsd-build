#############################################################################
# Makefile for building: FreeNAS
#############################################################################

####### Install

all:
	@cd ${.CURDIR}/scripts/ && sh build-iso.sh all
image:
	@cd ${.CURDIR}/scripts/ && sh build-iso.sh iso
iso:
	@cd ${.CURDIR}/scripts/ && sh build-iso.sh iso
tests:
	@cd ${.CURDIR}/scripts/ && sh build-iso.sh tests
