# make            build wv2shim.exe (needs mingw-w64-gcc)
# make install    build, then install for the current user (./install.sh)
# make check      run shellcheck and desktop-file-validate
# make dist       build the release tarball nohesi-linux-VERSION.tar.gz

CROSS   ?= x86_64-w64-mingw32-
PREFIX  ?= $(HOME)/.local
# From the newest vX.Y tag: 1.0, or 1.0-3-gabc1234 three commits later. The
# snapshot-* tags of per-commit builds are not counted.
VERSION ?= $(patsubst v%,%,$(shell git describe --tags --match 'v[0-9]*' --always --dirty 2>/dev/null || echo dev))
# Fixed timestamps make the tarball reproducible from the same commit.
SOURCE_DATE_EPOCH ?= $(shell git log -1 --format=%ct 2>/dev/null || date +%s)

DIST     = nohesi-linux-$(VERSION)
SCRIPTS  = nohesi-launcher ac-content-manager common.sh install.sh
EXECUTABLES = nohesi-launcher ac-content-manager install.sh wv2shim.exe
DISTFILES = $(SCRIPTS) wv2shim.exe wv2shim.c wv2shim.rc Makefile \
	nohesi-launcher.desktop ac-content-manager.desktop \
	README.md wintrust-implement-cryptsipverifyindirectdata.patch \
	$(wildcard LICENSE content-manager.png)

all: wv2shim.exe

wv2shim.res: wv2shim.rc
	$(CROSS)windres $< -O coff -o $@

wv2shim.exe: wv2shim.c wv2shim.res
	$(CROSS)gcc -O2 -Wall -municode -mwindows -static -s -Wl,--no-insert-timestamp \
		-o $@ wv2shim.c wv2shim.res

install: wv2shim.exe
	PREFIX="$(PREFIX)" ./install.sh

uninstall:
	PREFIX="$(PREFIX)" ./install.sh --uninstall

check:
	shellcheck -x -S warning $(SCRIPTS)
	desktop-file-validate nohesi-launcher.desktop ac-content-manager.desktop

dist: $(DIST).tar.gz

$(DIST).tar.gz: $(DISTFILES)
	rm -rf $(DIST) && mkdir $(DIST)
	cp $(DISTFILES) $(DIST)/
	chmod 644 $(DIST)/* && chmod 755 $(DIST) $(addprefix $(DIST)/,$(EXECUTABLES))
	tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@$(SOURCE_DATE_EPOCH) \
		-cf - $(DIST) | gzip -9n > $@
	rm -rf $(DIST)
	sha256sum $@ > $@.sha256

version:
	@echo $(VERSION)

clean:
	rm -f wv2shim.exe wv2shim.res nohesi-linux-*.tar.gz nohesi-linux-*.tar.gz.sha256

.PHONY: all install uninstall check dist version clean
