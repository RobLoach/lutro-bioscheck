NAME = bioscheck

start:
	retroarch -L lutro main.lua

package: clean
	zip -r $(NAME).lutro main.lua conf.lua src/ vendor/ resources/ -x "resources/screenshot.png"

clean:
	rm -f $(NAME).lutro

.PHONY: start package clean