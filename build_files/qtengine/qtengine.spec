%global commit 167e7d9a27cdc8005ef2bd4d5d317b9da01b853f

Name:           qtengine
Version:        0.2.2
Release:        2%{?dist}
Summary:        Qt5 and Qt6 platform themes using KDE color schemes
License:        BSD-2-Clause
URL:            https://github.com/kossLAN/qtengine
Source0:        https://github.com/kossLAN/qtengine/archive/%{commit}.tar.gz#/qtengine-%{version}.tar.gz

BuildRequires:  gcc-c++
BuildRequires:  cmake
BuildRequires:  extra-cmake-modules
BuildRequires:  qt5-qtbase-devel
BuildRequires:  qt5-qtbase-private-devel
BuildRequires:  qt5-qtbase-static
BuildRequires:  qt5-qtquickcontrols2-devel
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtbase-private-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  kf5-kconfig-devel
BuildRequires:  kf5-kconfigwidgets-devel
BuildRequires:  kf5-kiconthemes-devel
BuildRequires:  kf6-kconfig-devel
BuildRequires:  kf6-kcolorscheme-devel
BuildRequires:  kf6-kiconthemes-devel

%description
Qt platform theme and style plugins for Qt5 and Qt6 applications, using a
shared JSON configuration and KDE color schemes.

%prep
echo '2480d872f8fc3ee3fced8c773a7ea9a150a850b250345c82c111521ea7ed49b2  %{SOURCE0}' | sha256sum --check --strict
%autosetup -n qtengine-%{commit}

%build
%cmake -DBUILD_QT5=ON -DBUILD_QT6=ON -DCMAKE_SKIP_INSTALL_RPATH=ON \
    -DQT5_PLUGINDIR=%{_libdir}/qt5/plugins \
    -DQT6_PLUGINDIR=%{_libdir}/qt6/plugins \
    -DQT5_LIBDIR=%{_libdir}
%cmake_build

%install
%cmake_install

%files
%license LICENSE
%doc README.md
%{_libdir}/libqt5engine-common.so
%{_libdir}/libqt6engine-common.so
%{_libdir}/qt5/plugins/platformthemes/libqt5engine-plugin.so
%{_libdir}/qt5/plugins/styles/libqt5engine-style.so
%{_libdir}/qt6/plugins/platformthemes/libqt6engine-plugin.so
%{_libdir}/qt6/plugins/styles/libqt6engine-style.so

%changelog
* Sun Nov 08 2026 Justin Schwerdtfeger <justinschwerdtfeger@users.noreply.github.com> - 0.2.2-2
- Rebuild both Qt plugins for Fedora 45.
