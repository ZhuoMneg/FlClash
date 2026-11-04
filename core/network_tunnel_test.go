package core

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"os"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"go.yaml.in/yaml/v3"
)

func testTunnelConfig() NetworkTunnelConfig {
	key := base64.StdEncoding.EncodeToString(make([]byte, 32))
	return NetworkTunnelConfig{Enabled: true, Extension: true, Host: "179.253.249.97", Port: 27034, Pin: strings.Repeat("a", 64), Token: strings.Repeat("t", 48), PrivateKey: key, PublicKey: key, IP: "10.203.77.2", IPv6: "fd42:203:77::2", DNS: "10.203.77.1"}
}

func TestTunnelValidation(t *testing.T) {
	c := testTunnelConfig()
	if err := c.validate(); err != nil {
		t.Fatal(err)
	}
	for _, modify := range []func(*NetworkTunnelConfig){
		func(c *NetworkTunnelConfig) { c.Host = "127.0.0.1" }, func(c *NetworkTunnelConfig) { c.Host = "100.64.1.1" },
		func(c *NetworkTunnelConfig) { c.Token += "\n" }, func(c *NetworkTunnelConfig) { c.PrivateKey = "bad" },
		func(c *NetworkTunnelConfig) { c.DNS = "not-an-ip" }, func(c *NetworkTunnelConfig) { c.IPv6 = "1.1.1.1" },
	} {
		bad := c
		modify(&bad)
		if bad.validate() == nil {
			t.Fatal("accepted invalid config")
		}
	}
	for _, address := range []string{"10.0.0.1", "172.28.215.8", "100.127.1.1", "0.1.1.1", "198.18.1.1", "::1"} {
		if publicTunnelIPv4(netip.MustParseAddr(address)) {
			t.Fatalf("accepted non-public endpoint %s", address)
		}
	}
}

func TestTunnelExtensionPreservesChainsAndDirectRules(t *testing.T) {
	raw := config.DefaultRawConfig()
	raw.Proxy = []map[string]any{
		{"name": "first", "type": "ss", "dialer-proxy": "second"},
		{"name": "second", "type": "ss", "dialer-proxy": "direct-upstream"},
		{"name": "direct-upstream", "type": "direct"},
	}
	raw.ProxyGroup = []map[string]any{{"name": "select", "type": "select", "proxies": []string{"first", "second", "DIRECT"}, "include-all": true}}
	raw.Rule = []string{"DOMAIN,baidu.com,DIRECT", "MATCH,select"}
	c := testTunnelConfig()
	if err := extendNetworkTunnel(raw, &c); err != nil {
		t.Fatal(err)
	}
	if raw.Proxy[0]["dialer-proxy"] != "second" || raw.Proxy[1]["dialer-proxy"] != networkTunnelName {
		t.Fatal("lost node chain")
	}
	if raw.Rule[len(raw.Rule)-2] != "DOMAIN,baidu.com,DIRECT" {
		t.Fatal("lost direct rule")
	}
	if !strings.Contains(raw.ProxyGroup[0]["exclude-filter"].(string), networkTunnelName) {
		t.Fatal("WG included in normal group")
	}
	if raw.Proxy[3]["server"] != "127.0.0.1" {
		t.Fatal("WG does not use loopback bridge")
	}
	if extendNetworkTunnel(raw, &c) == nil {
		t.Fatal("old extension was accepted")
	}
	c.Extension = false
	if err := extendNetworkTunnel(raw, &c); err != nil {
		t.Fatal(err)
	}
}

func TestTunnelRejectsLeakingAndCyclicDialers(t *testing.T) {
	for _, members := range [][]string{{"DIRECT"}, {"node"}, {"missing"}} {
		raw := config.DefaultRawConfig()
		raw.Proxy = []map[string]any{{"name": "node", "type": "socks5", "server": "127.0.0.1", "port": 9, "dialer-proxy": "upstream"}}
		raw.ProxyGroup = []map[string]any{{"name": "upstream", "type": "select", "proxies": members}}
		c := testTunnelConfig()
		if err := extendNetworkTunnel(raw, &c); err != nil {
			t.Fatal(err)
		}
		cfg, err := config.ParseRawConfig(raw)
		if err != nil {
			continue
		}
		err = validateTunnelChains(raw, cfg)
		closeNetworkTunnelCandidate(cfg)
		if err == nil {
			t.Fatalf("accepted bad dialer %v", members)
		}
	}
}

func tunnelChainTestRaw() *config.RawConfig {
	raw := config.DefaultRawConfig()
	raw.Proxy = []map[string]any{
		{"name": "node", "type": "socks5", "server": "127.0.0.1", "port": 9, "dialer-proxy": "upstream"},
		{"name": "upstream-node", "type": "http", "server": "127.0.0.1", "port": 10},
	}
	raw.Rule = []string{"MATCH,node"}
	return raw
}

func parseTunnelChainTest(t *testing.T, raw *config.RawConfig) *config.Config {
	t.Helper()
	c := testTunnelConfig()
	if err := extendNetworkTunnel(raw, &c); err != nil {
		t.Fatal(err)
	}
	cfg, err := config.ParseRawConfig(raw)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { closeNetworkTunnelCandidate(cfg) })
	return cfg
}

func TestTunnelUsesFilteredDialerGroupMembers(t *testing.T) {
	for _, options := range []map[string]any{
		{"include-all": true, "filter": "^upstream-node$"},
		{"include-all-proxies": true, "exclude-filter": "^node$"},
		{"include-all-proxies": true, "exclude-type": "socks5"},
		{"proxies": []string{"upstream-node", "DIRECT"}, "exclude-filter": "^DIRECT$"},
		{"include-all": true, "filter": "^upstream-node$", "exclude-filter": "^unused-a$`^unused-b$"},
	} {
		raw := tunnelChainTestRaw()
		group := map[string]any{"name": "upstream", "type": "select"}
		for key, value := range options {
			group[key] = value
		}
		raw.ProxyGroup = []map[string]any{group}
		cfg := parseTunnelChainTest(t, raw)
		if err := validateTunnelChains(raw, cfg); err != nil {
			t.Fatalf("rejected filtered group %v: %v", options, err)
		}
	}
}

func TestTunnelRejectsDirectEmptyGroupFallback(t *testing.T) {
	for _, options := range []map[string]any{
		{"proxies": []string{"upstream-node"}, "exclude-filter": "^upstream-node$"},
		{"proxies": []string{"upstream-node"}, "exclude-type": "http"},
		{"include-all": true, "filter": "^missing$"},
		{"proxies": []string{"upstream-node"}, "exclude-filter": "^upstream-node$", "empty-fallback": "DIRECT"},
	} {
		raw := tunnelChainTestRaw()
		group := map[string]any{"name": "upstream", "type": "select"}
		for key, value := range options {
			group[key] = value
		}
		raw.ProxyGroup = []map[string]any{group}
		cfg := parseTunnelChainTest(t, raw)
		if err := validateTunnelChains(raw, cfg); err == nil {
			t.Fatalf("accepted direct fallback for filtered group %v", options)
		}
	}
}

func TestTunnelAcceptsRejectEmptyGroupFallback(t *testing.T) {
	raw := tunnelChainTestRaw()
	raw.ProxyGroup = []map[string]any{{"name": "upstream", "type": "select", "proxies": []string{"upstream-node"}, "exclude-filter": "^upstream-node$", "empty-fallback": "REJECT"}}
	cfg := parseTunnelChainTest(t, raw)
	if err := validateTunnelChains(raw, cfg); err != nil {
		t.Fatal(err)
	}
}

func TestTunnelLoadRejectsUnsafeFallbackBeforeWriting(t *testing.T) {
	previous := C.Path.HomeDir()
	C.SetHomeDir(t.TempDir())
	t.Cleanup(func() { C.SetHomeDir(previous) })
	raw := tunnelChainTestRaw()
	raw.ProxyGroup = []map[string]any{{"name": "upstream", "type": "select", "proxies": []string{"upstream-node"}, "exclude-filter": "^upstream-node$"}}
	raw.Listeners = []map[string]any{{"name": "unstarted-tun", "type": "tun", "stack": "gvisor"}}
	data, err := json.Marshal(raw)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(runningConfigPath(), data, 0o600); err != nil {
		t.Fatal(err)
	}
	c := testTunnelConfig()
	params := &SetupParams{}
	params.NetworkTunnel = &c
	if _, err = loadSetupConfig(params); err == nil || !strings.Contains(err.Error(), "direct choice") {
		t.Fatalf("unsafe setup result: %v", err)
	}
	after, err := os.ReadFile(runningConfigPath())
	if err != nil || string(after) != string(data) {
		t.Fatalf("rejected setup changed its input: %v", err)
	}
}

func TestTunnelLoadPersistsCompleteConfig(t *testing.T) {
	for _, withBase := range []bool{false, true} {
		name := "running-config"
		if withBase {
			name = "profile-base"
		}
		t.Run(name, func(t *testing.T) {
			previous := C.Path.HomeDir()
			C.SetHomeDir(t.TempDir())
			t.Cleanup(func() { C.SetHomeDir(previous) })
			raw := config.DefaultRawConfig()
			raw.MixedPort = 7890
			raw.Proxy = []map[string]any{{"name": "home", "type": "socks5", "server": "10.203.77.1", "port": 7893}}
			raw.ProxyGroup = []map[string]any{{"name": "select", "type": "select", "proxies": []string{"home"}}}
			raw.Rule = []string{"DOMAIN,baidu.com,DIRECT", "MATCH,select"}
			data, err := yaml.Marshal(raw)
			if err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(runningConfigPath(), data, 0o600); err != nil {
				t.Fatal(err)
			}
			c := testTunnelConfig()
			params := &SetupParams{}
			params.NetworkTunnel = &c
			if withBase {
				path := writeBaseProfile(t, string(data))
				base, err := handleGetProfileBase(PathParams{Path: path})
				if err != nil {
					t.Fatal(err)
				}
				params.Base = &SetupBase{Path: path, Overlay: overlayOf(t, base, nil, nil)}
			}
			cfg, err := loadSetupConfig(params)
			if err != nil {
				t.Fatalf("load tunnel config: %v", err)
			}
			t.Cleanup(func() { closeNetworkTunnelCandidate(cfg) })
			persisted, err := handleReadConfig(PathParams{Path: runningConfigPath()})
			if err != nil {
				t.Fatalf("read persisted tunnel config: %v", err)
			}
			if persisted.MixedPort != 7890 || len(persisted.Proxy) != 2 || len(persisted.ProxyGroup) != 1 {
				t.Fatalf("persisted config lost sections: port=%d proxies=%d groups=%d", persisted.MixedPort, len(persisted.Proxy), len(persisted.ProxyGroup))
			}
			if persisted.Proxy[0]["dialer-proxy"] != networkTunnelName || persisted.Proxy[1]["name"] != networkTunnelName {
				t.Fatal("persisted config lost WG proxy or dialer")
			}
			if !reflect.DeepEqual(persisted.Rule[len(persisted.Rule)-len(raw.Rule):], raw.Rule) {
				t.Fatalf("persisted config lost original rules: %v", persisted.Rule)
			}
			reloaded, err := config.ParseRawConfig(persisted)
			if err != nil {
				t.Fatalf("parse persisted config for reload: %v", err)
			}
			t.Cleanup(func() { closeNetworkTunnelCandidate(reloaded) })
			if reloaded.Proxies[networkTunnelName] == nil || reloaded.Proxies["home"] == nil {
				t.Fatal("persisted config cannot restore tunnel proxies")
			}
		})
	}
}

func TestTunnelDirectoryPinsAndRejectsStaleOrPrivateEndpoints(t *testing.T) {
	endpoint := tunnelEndpoint{IP: "119.39.89.123", Port: 15140, HandshakeAge: 1, ServerTime: time.Now().Unix()}
	token := strings.Repeat("t", 48)
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer "+token || r.URL.Path != "/v1/endpoint" {
			t.Error("wrong request")
		}
		_ = json.NewEncoder(w).Encode(endpoint)
	}))
	defer server.Close()
	host, port, _ := net.SplitHostPort(server.Listener.Addr().String())
	number, _ := strconv.Atoi(port)
	digest := sha256.Sum256(server.Certificate().Raw)
	c := NetworkTunnelConfig{Host: host, Port: number, Pin: hex.EncodeToString(digest[:]), Token: token}
	dial := (&net.Dialer{}).DialContext
	result, err := queryTunnelDirectory(context.Background(), c, dial)
	if err != nil || result.String() != "119.39.89.123:15140" {
		t.Fatalf("query: %v %v", result, err)
	}
	c.Pin = strings.Repeat("0", 64)
	if _, err = queryTunnelDirectory(context.Background(), c, dial); err == nil {
		t.Fatal("accepted wrong pin")
	}
	c.Pin = hex.EncodeToString(digest[:])
	endpoint.HandshakeAge = 201
	if _, err = queryTunnelDirectory(context.Background(), c, dial); err == nil {
		t.Fatal("accepted stale handshake")
	}
	endpoint.HandshakeAge = 1
	endpoint.IP = "192.168.6.1"
	if _, err = queryTunnelDirectory(context.Background(), c, dial); err == nil {
		t.Fatal("accepted private home endpoint")
	}
}

func TestTunnelUDPBridgeStopsAndRejectsOtherSenders(t *testing.T) {
	listen := func() *net.UDPConn {
		conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = conn.Close() })
		return conn
	}
	local, outer, home, client, other := listen(), listen(), listen(), listen(), listen()
	ctx, cancel := context.WithCancel(context.Background())
	s := &networkTunnelSession{ctx: ctx, cancel: cancel, local: local, outer: outer, home: home.LocalAddr().(*net.UDPAddr).AddrPort()}
	s.launch("test local", s.receiveLocal)
	s.launch("test outer", func() { s.receiveOuter(outer) })
	defer s.stop()
	packet := make([]byte, 32)
	packet[0] = 4
	if _, err := client.WriteToUDP(packet, local.LocalAddr().(*net.UDPAddr)); err != nil {
		t.Fatal(err)
	}
	_ = home.SetReadDeadline(time.Now().Add(time.Second))
	buffer := make([]byte, 100)
	n, sender, err := home.ReadFromUDP(buffer)
	if err != nil || n != 32 {
		t.Fatalf("forward: %d %v", n, err)
	}
	_, _ = other.WriteToUDP(packet, sender)
	_ = client.SetReadDeadline(time.Now().Add(30 * time.Millisecond))
	if _, _, err = client.ReadFromUDP(buffer); err == nil {
		t.Fatal("accepted unsolicited sender")
	}
	_, _ = home.WriteToUDP(packet, sender)
	_ = client.SetReadDeadline(time.Now().Add(time.Second))
	if _, _, err = client.ReadFromUDP(buffer); err != nil {
		t.Fatal(err)
	}
	s.mu.Lock()
	received := s.received
	s.mu.Unlock()
	if received != 32 {
		t.Fatalf("reply count %d", received)
	}
	s.stop()
	replacement, err := net.ListenUDP("udp4", local.LocalAddr().(*net.UDPAddr))
	if err != nil {
		t.Fatal("listener leaked", err)
	}
	_ = replacement.Close()
}

type tunnelReadErrorPacketConn struct {
	net.PacketConn
	err    error
	closed bool
}

func (c *tunnelReadErrorPacketConn) ReadFrom([]byte) (int, net.Addr, error) {
	return 0, nil, c.err
}

func (c *tunnelReadErrorPacketConn) Close() error {
	c.closed = true
	return nil
}

func TestTunnelUDPReceiveErrorSchedulesRebind(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	outer := &tunnelReadErrorPacketConn{err: errors.New("adapter read failed")}
	s := &networkTunnelSession{ctx: ctx, outer: outer, refresh: make(chan struct{}, 1)}
	s.receiveOuter(outer)
	if s.outer != nil || !outer.closed {
		t.Fatal("failed socket remained active")
	}
	if !strings.Contains(s.lastError, "adapter read failed") {
		t.Fatalf("receive error was not reported: %q", s.lastError)
	}
	select {
	case <-s.refresh:
	default:
		t.Fatal("failed socket did not request immediate rebind")
	}
}

func TestTunnelUDPReceiveErrorPreservesStopAndReplacement(t *testing.T) {
	for _, stopped := range []bool{false, true} {
		t.Run(strconv.FormatBool(stopped), func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			old := &tunnelReadErrorPacketConn{err: net.ErrClosed}
			current := net.PacketConn(old)
			if stopped {
				cancel()
			} else {
				current = &tunnelReadErrorPacketConn{}
			}
			s := &networkTunnelSession{ctx: ctx, outer: current, refresh: make(chan struct{}, 1), lastError: "unchanged"}
			s.receiveOuter(old)
			if s.outer != current || old.closed || s.lastError != "unchanged" {
				t.Fatal("intentional socket shutdown changed session state")
			}
			select {
			case <-s.refresh:
				t.Fatal("intentional socket shutdown requested rebind")
			default:
			}
		})
	}
}
