# typed: strict
# frozen_string_literal: true

# Homebrew cask for this fork of Simple Comic.
#
# Belongs in a tap repository — GitHub repo `Wiredframe/homebrew-tap`, path
# `Casks/simple-comic.rb` — and is kept here so it ships with the source it describes. After a
# release, update `version` and `sha256` from the output of scripts/release.sh and push the tap.
#
# The token deliberately matches Homebrew's own `simple-comic` cask: this is the same app, and
# it installs to the same place. Users disambiguate with the full name,
# `brew install --cask --no-quarantine wiredframe/tap/simple-comic`, and `conflicts_with` stops
# the two from being installed on top of each other by accident.
#
# The build is not notarised (see scripts/release.sh for why), so macOS quarantines the
# download and would refuse to open it on the first try. Homebrew's DSL has no stanza to opt out
# of that, but a `postflight` block runs after the app is in place, and clearing the attribute
# there spares every user from knowing about `--no-quarantine`. The caveats say plainly that
# this happened.
#
# `sha256` must match the asset that was actually published: take it from the release notes the
# workflow writes, not from a local build, since two builds of the same source do not produce
# byte-identical zips.

cask "simple-comic" do
  version "2.0.1"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/Wiredframe/Simple-Comic/releases/download/v#{version}/Simple-Comic-#{version}.zip",
      verified: "github.com/Wiredframe/"
  name "Simple Comic"
  desc "Comic viewer with a paper effect and a library"
  homepage "https://github.com/Wiredframe/Simple-Comic"

  conflicts_with cask: "homebrew/cask/simple-comic"
  depends_on macos: ">= :big_sur"

  app "Simple Comic.app"

  postflight do
    # Same effect as installing with --no-quarantine, minus the need to know about the flag.
    # `must_succeed: false` because the attribute is legitimately absent when someone did pass
    # the flag, and xattr treats that as an error.
    system_command "/usr/bin/xattr",
                   args:         ["-dr", "com.apple.quarantine", "#{appdir}/Simple Comic.app"],
                   must_succeed: false
  end

  zap trash: [
    "~/Library/Application Scripts/de.wiredframe.simplecomic",
    "~/Library/Containers/de.wiredframe.simplecomic",
    "~/Library/Containers/de.wiredframe.simplecomic.QuickComic-Preview",
    "~/Library/Containers/de.wiredframe.simplecomic.QuickComic-Thumbnailer",
    "~/Library/Saved Application State/de.wiredframe.simplecomic.savedState",
  ]

  caveats <<~EOS
    This build is signed but not notarised by Apple, so macOS quarantined the download.
    The cask has cleared that flag for you, which is what lets the app open normally.
    If you would rather macOS asked you, reinstall and run instead:
      xattr -w com.apple.quarantine "0081;00000000;;" "/Applications/Simple Comic.app"
  EOS
end
