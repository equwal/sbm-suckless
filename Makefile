include config.mk

all:
	@echo Nothing to build: use make install, make uninstall, make check, or make dist.

check:
	@sh test.sh

dist:
	@echo creating dist tarball
	@mkdir -p sbm-${VERSION}-temp
	@cp -R LICENSE Makefile config.mk bm bm-sync test.sh sbm-${VERSION}-temp
	@mv sbm-${VERSION}-temp sbm-${VERSION}
	@tar -cf sbm-${VERSION}.tar sbm-${VERSION}
	@gzip sbm-${VERSION}.tar
	@rm -rf sbm-${VERSION}

install:
	@echo installing scripts to ${DESTDIR}${PREFIX}/bin
	@mkdir -p ${DESTDIR}${PREFIX}/bin
	@cp bm bm-sync ${DESTDIR}${PREFIX}/bin
	@chmod 755 ${DESTDIR}${PREFIX}/bin/bm ${DESTDIR}${PREFIX}/bin/bm-sync

uninstall:
	@echo removing scripts
	rm -f ${DESTDIR}${PREFIX}/bin/bm ${DESTDIR}${PREFIX}/bin/bm-sync
