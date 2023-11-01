all: build test
all-release: build-release test-release

genDemo:
    fish_prompt="> " fish_history="eza_history" vhs < docs/tapes/demo.tape
    nsxiv -a docs/images/demo.gif

#----------#
# building #
#----------#

# compile the exa binary
@build:
    cargo build

# compile the exa binary (in release mode)
@build-release:
    cargo build --release --verbose

# produce an HTML chart of compilation timings
@build-time:
    cargo +nightly clean
    cargo +nightly build -Z timings

# check that the exa binary can compile
@check:
    cargo check


#---------------#
# running tests #
#---------------#

# run unit tests
@test:
    cargo test --workspace -- --quiet

# run unit tests (in release mode)
@test-release:
    cargo test --workspace --release --verbose

#-----------------------#
# code quality and misc #
#-----------------------#

# lint the code
@clippy:
    touch src/main.rs
    cargo clippy

# update dependency versions, and checks for outdated ones
@update-deps:
    cargo update
    command -v cargo-outdated >/dev/null || (echo "cargo-outdated not installed" && exit 1)
    cargo outdated

# list unused dependencies
@unused-deps:
    command -v cargo-udeps >/dev/null || (echo "cargo-udeps not installed" && exit 1)
    cargo +nightly udeps

# check that every combination of feature flags is successful
@check-features:
    command -v cargo-hack >/dev/null || (echo "cargo-hack not installed" && exit 1)
    cargo hack check --feature-powerset

# print versions of the necessary build tools
@versions:
    rustc --version
    cargo --version


#---------------#
# documentation #
#---------------#

# build the man pages
@man:
    mkdir -p "${CARGO_TARGET_DIR:-target}/man"
    version=$(awk 'BEGIN { FS = "\"" } ; /^version/ { print $2 ; exit }' Cargo.toml); \
    for page in eza.1 eza_colors.5 eza_colors-explanation.5; do \
        sed "s/\$version/v${version}/g" "man/${page}.md" | pandoc --standalone -f markdown -t man > "${CARGO_TARGET_DIR:-target}/man/${page}"; \
    done;

# build and preview the main man page (eza.1)
@man-1-preview: man
    man "${CARGO_TARGET_DIR:-target}/man/eza.1"

# build and preview the colour configuration man page (eza_colors.5)
@man-5-preview: man
    man "${CARGO_TARGET_DIR:-target}/man/eza_colors.5"

# build and preview the colour configuration man page (eza_colors.5)
@man-5-explanations-preview: man
    man "${CARGO_TARGET_DIR:-target}/man/eza_colors-explanation.5"

#---------------#
#    release    #
#---------------#

new_version := "$(convco version --bump)"

# If you're not cafkafk and she isn't dead, don't run this!
#
# usage: release major, release minor, release patch
release:
    cargo bump "{{new_version}}"
    git cliff -t "{{new_version}}" > CHANGELOG.md
    cargo check
    nix build -L ./#clippy
    git checkout -b "cafk-release-v{{new_version}}"
    git commit -asm "chore: release eza v{{new_version}}"
    git push
    @echo "waiting 10 seconds for github to catch up..."
    sleep 10
    gh pr create --draft --title "chore: release v{{new_version}}" --body "This PR was auto-generated by our lovely just file" --reviewer cafkafk
    @echo "Now go review that and come back and run gh-release"

@gh-release:
    git tag -d "v{{new_version}}" || echo "tag not found, creating";
    git tag -a "v{{new_version}}" -m "auto generated by the justfile for eza v$(convco version)"
    just cross
    mkdir -p ./target/"release-notes-$(convco version)"
    git cliff -t "v$(convco version)" --current > ./target/"release-notes-$(convco version)/RELEASE.md"
    just checksum >> ./target/"release-notes-$(convco version)/RELEASE.md"

    gh release create "v$(convco version)" --target "$(git rev-parse HEAD)" --title "eza v$(convco version)" -d -F ./target/"release-notes-$(convco version)/RELEASE.md" ./target/"bin-$(convco version)"/*

#----------------#
#    binaries    #
#----------------#

tar BINARY TARGET:
    tar czvf ./target/"bin-$(convco version)"/{{BINARY}}_{{TARGET}}.tar.gz -C ./target/{{TARGET}}/release/ ./{{BINARY}}

zip BINARY TARGET:
    zip -j ./target/"bin-$(convco version)"/{{BINARY}}_{{TARGET}}.zip ./target/{{TARGET}}/release/{{BINARY}}

tar_static BINARY TARGET:
    tar czvf ./target/"bin-$(convco version)"/{{BINARY}}_{{TARGET}}_static.tar.gz -C ./target/{{TARGET}}/release/ ./{{BINARY}}

zip_static BINARY TARGET:
    zip -j ./target/"bin-$(convco version)"/{{BINARY}}_{{TARGET}}_static.zip ./target/{{TARGET}}/release/{{BINARY}}

binary BINARY TARGET:
    rustup target add {{TARGET}}
    cross build --release --target {{TARGET}}
    just tar {{BINARY}} {{TARGET}}
    just zip {{BINARY}} {{TARGET}}

binary_static BINARY TARGET:
    rustup target add {{TARGET}}
    RUSTFLAGS='-C target-feature=+crt-static' cross build --release --target {{TARGET}}
    just tar_static {{BINARY}} {{TARGET}}
    just zip_static {{BINARY}} {{TARGET}}

checksum:
    @echo "# Checksums"
    @echo "## sha256sum"
    @echo '```'
    @sha256sum ./target/"bin-$(convco version)"/*
    @echo '```'
    @echo "## md5sum"
    @echo '```'
    @md5sum ./target/"bin-$(convco version)"/*
    @echo '```'

alias c := cross

# Generate release binaries for EZA
#
# usage: cross
@cross:
    # Setup Output Directory
    mkdir -p ./target/"bin-$(convco version)"

    # Install Toolchains/Targets
    rustup toolchain install stable

    ## Linux
    ### x86
    just binary eza x86_64-unknown-linux-gnu
    # just binary_static eza x86_64-unknown-linux-gnu
    just binary eza x86_64-unknown-linux-musl
    # just binary_static eza x86_64-unknown-linux-musl

    ### aarch
    just binary eza aarch64-unknown-linux-gnu
    # BUG: just binary_static eza aarch64-unknown-linux-gnu

    ### arm
    just binary eza arm-unknown-linux-gnueabihf
    # just binary_static eza arm-unknown-linux-gnueabihf

    ## MacOS
    # TODO: just binary eza x86_64-apple-darwin

    ## Windows
    ### x86
    just binary eza.exe x86_64-pc-windows-gnu
    # just binary_static eza.exe x86_64-pc-windows-gnu
    # TODO: just binary eza.exe x86_64-pc-windows-gnullvm
    # TODO: just binary eza.exe x86_64-pc-windows-msvc

    # Generate Checksums
    # TODO: moved to gh-release just checksum

#---------------------#
# Integration testing #
#---------------------#

alias gen := gen_test_dir

test_dir := "tests/test_dir"

gen_test_dir:
    bash devtools/dir-generator.sh {{ test_dir }}

# Runs integration tests in nix sandbox
#
# Required nix, likely won't work on windows.
@itest:
    nix build -L ./#trycmd-local

# Runs integration tests in nix sandbox, and dumps outputs.
#
# WARNING: this can cause loss of work
@idump:
    rm ./tests/gen/*_nix.stderr -f || echo
    rm ./tests/gen/*_nix.stdout -f || echo
    rm ./tests/gen/*_unix.stderr -f || echo
    rm ./tests/gen/*_unix.stdout -f || echo
    nix build -L ./#trydump
    cp ./result/dump/*.std* ./tests/gen/

@itest-gen:
    nix build -L ./#trycmd
