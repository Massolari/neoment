TESTS_INIT=tests/init.lua
TESTS_DIR=tests/

test:
	@nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \
		-c "PlenaryBustedDirectory ${TESTS_DIR} { minimal_init = '${TESTS_INIT}' }"

test-watch:
	make test &2> /dev/null \
	&& fswatch . | xargs -I {} make test

.PHONY: test test-watch

