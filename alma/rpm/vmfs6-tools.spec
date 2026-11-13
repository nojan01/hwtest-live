%global commit 582b525
Name:           vmfs6-tools
Version:        0.2.1
Release:        1%{?dist}
Summary:        Tools to access VMFS6 (VMware ESXi 6.x/7.x) file systems
License:        GPL-2.0-or-later
URL:            https://github.com/teward/vmfs6-tools
Source0:        http://deb.debian.org/debian/pool/main/v/vmfs6-tools/vmfs6-tools_%{version}.orig.tar.gz

BuildRequires:  gcc make pkgconfig(uuid) readline-devel fuse-devel
BuildRequires:  asciidoc libxslt docbook-style-xsl
Requires:       fuse

%description
debugvmfs6, fsck.vmfs6, vmfs6-fuse and vmfs6-lvm for VMFS 6 volumes
(read-only via FUSE). Same sources as Debian trixie (teward fork).

%prep
%autosetup -n teward-%{name}-%{commit}

%build
./configure --prefix=%{_prefix} --sbindir=%{_sbindir} --mandir=%{_mandir}
%make_build

%install
%make_install NO_STRIP=1

%files
%license LICENSE
%doc README AUTHORS
%{_sbindir}/debugvmfs6
%{_sbindir}/fsck.vmfs6
%{_sbindir}/vmfs6-fuse
%{_sbindir}/vmfs6-lvm
%{_mandir}/man8/*.8*

%changelog
* Wed Nov 05 2026 Norbert Jander <36399468+nojan01@users.noreply.github.com> - 0.2.1-1
- Build für hwtest-live (AlmaLinux 9) aus den Debian-Quellen
