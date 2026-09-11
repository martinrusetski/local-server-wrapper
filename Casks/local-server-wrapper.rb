cask "local-server-wrapper" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/martinrusetski/local-server-wrapper/releases/download/v#{version}/LocalServerWrapper-v#{version}.dmg"
  name "Local Server Wrapper"
  desc "Turn local web servers into standalone apps"
  homepage "https://github.com/martinrusetski/local-server-wrapper"

  auto_updates true
  depends_on macos: :ventura

  app "LocalServerWrapper.app"

  # Ad-hoc signed distribution, matching the DMG installation instructions.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/LocalServerWrapper.app"]
  end

  zap trash: [
    "~/Library/Application Support/LocalServerWrapper",
    "~/Library/Frameworks/ServerRuntime.framework",
  ]
end
