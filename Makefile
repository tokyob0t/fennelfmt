LUA ?= lua
LUA_VERSION ?= $(shell $(LUA) -e 'v=_VERSION:gsub("^Lua *","");print(v)')
FENNEL ?= ./fennel
FENNEL_OPTS ?= --require-as-include

DESTDIR ?=
PREFIX ?= /usr/local
BIN_DIR ?= $(PREFIX)/bin
MAN_DIR ?= $(PREFIX)/share/man/man1
LUA_LIB_DIR ?= $(PREFIX)/share/lua/$(LUA_VERSION)

SRC=cli.fnl fnlfmt.fnl
fnlfmt: $(SRC)
	echo "#!/usr/bin/env $(LUA)" > $@
	$(FENNEL) $(FENNEL_OPTS) --compile $< >> $@
	chmod +x $@

fnlfmt.lua: fnlfmt.fnl
	$(FENNEL) --compile $< > $@

selfhost:
	./fnlfmt --fix fnlfmt.fnl
	./fnlfmt --fix cli.fnl
	./fnlfmt --fix indentation.fnl
	./fnlfmt --fix macrodebug.fnl

# assumes you have a sibling checkout of Fennel
fennel.lua: ../fennel/fennel.lua ; cp $< $@
fennel: ../fennel/fennel ; cp $< $@

test: fnlfmt ; $(FENNEL) test.fnl
count: ; cloc fnlfmt.fnl
clean: ; rm -f fnlfmt fnlfmt.lua
lint: ; fennel-ls --lint $(SRC)

install: fnlfmt fnlfmt.lua
	mkdir -p $(DESTDIR)$(BIN_DIR) && cp $< $(DESTDIR)$(BIN_DIR)/
	mkdir -p $(DESTDIR)$(LUA_LIB_DIR) && cp fnlfmt.lua $(DESTDIR)$(LUA_LIB_DIR)
	mkdir -p $(DESTDIR)$(MAN_DIR)
	cp fnlfmt.1 $(DESTDIR)$(MAN_DIR)/fnlfmt.1

uninstall:
	rm -f $(DESTDIR)$(BIN_DIR)/fnlfmt
	rm -f $(DESTDIR)$(MAN_DIR)/fnlfmt.1

.PHONY: selfhost test count roundtrip clean lint install
