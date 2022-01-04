# "make" Compiles everything and runs the regression tests
LIB = ./stdlib
TEST = ./tests
SRC = ./src
EXE = /usr/local/myFileVer1


.PHONY : test
test : compiler
	cd $(TEST) && ./testall.sh

# "make compiler" builds the executable as well as the "stdlib" library 

.PHONY : compiler
compiler : clean
	cd $(SRC) && dune build
	ln -s ./_build/default/src/ezap.exe ezap.exe
	cd $(LIB) && make


#
# The _tags file controls the operation of ocamlbuild, e.g., by including
# packages, enabling warnings
#
# See https://github.com/ocaml/ocamlbuild/blob/master/manual/manual.adoc


# "make clean" removes all generated files

.PHONY : clean
clean :
	ocamlbuild -clean
	rm -rf testall.log ocamlllvm *.diff
	rm -f ezap.exe

# Testing the "printbig" example

printbig : printbig.c
	cc -o printbig -DBUILD_TEST printbig.c

# Building the tarball

TESTS = \
  add1 arith1 arith2 arith3 fib float1 float2 float3 for1 for2 func1 \
  func2 func3 func4 func5 func6 func7 func8 func9 gcd2 gcd global1 \
  global2 global3 hello if1 if2 if3 if4 if5 if6 local1 local2 ops1 \
  ops2 printbig var1 var2 while1 while2 strassign strcat strprint \
  return1 

FAILS = \
  assign1 assign2 assign3 dead1 dead2 expr1 expr2 expr3 float1 float2 \
  for1 for2 for3 for4 for5 func1 func2 func3 func4 func5 func6 func7 \
  func8 func9 global1 global2 if1 if2 if3 nomain printbig printb print \
  return1 return2 while1 while2 return3

TESTFILES = $(TESTS:%=test-%.mc) $(TESTS:%=test-%.out) \
	    $(FAILS:%=fail-%.mc) $(FAILS:%=fail-%.err)

TARFILES = ast.ml sast.ml codegen.ml Makefile _tags microc.ml microcparse.mly \
	README scanner.mll semant.ml testall.sh \
	printbig.c arcade-font.pbm font2c \
	Dockerfile \
	$(TESTFILES:%=tests/%) 

microc.tar.gz : $(TARFILES)
	cd .. && tar czf microc/microc.tar.gz \
		$(TARFILES:%=microc/%)
