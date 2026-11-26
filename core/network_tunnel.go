package core

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/tls"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand/v2"
	"net"
	"net/http"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"go.yaml.in/yaml/v3"
)

const networkTunnelName = "__HOME_ROUTER_WG__"
const networkTunnelPort = 51832

type NetworkTunnelConfig struct {
	Enabled    bool   `json:"enabled"`
	Extension  bool   `json:"extension"`
	Host       string `json:"host"`
	Port       int    `json:"port"`
	Pin        string `json:"pin"`
	Token      string `json:"token"`
	PrivateKey string `json:"privateKey"`
	PublicKey  string `json:"publicKey"`
	IP         string `json:"ip"`
	IPv6       string `json:"ipv6"`
	DNS        string `json:"dns"`
	Interface  string `json:"interface"`
}

func (c *NetworkTunnelConfig) configured() bool { return c != nil && c.Host != "" }

func (c *NetworkTunnelConfig) validate() error {
	ip, err := netip.ParseAddr(c.Host)
	if err != nil || !publicTunnelIPv4(ip) || c.Port < 1 || c.Port > 65535 {
		return errors.New("network tunnel: invalid directory IPv4 or port")
	}
	pin, err := hex.DecodeString(c.Pin)
	if err != nil || len(pin) != sha256.Size || len(c.Token) < 40 || len(c.Token) > 512 || strings.ContainsAny(c.Token, "\r\n") {
		return errors.New("network tunnel: invalid directory credentials")
	}
	for _, key := range []string{c.PrivateKey, c.PublicKey} {
		decoded, err := base64.StdEncoding.DecodeString(key)
		if err != nil || len(decoded) != 32 {
			return errors.New("network tunnel: invalid WireGuard key")
		}
	}
	ip, err = netip.ParseAddr(c.IP)
	dns, dnsErr := netip.ParseAddr(c.DNS)
	if err != nil || !ip.Is4() || !ip.IsGlobalUnicast() || dnsErr != nil || !dns.Is4() || !dns.IsGlobalUnicast() {
		return errors.New("network tunnel: invalid tunnel IPv4 or DNS")
	}
	if c.IPv6 != "" {
		ip, err = netip.ParseAddr(c.IPv6)
		if err != nil || !ip.Is6() || !ip.IsGlobalUnicast() {
			return errors.New("network tunnel: invalid tunnel IPv6")
		}
	}
	return nil
}

type tunnelEndpoint struct {
	IP           string `json:"ip"`
	Port         int    `json:"port"`
	HandshakeAge int64  `json:"handshake_age"`
	ServerTime   int64  `json:"server_time"`
}

func publicTunnelIPv4(ip netip.Addr) bool {
	return ip.Is4() && ip.IsGlobalUnicast() && !ip.IsPrivate() && !ip.IsLoopback() &&
		!netip.MustParsePrefix("100.64.0.0/10").Contains(ip) &&
		!netip.MustParsePrefix("0.0.0.0/8").Contains(ip) &&
		!netip.MustParsePrefix("198.18.0.0/15").Contains(ip)
}

func (e tunnelEndpoint) address() (netip.AddrPort, error) {
	ip, err := netip.ParseAddr(e.IP)
	if err != nil || !publicTunnelIPv4(ip) || e.Port < 1 || e.Port > 65535 {
		return netip.AddrPort{}, errors.New("network tunnel: invalid home endpoint")
	}
	return netip.AddrPortFrom(ip, uint16(e.Port)), nil
}

type networkTunnelSession struct {
	cfg           NetworkTunnelConfig
	ctx           context.Context
	cancel        context.CancelFunc
	wg            sync.WaitGroup
	refresh       chan struct{}
	local         *net.UDPConn
	mu            sync.Mutex
	outer         net.PacketConn
	physical      string
	interfaceName string
	home          netip.AddrPort
	client        netip.AddrPort
	sent          atomic.Uint64
	received      atomic.Uint64
	lastQuery     time.Time
	lastReply     atomic.Int64
	lastError     string
}

var networkTunnelState struct {
	sync.Mutex
	desired *NetworkTunnelConfig
	session *networkTunnelSession
}

func configureNetworkTunnel(c *NetworkTunnelConfig) error {
	if c != nil && c.configured() {
		if err := c.validate(); err != nil {
			return err
		}
		copy := *c
		c = &copy
	} else {
		c = nil
	}
	networkTunnelState.Lock()
	defer networkTunnelState.Unlock()
	networkTunnelState.desired = c
	return reconcileNetworkTunnelLocked()
}

func reconcileNetworkTunnelLocked() error {
	c := networkTunnelState.desired
	s := networkTunnelState.session
	if c != nil && c.Enabled && isRunning.Load() && s != nil {
		previous, next := s.cfg, *c
		previous.Extension = next.Extension
		if previous == next {
			return nil
		}
	}
	if s != nil {
		s.stop()
		networkTunnelState.session = nil
	}
	if c == nil || !c.Enabled || !isRunning.Load() {
		return nil
	}
	s, err := startNetworkTunnel(*c)
	if err != nil {
		return err
	}
	networkTunnelState.session = s
	return nil
}

func reconcileNetworkTunnel() error {
	networkTunnelState.Lock()
	defer networkTunnelState.Unlock()
	return reconcileNetworkTunnelLocked()
}

func handleNetworkTunnelStatus() map[string]any {
	networkTunnelState.Lock()
	defer networkTunnelState.Unlock()
	result := map[string]any{"running": false}
	if c := networkTunnelState.desired; c != nil {
		result["enabled"] = c.Enabled
		result["extension"] = c.Extension
	}
	if s := networkTunnelState.session; s != nil {
		s.mu.Lock()
		defer s.mu.Unlock()
		result["running"] = true
		result["home"] = s.home.String()
		result["physical"] = s.physical
		result["sent"] = s.sent.Load()
		result["received"] = s.received.Load()
		if !s.lastQuery.IsZero() {
			result["lastQuery"] = s.lastQuery.Unix()
		}
		if lastReply := s.lastReply.Load(); lastReply > 0 {
			result["lastReply"] = lastReply
		}
		result["error"] = s.lastError
	}
	return result
}

func handleRefreshNetworkTunnel() bool {
	networkTunnelState.Lock()
	defer networkTunnelState.Unlock()
	if s := networkTunnelState.session; s != nil {
		select {
		case s.refresh <- struct{}{}:
		default:
		}
		return true
	}
	return false
}

func handleNetworkTunnelNetworkChanged() {
	networkTunnelState.Lock()
	s := networkTunnelState.session
	networkTunnelState.Unlock()
	if s != nil {
		s.forceRebind()
	}
}

func startNetworkTunnel(c NetworkTunnelConfig) (*networkTunnelSession, error) {
	local, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: networkTunnelPort})
	if err != nil {
		return nil, fmt.Errorf("network tunnel local listener: %w", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	s := &networkTunnelSession{cfg: c, ctx: ctx, cancel: cancel, local: local, refresh: make(chan struct{}, 1)}
	_ = local.SetReadBuffer(4 << 20)
	s.loadCache()
	s.launch("tunnel local", s.receiveLocal)
	s.launch("tunnel directory", s.run)
	return s, nil
}

func (s *networkTunnelSession) launch(name string, fn func()) {
	s.wg.Add(1)
	safeGo(name, func() { defer s.wg.Done(); fn() })
}

func (s *networkTunnelSession) stop() {
	s.cancel()
	_ = s.local.Close()
	s.mu.Lock()
	if s.outer != nil {
		_ = s.outer.Close()
	}
	s.mu.Unlock()
	s.wg.Wait()
}

func tunnelPhysicalInterface(preferred, host string) (string, string, error) {
	interfaces, err := net.Interfaces()
	if err != nil {
		return "", "", err
	}
	if preferred == "" {
		index := tunnelPreferredInterface(host)
		for i := range interfaces {
			if interfaces[i].Index == index {
				interfaces[0], interfaces[i] = interfaces[i], interfaces[0]
				break
			}
		}
	}
	for _, iface := range interfaces {
		name := strings.ToLower(iface.Name)
		if preferred != "" && preferred != iface.Name {
			continue
		}
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 || len(iface.HardwareAddr) == 0 {
			continue
		}
		blocked := []string{"wireguard", "wintun", "flclash", "tailscale", "virtual", "vmware", "vethernet", "atrust"}
		if preferred != "" {
			blocked = []string{"wintun", "flclash"}
		}
		virtual := false
		for _, word := range blocked {
			if strings.Contains(name, word) {
				virtual = true
				break
			}
		}
		if virtual {
			continue
		}
		addresses, _ := iface.Addrs()
		for _, address := range addresses {
			prefix, err := netip.ParsePrefix(address.String())
			if err == nil && prefix.Addr().Is4() && prefix.Addr().IsGlobalUnicast() {
				return iface.Name, prefix.Addr().String(), nil
			}
		}
	}
	return "", "", errors.New("no physical IPv4 interface available")
}

func (s *networkTunnelSession) rebind() error {
	name, ip, err := tunnelPhysicalInterface(s.cfg.Interface, s.cfg.Host)
	if err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.ctx.Err() != nil {
		return s.ctx.Err()
	}
	if s.outer != nil && s.physical == ip && s.interfaceName == name {
		return nil
	}
	host, _ := netip.ParseAddr(s.cfg.Host)
	outer, err := dialer.ListenPacket(s.ctx, "udp4", net.JoinHostPort(ip, "0"), netip.AddrPortFrom(host, uint16(s.cfg.Port)), dialer.WithInterface(name))
	if err != nil {
		return err
	}
	if conn, ok := outer.(*net.UDPConn); ok {
		_ = conn.SetReadBuffer(4 << 20)
		_ = conn.SetWriteBuffer(1 << 20)
	}
	old := s.outer
	s.outer = outer
	s.physical = ip
	s.interfaceName = name
	s.launch("tunnel outer", func() { s.receiveOuter(outer) })
	if old != nil {
		_ = old.Close()
	}
	return nil
}

func (s *networkTunnelSession) query() (netip.AddrPort, error) {
	s.mu.Lock()
	name := s.interfaceName
	s.mu.Unlock()
	if name == "" {
		return netip.AddrPort{}, errors.New("physical interface is not ready")
	}
	return queryTunnelDirectory(s.ctx, s.cfg, func(ctx context.Context, network, address string) (net.Conn, error) {
		return dialer.DialContext(ctx, "tcp4", address, dialer.WithInterface(name))
	})
}

func queryTunnelDirectory(ctx context.Context, c NetworkTunnelConfig, physicalDial func(context.Context, string, string) (net.Conn, error)) (netip.AddrPort, error) {
	pin, _ := hex.DecodeString(c.Pin)
	transport := &http.Transport{
		Proxy: nil, MaxResponseHeaderBytes: 8192,
		DialContext: physicalDial,
		TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12, InsecureSkipVerify: true, VerifyConnection: func(state tls.ConnectionState) error {
			// The private directory uses a pinned self-signed certificate.
			if len(state.PeerCertificates) == 0 {
				return errors.New("missing directory certificate")
			}
			actual := sha256.Sum256(state.PeerCertificates[0].Raw)
			if subtle.ConstantTimeCompare(pin, actual[:]) != 1 {
				return errors.New("directory certificate mismatch")
			}
			return nil
		}},
	}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 8 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("directory redirect refused") }}
	request, err := http.NewRequestWithContext(ctx, "GET", "https://"+net.JoinHostPort(c.Host, fmt.Sprint(c.Port))+"/v1/endpoint", nil)
	if err != nil {
		return netip.AddrPort{}, err
	}
	request.Header.Set("Authorization", "Bearer "+c.Token)
	response, err := client.Do(request)
	if err != nil {
		return netip.AddrPort{}, err
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return netip.AddrPort{}, fmt.Errorf("directory HTTP %d", response.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, 4097))
	if err != nil || len(data) > 4096 {
		return netip.AddrPort{}, errors.New("invalid directory response size")
	}
	var endpoint tunnelEndpoint
	if err = json.Unmarshal(data, &endpoint); err != nil {
		return netip.AddrPort{}, errors.New("invalid directory response")
	}
	age := time.Now().Unix() - endpoint.ServerTime
	if endpoint.HandshakeAge < 0 || endpoint.HandshakeAge > 200 || age < -900 || age > 900 {
		return netip.AddrPort{}, errors.New("directory result is stale; check system clock")
	}
	return endpoint.address()
}

func (s *networkTunnelSession) run() {
	failures := 0
	for s.ctx.Err() == nil {
		err := s.rebind()
		var endpoint netip.AddrPort
		if err == nil {
			endpoint, err = s.query()
		}
		s.mu.Lock()
		changed := false
		if err == nil && s.ctx.Err() == nil {
			changed = s.home != endpoint
			s.home = endpoint
			s.lastQuery = time.Now()
			s.lastError = ""
			failures = 0
		} else if err != nil {
			s.lastError = err.Error()
			failures++
		}
		s.mu.Unlock()
		if changed {
			s.saveCache(endpoint)
		}
		delay := 10 * time.Second
		if failures > 0 {
			delay = time.Duration(1<<min(failures, 5))*time.Second + time.Duration(rand.IntN(500))*time.Millisecond
		}
		timer := time.NewTimer(delay)
		select {
		case <-s.ctx.Done():
			timer.Stop()
			return
		case <-s.refresh:
			timer.Stop()
		case <-timer.C:
		}
	}
}

func (s *networkTunnelSession) receiveLocal() {
	buffer := make([]byte, 65536)
	for {
		n, from, err := s.local.ReadFromUDPAddrPort(buffer)
		if err != nil {
			return
		}
		if !from.Addr().IsLoopback() || n < 16 || buffer[0] < 1 || buffer[0] > 4 || buffer[1] != 0 || buffer[2] != 0 || buffer[3] != 0 {
			continue
		}
		s.mu.Lock()
		s.client = from
		outer, home := s.outer, s.home
		s.mu.Unlock()
		if outer != nil && home.IsValid() {
			if _, err = outer.WriteTo(buffer[:n], net.UDPAddrFromAddrPort(home)); err == nil {
				s.sent.Add(uint64(n))
			} else {
				s.resetOuter(outer, err)
			}
		}
	}
}

func (s *networkTunnelSession) receiveOuter(outer net.PacketConn) {
	buffer := make([]byte, 65536)
	for {
		n, from, err := outer.ReadFrom(buffer)
		if err != nil {
			s.resetOuter(outer, err)
			return
		}
		s.mu.Lock()
		home, client := s.home, s.client
		current := s.outer == outer
		s.mu.Unlock()
		var fromAddr netip.AddrPort
		if udpAddr, ok := from.(*net.UDPAddr); ok {
			ap := udpAddr.AddrPort()
			fromAddr = netip.AddrPortFrom(ap.Addr().Unmap(), ap.Port())
		} else if parsed, parseErr := netip.ParseAddrPort(from.String()); parseErr == nil {
			fromAddr = netip.AddrPortFrom(parsed.Addr().Unmap(), parsed.Port())
		}
		if !current || !client.IsValid() || !fromAddr.IsValid() || fromAddr != home {
			continue
		}
		if _, err = s.local.WriteToUDPAddrPort(buffer[:n], client); err == nil {
			s.received.Add(uint64(n))
			s.lastReply.Store(time.Now().Unix())
		}
	}
}

func (s *networkTunnelSession) forceRebind() {
	s.mu.Lock()
	if s.ctx.Err() != nil {
		s.mu.Unlock()
		return
	}
	old := s.outer
	s.outer = nil
	s.physical = ""
	s.interfaceName = ""
	select {
	case s.refresh <- struct{}{}:
	default:
	}
	s.mu.Unlock()
	if old != nil {
		_ = old.Close()
	}
}

func (s *networkTunnelSession) resetOuter(outer net.PacketConn, err error) {
	s.mu.Lock()
	if s.ctx.Err() != nil || s.outer != outer {
		s.mu.Unlock()
		return
	}
	s.outer = nil
	s.lastError = fmt.Sprintf("network tunnel UDP: %v", err)
	select {
	case s.refresh <- struct{}{}:
	default:
	}
	s.mu.Unlock()
	_ = outer.Close()
}

func (s *networkTunnelSession) cachePath() string {
	identity := sha256.Sum256([]byte(s.cfg.Host + ":" + fmt.Sprint(s.cfg.Port) + s.cfg.Pin + s.cfg.PublicKey))
	return filepath.Join(C.Path.HomeDir(), "network-tunnel-"+hex.EncodeToString(identity[:8])+".json")
}

func (s *networkTunnelSession) loadCache() {
	data, err := os.ReadFile(s.cachePath())
	if err != nil {
		return
	}
	var endpoint tunnelEndpoint
	if json.Unmarshal(data, &endpoint) == nil {
		s.home, _ = endpoint.address()
	}
}

func (s *networkTunnelSession) saveCache(address netip.AddrPort) {
	data, _ := json.Marshal(tunnelEndpoint{IP: address.Addr().String(), Port: int(address.Port())})
	file, err := os.CreateTemp(C.Path.HomeDir(), ".tunnel-cache-*")
	if err != nil {
		return
	}
	name := file.Name()
	defer os.Remove(name)
	if _, err = file.Write(data); err != nil {
		file.Close()
		return
	}
	if file.Close() != nil {
		return
	}
	_ = os.Rename(name, s.cachePath())
}

func loadNetworkTunnelConfig(params *SetupParams) (*config.Config, error) {
	var document yaml.Node
	if params.Base != nil {
		merged, err := mergeProfileBase(params.Base)
		if err != nil {
			return nil, err
		}
		document = *merged
	} else {
		data, err := os.ReadFile(runningConfigPath())
		if err != nil {
			return nil, err
		}
		if err = yaml.Unmarshal(data, &document); err != nil {
			return nil, err
		}
	}
	raw := config.DefaultRawConfig()
	if err := document.Decode(raw); err != nil {
		return nil, err
	}
	if err := extendNetworkTunnel(raw, params.NetworkTunnel); err != nil {
		return nil, err
	}
	cfg, err := config.ParseRawConfig(raw)
	if err != nil {
		return nil, err
	}
	accepted := false
	defer func() {
		if !accepted {
			closeNetworkTunnelCandidate(cfg)
		}
	}()
	if err = validateTunnelChains(raw, cfg); err != nil {
		return nil, err
	}
	if err = document.Encode(raw); err != nil {
		return nil, err
	}
	if err = writeConfigDocumentWithMode(runningConfigPath(), &document, 0o600); err != nil {
		return nil, err
	}
	accepted = true
	return withPlatformLimits(cfg), nil
}

func closeNetworkTunnelCandidate(cfg *config.Config) {
	for _, provider := range cfg.Providers {
		if closer, ok := provider.(io.Closer); ok {
			_ = closer.Close()
		}
	}
	for _, provider := range cfg.RuleProviders {
		if closer, ok := provider.(io.Closer); ok {
			_ = closer.Close()
		}
	}
	for _, proxy := range cfg.Proxies {
		_ = proxy.Close()
	}
}

func extendNetworkTunnel(raw *config.RawConfig, c *NetworkTunnelConfig) error {
	if !c.configured() || !c.Extension {
		return nil
	}
	if err := c.validate(); err != nil {
		return err
	}
	if len(raw.ProxyProvider) > 0 {
		return errors.New("network tunnel: proxy-providers are not supported; use a static subscription")
	}
	if len(raw.Proxy) == 0 {
		return errors.New("network tunnel: no subscription nodes")
	}
	for _, p := range raw.Proxy {
		if p["name"] == networkTunnelName {
			return errors.New("network tunnel: disable the old home extension script first")
		}
	}
	passive := func(p map[string]any) bool {
		t, _ := p["type"].(string)
		switch strings.ToLower(t) {
		case "direct", "reject", "pass", "dns":
			return true
		}
		return false
	}
	directNames := map[string]bool{}
	for _, p := range raw.Proxy {
		name, _ := p["name"].(string)
		kind, _ := p["type"].(string)
		if strings.EqualFold(kind, "direct") {
			directNames[name] = true
		}
	}
	for _, p := range raw.Proxy {
		if passive(p) {
			continue
		}
		upstream, _ := p["dialer-proxy"].(string)
		if directNames[upstream] {
			upstream = "DIRECT"
		}
		if upstream == "" || upstream == "DIRECT" || upstream == "COMPATIBLE" {
			p["dialer-proxy"] = networkTunnelName
		}
	}
	wg := map[string]any{"name": networkTunnelName, "type": "wireguard", "server": "127.0.0.1", "port": networkTunnelPort, "ip": c.IP, "private-key": c.PrivateKey, "public-key": c.PublicKey, "allowed-ips": []string{"0.0.0.0/0", "::/0"}, "persistent-keepalive": 15, "mtu": 1280, "udp": true, "remote-dns-resolve": true, "dns": []string{c.DNS}}
	if c.IPv6 != "" {
		wg["ipv6"] = c.IPv6
		raw.IPv6 = true
	}
	raw.Proxy = append(raw.Proxy, wg)
	for _, g := range raw.ProxyGroup {
		if g["include-all"] == true || g["include-all-proxies"] == true {
			exclude, _ := g["exclude-filter"].(string)
			if exclude != "" {
				exclude += "`"
			}
			g["exclude-filter"] = exclude + "^__HOME_ROUTER_WG__$"
		}
	}
	raw.Rule = append([]string{"IP-CIDR," + c.DNS + "/32," + networkTunnelName + ",no-resolve", "DOMAIN,myip.ipip.net," + networkTunnelName, "IP-CIDR,127.0.0.1/32,DIRECT,no-resolve"}, raw.Rule...)
	return nil
}

func validateTunnelChains(raw *config.RawConfig, cfg *config.Config) error {
	checked, checking := map[string]bool{}, map[string]bool{}
	var visit func(string) error
	visit = func(name string) error {
		if name == networkTunnelName || checked[name] {
			return nil
		}
		if checking[name] {
			return errors.New("network tunnel: proxy chain cycle")
		}
		proxy := cfg.Proxies[name]
		if proxy == nil {
			return fmt.Errorf("network tunnel: unresolved dialer %s", name)
		}
		checking[name] = true
		if group, ok := proxy.Adapter().(outboundgroup.ProxyGroup); ok {
			members := group.Proxies()
			if len(members) == 0 {
				return fmt.Errorf("network tunnel: empty dialer group %s", name)
			}
			for _, member := range members {
				if err := visit(member.Name()); err != nil {
					return err
				}
			}
		} else {
			switch proxy.Type() {
			case C.Reject, C.RejectDrop:
			case C.Direct, C.Compatible, C.Pass, C.PassRule, C.Rematch, C.Dns:
				return fmt.Errorf("network tunnel: direct choice in dialer chain %s", name)
			default:
				if err := visit(proxy.ProxyInfo().DialerProxy); err != nil {
					return err
				}
			}
		}
		delete(checking, name)
		checked[name] = true
		return nil
	}
	for _, p := range raw.Proxy {
		name, _ := p["name"].(string)
		if name == networkTunnelName {
			continue
		}
		t, _ := p["type"].(string)
		switch strings.ToLower(t) {
		case "direct", "reject", "pass", "dns":
			continue
		}
		if err := visit(name); err != nil {
			return err
		}
	}
	return nil
}
