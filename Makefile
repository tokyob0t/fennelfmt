LUA ?= lua
LUA_VERSION ?= $(shell $(LUA) -e 'v=_VERSION:gsub("^Lua *","");print(v)')
FENNEL ?= ./fennel
FENNEL_OPTS ?= --require-as-include
# Prefer the vendored Fennel over any system-wide install.
FENNEL_ENV ?= LUA_PATH="$(CURDIR)/?.lua;;"

DESTDIR ?=
PREFIX ?= /usr/local
BIN_DIR ?= $(PREFIX)/bin
MAN_DIR ?= $(PREFIX)/share/man/man1
LUA_LIB_DIR ?= $(PREFIX)/share/lua/$(LUA_VERSION)

FENNEL_LS ?= $(shell command -v fennel-ls 2>/dev/null \
	|| echo $(HOME)/.local/share/nvim/mason/bin/fennel-ls)

SRC=cli.fnl fnlfmt.fnl indentation.fnl
SELF_HOSTED=fnlfmt.fnl cli.fnl indentation.fnl macrodebug.fnl test.fnl

fnlfmt: $(SRC)
	echo "#!/usr/bin/env $(LUA)" > $@
	$(FENNEL_ENV) $(FENNEL) $(FENNEL_OPTS) --compile $< >> $@
	chmod +x $@

fnlfmt.lua: fnlfmt.fnl
	$(FENNEL_ENV) $(FENNEL) --compile $< > $@

indentation.lua: indentation.fnl
	$(FENNEL_ENV) $(FENNEL) --compile $< > $@

selfhost: fnlfmt
	./fnlfmt --fix $(SELF_HOSTED)

# assumes you have a sibling checkout of Fennel
fennel.lua: ../fennel/fennel.lua ; cp $< $@
fennel: ../fennel/fennel ; cp $< $@

test: fnlfmt ; $(FENNEL_ENV) $(FENNEL) test.fnl
count: ; cloc fnlfmt.fnl
clean: ; rm -f fnlfmt fnlfmt.lua indentation.lua
lint: ; $(FENNEL_LS) --lint $(SRC)

check: test
	./fnlfmt --check $(SELF_HOSTED)
	$(FENNEL_LS) --lint $(SRC)

install: fnlfmt fnlfmt.lua indentation.lua
	mkdir -p $(DESTDIR)$(BIN_DIR) && cp fnlfmt $(DESTDIR)$(BIN_DIR)/
	mkdir -p $(DESTDIR)$(LUA_LIB_DIR) && cp fnlfmt.lua indentation.lua $(DESTDIR)$(LUA_LIB_DIR)
	mkdir -p $(DESTDIR)$(MAN_DIR)
	cp fnlfmt.1 $(DESTDIR)$(MAN_DIR)/fnlfmt.1

uninstall:
	rm -f $(DESTDIR)$(BIN_DIR)/fnlfmt
	rm -f $(DESTDIR)$(LUA_LIB_DIR)/fnlfmt.lua
	rm -f $(DESTDIR)$(LUA_LIB_DIR)/indentation.lua
	rm -f $(DESTDIR)$(MAN_DIR)/fnlfmt.1

.PHONY: selfhost test check count clean lint install uninstall
