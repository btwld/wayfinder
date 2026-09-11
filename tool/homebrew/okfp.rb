# Generated release pins are maintained by conceptadev/wayfinder.
class Okfp < Formula
  desc "Concepta OKF Profile validation gate"
  homepage "https://pub.dev/packages/okf_profile"
  url "https://pub.dev/api/archives/okf_profile-0.2.1-dev.0.tar.gz"
  version "0.2.1-dev.0"
  sha256 "cf5f99fb5c414f42db8d81d25a38ec2f8ee707d0d5bcf399c8367d9f1abd1055"
  license "Apache-2.0"

  # Refresh the digests from the checksum published beside each SDK archive:
  #   curl "<archive url>.sha256sum"
  dart_sdk_version = "3.13.3"
  dart_sdk_url, dart_sdk_sha = if OS.mac? && Hardware::CPU.intel?
    ["https://storage.googleapis.com/dart-archive/channels/stable/release/#{dart_sdk_version}/sdk/dartsdk-macos-x64-release.zip",
     "df957f34954c03c6551ff1ca7ce0c31038039689345f8b4d658aa5e69e28495c"]
  elsif OS.mac? && Hardware::CPU.arm?
    ["https://storage.googleapis.com/dart-archive/channels/stable/release/#{dart_sdk_version}/sdk/dartsdk-macos-arm64-release.zip",
     "c703bcbb25ca0cc5df9109fb8272d52786ac14782437bd9e365a01985273c1cc"]
  elsif OS.linux? && Hardware::CPU.intel?
    ["https://storage.googleapis.com/dart-archive/channels/stable/release/#{dart_sdk_version}/sdk/dartsdk-linux-x64-release.zip",
     "549c182cffbdc6864df7509c16fec646c73fe6cb8a18c2cb572db1292f300cd7"]
  elsif OS.linux? && Hardware::CPU.arm?
    ["https://storage.googleapis.com/dart-archive/channels/stable/release/#{dart_sdk_version}/sdk/dartsdk-linux-arm64-release.zip",
     "c59c535623f3ab9717e8755237df695f153fb3af3bfb0f6c281b2eb4fefe669e"]
  end

  resource "dart-sdk" do
    url dart_sdk_url
    sha256 dart_sdk_sha
  end

  def install
    # Into buildpath, not libexec: the SDK is only needed to compile, and
    # keeping it would leave a ~620MB keg behind for a 10MB executable.
    (buildpath/"dart-sdk").install resource("dart-sdk")

    ENV["PUB_ENVIRONMENT"] = "homebrew:okfp"

    # The published archive is built independently of its source workspace.
    inreplace "pubspec.yaml", "resolution: workspace\n", ""
    dart = buildpath/"dart-sdk/bin/dart"
    system dart, "pub", "get"
    system dart, "compile", "exe", "bin/okfp.dart", "-o", "okfp"
    bin.install "okfp"
  end

  test do
    assert_match "okfp #{version}", shell_output("#{bin}/okfp --version")
  end
end
