class Jv < Formula
  desc "Explainable Java runner for small projects"
  homepage "https://github.com/copydataai/jv"
  url "https://github.com/copydataai/jv/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_SHA256"
  license "MIT"

  depends_on "openjdk"

  def install
    bin.install "jv.sh" => "jv"
  end

  test do
    system "#{bin}/jv", "version"
  end
end
