LUA ?= lua
LUA_VERSION ?= $(shell $(LUA) -e 'v=_VERSION:gsub("^Lua *","");print(v)')
DESTDIR ?=
PREFIX ?= /usr/local
BIN_DIR ?= $(PREFIX)/bin
LUA_LIB_DIR ?= $(PREFIX)/share/lua/$(LUA_VERSION)

SRC=src/fennel.fnl $(wildcard src/fennel/*.fnl)

build: fennel fennel.lua

test: fennel.lua fennel
	$(LUA) test/init.lua $(TESTS)

testall: export FNL_TESTALL = 1
testall: export FNL_TEST_OUTPUT ?= text
testall: fennel fennel.lua
	@printf 'Testing lua 5.1:\n'  ; lua5.1 test/init.lua
	@printf "\nTesting lua 5.2:\n"; lua5.2 test/init.lua
	@printf "\nTesting lua 5.3:\n"; lua5.3 test/init.lua
	@printf "\nTesting lua 5.4:\n"; lua5.4 test/init.lua
	@printf "\nTesting luajit:\n" ; luajit test/init.lua

fuzz: fennel fennel.lua
	$(LUA) test/init.lua fuzz

count: ; cloc $(SRC) # older versions of cloc might need --force-lang=lisp

# install https://git.sr.ht/~technomancy/fnlfmt manually for this:
format: ; for f in $(SRC); do fnlfmt --fix $$f ; done

# Avoid chicken/egg situation using the old Lua launcher.
LAUNCHER=$(LUA) old/launcher.lua --add-fennel-path src/?.fnl --globals "_G,_ENV"

# Precompile standalone serializer
fennelview.lua: src/fennel/view.fnl fennel.lua ; $(LAUNCHER) --compile $< > $@

# All-in-one pure-lua script:
fennel: src/launcher.fnl $(SRC)
	echo "#!/usr/bin/env $(LUA)" > $@
	$(LAUNCHER) --no-metadata --require-as-include --compile $< >> $@
	chmod 755 $@

# Library file
fennel.lua: $(SRC)
	$(LAUNCHER) --no-metadata --require-as-include --compile $< > $@

# A lighter version of the compiler that excludes some features; experimental.
minifennel.lua: $(SRC) fennel
	./fennel --no-metadata --require-as-include --add-fennel-path src/?.fnl \
		--skip-include fennel.repl,fennel.view,fennel.friend \
		--compile $< > $@

LUA_DIR ?= $(PWD)/lua-5.3.5
STATIC_LUA_LIB ?= $(LUA_DIR)/src/liblua-linux-x86_64.a
LUA_INCLUDE_DIR ?= $(LUA_DIR)/src

PATH_ARGS=FENNEL_PATH=src/?.fnl FENNEL_MACRO_PATH=src/?.fnl

fennel-bin: src/launcher.fnl fennel $(STATIC_LUA_LIB)
	$(PATH_ARGS) ./fennel --no-compiler-sandbox --compile-binary \
		$< $@ $(STATIC_LUA_LIB) $(LUA_INCLUDE_DIR)

fennel-bin.exe: src/launcher.fnl fennel $(LUA_INCLUDE_DIR)/liblua-mingw.a
	$(PATH_ARGS) CC=i686-w64-mingw32-gcc ./fennel --compile-binary $< fennel-bin \
		$(LUA_INCLUDE_DIR)/liblua-mingw.a $(LUA_INCLUDE_DIR)

fennel-arm32: src/launcher.fnl fennel $(LUA_INCLUDE_DIR)/liblua-arm32.a
	$(PATH_ARGS) CC=arm-linux-gnueabihf-gcc ./fennel --compile-binary $< $@ \
		$(LUA_INCLUDE_DIR)/liblua-arm32.a $(LUA_INCLUDE_DIR)

$(LUA_DIR): ; curl https://www.lua.org/ftp/lua-5.3.5.tar.gz | tar xz

$(STATIC_LUA_LIB): $(LUA_DIR)
	make -C $(LUA_DIR) clean linux
	mv $(LUA_DIR)/src/liblua.a $@

# install gcc-mingw-w64-i686
$(LUA_DIR)/src/liblua-mingw.a: $(LUA_DIR)
	make -C $(LUA_DIR) clean mingw CC=i686-w64-mingw32-gcc
	mv $(LUA_DIR)/src/liblua.a $@

# install gcc-arm-linux-gnueabihf
$(LUA_DIR)/src/liblua-arm32.a: $(LUA_DIR)
	make -C $(LUA_DIR) clean linux CC=arm-linux-gnueabihf-gcc
	mv $(LUA_DIR)/src/liblua.a $@

ci: testall fuzz

clean:
	rm -f fennel.lua fennel fennel-bin fennel-bin.exe  fennel-arm32 \
		*_binary.c luacov.*
	make -C $(LUA_DIR) clean || true # this dir might not exist

coverage: fennel
	$(LUA) -lluacov test/init.lua
	@echo "generated luacov.report.out"

install: fennel fennel.lua fennelview.lua
	mkdir -p $(DESTDIR)$(BIN_DIR) && \
		cp fennel $(DESTDIR)$(BIN_DIR)/
	mkdir -p $(DESTDIR)$(LUA_LIB_DIR) && \
		for f in fennel.lua fennelview.lua; do cp $$f $(DESTDIR)$(LUA_LIB_DIR)/; done

# Release-related tasks:

fennel.tar.gz: README.md LICENSE fennel.1 fennel fennel.lua fennelview.lua \
		Makefile $(SRC)
	rm -rf fennel-$(VERSION)
	mkdir fennel-$(VERSION)
	cp -r $^ fennel-$(VERSION)
	tar czf $@ fennel-$(VERSION)

uploadrock: rockspecs/fennel-$(VERSION)-1.rockspec uploadtar
	luarocks --local build $<
	$(HOME)/.luarocks/bin/fennel --version | grep $(VERSION)
	luarocks --local remove fennel
	luarocks upload --api-key $(shell pass luarocks-api-key) $<
	luarocks --local install fennel
	$(HOME)/.luarocks/bin/fennel --version | grep $(VERSION)
	luarocks --local remove fennel

uploadtar: fennel fennel-bin fennel-bin.exe fennel-arm32 fennel.tar.gz
	mkdir -p downloads/
	mv fennel downloads/fennel-$(VERSION)
	mv fennel-bin downloads/fennel-$(VERSION)-x86_64
	mv fennel-bin.exe downloads/fennel-$(VERSION)-windows32.exe
	mv fennel-arm32 downloads/fennel-$(VERSION)-arm32
	mv fennel.tar.gz downloads/fennel-$(VERSION).tar.gz
	gpg -ab downloads/fennel-$(VERSION)
	gpg -ab downloads/fennel-$(VERSION)-x86_64
	gpg -ab downloads/fennel-$(VERSION)-windows32.exe
	gpg -ab downloads/fennel-$(VERSION)-arm32
	gpg -ab downloads/fennel-$(VERSION).tar.gz
	rsync -rtAv downloads/ fenneler@fennel-lang.org:fennel-lang.org/downloads/

release: uploadtar uploadrock

.PHONY: build test testall count format ci clean coverage install \
	uploadtar uploadrock release

# TODO for 1.0.0 release

# * remove fennelview.lua as a separate file
# * update fennel-bin to lua 5.4
# * enforce compiler sandbox
# * start disallowing & in identifiers
