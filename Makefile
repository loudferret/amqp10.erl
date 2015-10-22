
ERL = erl
ERLC = erlc
#PADIRS = $(CURDIR)/.eunit $(CURDIR)/../*/ebin/ $(CURDIR)/deps/*/ebin/ $(CURDIR)/ebin/
#INCDIRS = $(CURDIR)/include/ $(CURDIR)/deps/*/include/
PADIRS = .eunit/ ../*/ebin/ deps/*/ebin/ ebin/
INCDIRS = include/ $(wildcard deps/*/include/)
ERLCFLAGS= -pa $(PADIRS) -I $(INCDIRS)

SDIR = $(CURDIR)/src
TDIR = $(CURDIR)/test
ODIR = $(CURDIR)/ebin

#TARGETS = $($(SDIR)/%.erl=$(ODIR)/%.beam)
#$(warning TARGETS = .$(TARGETS).)

#$(warning INCDIRS = .$(INCDIRS).)
#$(warning PADIRS = .$(PADIRS).)
#$(warning ERLCFLAGS = .$(ERLCFLAGS).)

$(ODIR)/%.beam: $(SDIR)/%.erl
	$(ERLC) -W -o $(ODIR) \
			$(ERLCFLAGS) \
			$<

src:
	$(ERL) $(ERLCFLAGS) -make

test.spec:	test.spec.in
	cat $(CURDIR)/test.spec.in | sed -e "s,@PATH@,$(CURDIR)," > $(TDIR)/test.spec

test:	test.spec src
	ct_run -dir $(TDIR)/ \
			-logdir $(TDIR)/log/ \
			-config $(TDIR)/test.cfg \
			-env ERL_LIBS $(CURDIR)/build/dep-apps/ \
			-include $(CURDIR)/include/ \
			-spec $(TDIR)/test.spec \
			-pa $(PADIRS) \
			-ct_hooks cth_surefire \
			-erl_args -noshell


clean:
	rm -f $(CURDIR)/ebin/*.beam
