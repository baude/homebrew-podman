class Podman < Formula
  desc "Tool for managing OCI containers and pods"
  homepage "https://podman.io/"
  license "Apache-2.0"

  stable do
    url "https://github.com/containers/podman/archive/v4.0.2.tar.gz"
    sha256 "cac4328b0a5e618f4f6567944e255d15fad3e1f7901df55603f1efdd7aaeda95"
	patch do
	    url "https://patch-diff.githubusercontent.com/raw/containers/podman/pull/13409.patch"
        sha256 "02313460b545da994381bb51ccf44996ddcb8ecbcb6212e2a4d4f45d39c1d587"
       end
       patch do
           url "https://fedorapeople.org/groups/podman/testing/darwin_qemu_search_paths.patch"
           sha256 "6315f2c8071b0bdba5c3346c4581aaed70696a7e63c3a361a1e1bd78eb5a3f51"
       end
    resource "gvproxy" do
      url "https://github.com/containers/gvisor-tap-vsock/archive/v0.3.0.tar.gz"
      sha256 "6ca454ae73fce3574fa2b615e6c923ee526064d0dc2bcf8dab3cca57e9678035"
    end
   resource "podman-qemu" do
	#head "https://gitlab.com/wwcohen/qemu.git", branch: "9p-darwin"
         url "https://download.qemu.org/qemu-6.2.0.tar.xz"
         sha256 "68e15d8e45ac56326e0b9a4afa8b49a3dfe8aba3488221d098c84698bca65b45"
         patch do
             url "https://github.com/qemu/qemu/compare/v6.2.0...willcohen:0024dfc24f88410fe9d85ef8e4a27cbc7283b87a.patch"
             sha256 "72a35081f1ad79529580a78339dfbcc808c85e7de4120e0b47d1769330b59449"
         end 
       end

  end

  head do
    url "https://github.com/containers/podman.git", branch: "main"

    resource "gvproxy" do
      url "https://github.com/containers/gvisor-tap-vsock.git", branch: "main"
    end
  end

  depends_on "go" => :build
  depends_on "go-md2man" => :build
  depends_on "libtool" => :build
  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkg-config" => :build

  depends_on "glib"
  depends_on "gnutls"
  depends_on "jpeg"
  depends_on "libpng"
  depends_on "libslirp"
  depends_on "libssh"
  depends_on "libusb"
  depends_on "lzo"
  depends_on "ncurses"
  depends_on "nettle"
  depends_on "pixman"
  depends_on "snappy"
  depends_on "vde"

  on_linux do
    depends_on "attr"
    depends_on "gcc"
    depends_on "gtk+3"
    depends_on "libcap-ng"
  end

  fails_with gcc: "5"

  def install
    ENV["CGO_ENABLED"] = "1"
    os = OS.kernel_name.downcase

    inreplace "vendor/github.com/containers/common/pkg/config/config_#{os}.go",
              "/usr/local/libexec/podman",
              libexec

    system "make", "podman-remote-#{os}"
    if OS.mac?
      bin.install "bin/#{os}/podman" => "podman-remote"
      bin.install_symlink bin/"podman-remote" => "podman"
      bin.install "bin/#{os}/podman-mac-helper" => "podman-mac-helper"
    else
      bin.install "bin/podman-remote"
    end

    resource("gvproxy").stage do
      system "make", "gvproxy"
      libexec.install "bin/gvproxy"
    end

   resource("podman-qemu").stage do
         ENV["LIBTOOL"] = "glibtool"
         args = %W[
           --prefix=#{libexec}
           --cc=#{ENV.cc}
           --host-cc=#{ENV.cc}
           --disable-bsd-user
           --disable-guest-agent
           --enable-curses
           --enable-libssh
           --enable-slirp=system
           --enable-vde
	   --enable-virtfs
           --extra-cflags=-DNCURSES_WIDECHAR=1
           --disable-sdl
           --target-list=aarch64-softmmu,x86_64-softmmu
         ]
         # Sharing Samba directories in QEMU requires the samba.org smbd which is
         # incompatible with the macOS-provided version. This will lead to
         # silent runtime failures, so we set it to a Homebrew path in order to
         # obtain sensible runtime errors. This will also be compatible with
         # Samba installations from external taps.
         args << "--smbd=#{HOMEBREW_PREFIX}/sbin/samba-dot-org-smbd"
    
         args << "--disable-gtk" if OS.mac?
         args << "--enable-cocoa" if OS.mac?
         args << "--enable-gtk" if OS.linux?
   
	 system "mv hw/9pfs/9p-util.c hw/9pfs/9p-util-linux.c" unless build.head?
 
         system "./configure", *args
         system "make", "V=1", "install"
       end

    system "make", "podman-remote-#{os}-docs"
    man1.install Dir["docs/build/remote/#{os}/*.1"]

    bash_completion.install "completions/bash/podman"
    zsh_completion.install "completions/zsh/_podman"
    fish_completion.install "completions/fish/podman.fish"
  end

  test do
    assert_match "podman-remote version #{version}", shell_output("#{bin}/podman-remote -v")
    assert_match(/Cannot connect to Podman/i, shell_output("#{bin}/podman-remote info 2>&1", 125))

    machineinit_output = shell_output("podman-remote machine init --image-path fake-testi123 fake-testvm 2>&1", 125)
    assert_match "Error: open fake-testi123: no such file or directory", machineinit_output
  end
end
