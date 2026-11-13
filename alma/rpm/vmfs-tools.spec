Name:           vmfs-tools
Version:        0.2.5
Release:        1%{?dist}
Summary:        Tools to access VMFS (VMware ESX/ESXi 3-5) file systems
License:        GPL-2.0-or-later
URL:            https://glandium.org/projects/vmfs-tools/
Source0:        http://deb.debian.org/debian/pool/main/v/vmfs-tools/vmfs-tools_%{version}.orig.tar.gz
Source1:        http://deb.debian.org/debian/pool/main/v/vmfs-tools/vmfs-tools_%{version}-1.1.debian.tar.xz

BuildRequires:  gcc make pkgconfig(uuid) readline-devel fuse-devel
BuildRequires:  asciidoc libxslt docbook-style-xsl
Requires:       fuse

%description
debugvmfs, fsck.vmfs, vmfs-fuse and vmfs-lvm for VMFS 3 and 5 volumes
(read-only via FUSE). Same sources and patches as Debian trixie.

%prep
%autosetup -n %{name}-%{version} -a 1
patch -p1 < debian/patches/debian.patch

%build
./configure --prefix=%{_prefix} --sbindir=%{_sbindir} --mandir=%{_mandir}
%make_build

%install
%make_install NO_STRIP=1

%files
%license LICENSE
%doc README AUTHORS
%{_sbindir}/debugvmfs
%{_sbindir}/fsck.vmfs
%{_sbindir}/vmfs-fuse
%{_sbindir}/vmfs-lvm
%{_mandir}/man8/*.8*

%changelog
* Wed Nov 05 2026 Norbert Jander <36399468+nojan01@users.noreply.github.com> - 0.2.5-1
- Build für hwtest-live (AlmaLinux 9) aus den Debian-Quellen
