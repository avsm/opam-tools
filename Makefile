.DEFAULT_GOAL := all

.PHONY: all
all:
	opam exec -- dune build --root . @install

.PHONY: dev
dev: ## Install development dependencies
	opam switch create --no-install . ocaml-base-compiler.4.11.1
	opam install -y dune-release merlin ocamlformat utop ocaml-lsp-server
	opam install --locked --deps-only --with-test --with-doc -y .

.PHONY: build
build: ## Build the project, including non installable libraries and executables
	opam exec -- dune build --root .

.PHONY: lock
lock: ## Generate a lock file
	opam lock -y .

.PHONY: install
install: all ## Install the packages on the system
	opam install -y .

.PHONY: test
test: ## Run the unit tests
	opam exec -- dune build --root . @test/runtest

.PHONY: clean
clean: ## Clean build artifacts and other generated files
	opam exec -- dune clean --root .

.PHONY: fmt
fmt: ## Format the codebase with ocamlformat
	opam exec -- dune build --root . @fmt --auto-promote

.PHONY: watch
watch: ## Watch for the filesystem and rebuild on every change
	opam exec -- dune build ---root . -watch

.PHONY: utop
utop: ## Run a REPL and link with the project's libraries
	opam exec -- dune utop --root . lib -- -implicit-bindings
