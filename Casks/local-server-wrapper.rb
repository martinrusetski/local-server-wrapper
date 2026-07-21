cask "local-server-wrapper" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/martinrusetski/local-server-wrapper/releases/download/v#{version}/LocalServerWrapper-v#{version}.dmg"
  name "Local Server Wrapper"
  desc "Turn local web servers into standalone menu-bar Mac apps"
  homepage "https://github.com/martinrusetski/local-server-wrapper"

  depends_on macos: :ventura

  app "LocalServerWrapper.app"

  # The app is ad-hoc signed (not notarized); clear the quarantine flag so it
  # launches without the Gatekeeper prompt.
  postflight do
    system_command "/usr/bin/xattr", args: ["-cr", "#{appdir}/LocalServerWrapper.app"]
  end

  # The manager installs the shared runtime here; generated server apps land in
  # /Applications when the user creates them, so those are left untouched.
  zap trash: [
    "~/Library/Application Support/LocalServerWrapper",
    "~/Library/Frameworks/ServerRuntime.framework",
  ]
end
