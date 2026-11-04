package core

import (
	"golang.org/x/sys/windows"
	"net/netip"
)

func tunnelPreferredInterface(host string) int {
	ip, err := netip.ParseAddr(host)
	if err != nil || !ip.Is4() {
		return 0
	}
	var index uint32
	if windows.GetBestInterfaceEx(&windows.SockaddrInet4{Addr: ip.As4()}, &index) != nil {
		return 0
	}
	return int(index)
}
