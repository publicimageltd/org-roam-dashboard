.POSIX:
EMACS = emacs
TARGET := $(shell emacs -batch --eval='(princ user-emacs-directory)')
PACKAGE-NAME := $(shell basename `pwd`)

SRCS = $(wildcard *.el)
OBJS = $(SRCS:.el=.elc)

.PHONY: compile test clean install


all: compile

compile: ${SRCS} ${OBJS}

install:
	cd $(TARGET)lisp/packages
	printf "%s\n" $(PACKAGE-NAME)

clean:
	rm -f ${OBJS}

test:
	$(EMACS) -batch -f package-initialize -L . -f buttercup-run-discover

.SUFFIXES: .el .elc
.el.elc:
	$(EMACS) -batch -Q -L . -f batch-byte-compile $<
