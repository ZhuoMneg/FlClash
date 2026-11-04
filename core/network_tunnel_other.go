//go:build !windows

package core

func tunnelPreferredInterface(string) int { return 0 }
