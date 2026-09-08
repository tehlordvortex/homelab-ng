package pluginciliumtrustedips

import (
	"bufio"
	"context"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	saPath    = "/var/run/secrets/kubernetes.io/serviceaccount"
	crtPath   = saPath + "/ca.crt"
	tokenPath = saPath + "/token"
)

var (
	k8sHost, k8sPort = os.Getenv("KUBERNETES_SERVICE_HOST"), os.Getenv("KUBERNETES_SERVICE_PORT")
	apiServerUrl     = "https://" + net.JoinHostPort(k8sHost, k8sPort)
	// https://github.com/traefik/yaegi/issues/1720
	httpTransport http.RoundTripper = &k8sTransport{
		transport: http.DefaultTransport.(*http.Transport),
	}
	httpClient = &http.Client{
		Transport: httpTransport,
	}
	owies = &watchManager{watches: make(map[string]*ongoingWatch)}
)

type Config struct {
	LogLevel               string            `json:"logLevel,omitempty"`
	LogFormat              string            `json:"logFormat,omitempty"`
	CIDRGroupLabelSelector map[string]string `json:"cidrGroupLabelSelector,omitempty"`
	EndpointLabelSelector  map[string]string `json:"endpointLabelSelector,omitempty"`
	StaticTrustedCIDRs     []string          `json:"staticTrustedCIDRs,omitempty"`
}

func CreateConfig() *Config {
	return &Config{}
}

type CiliumTrustedIPs struct {
	next                   http.Handler
	name                   string
	cidrGroupLabelSelector string
	endpointLabelSelector  string

	logger *slog.Logger
}

type trustedIPSet struct {
	key string
	ips []*net.IPNet
}

type ipStore struct {
	atomic.Value
}

func (is *ipStore) Load() []*net.IPNet {
	return is.Value.Load().([]*net.IPNet)
}

func (is *ipStore) Store(ips []*net.IPNet) {
	is.Value.Store(ips)
}

func New(ctx context.Context, next http.Handler, config *Config, name string) (http.Handler, error) {
	slogLevel := slog.LevelInfo
	logFormat := "common"
	if config.LogLevel != "" {
		if err := slogLevel.UnmarshalText([]byte(config.LogLevel)); err != nil {
			return nil, fmt.Errorf("invalid log level: %w", err)
		}
	}
	if config.LogFormat != "" {
		logFormat = config.LogFormat
	}
	if logFormat != "common" && logFormat != "json" {
		return nil, fmt.Errorf("invalid log format: %s", logFormat)
	}

	var sh slog.Handler
	opts := &slog.HandlerOptions{Level: slogLevel}
	if logFormat == "json" {
		sh = slog.NewJSONHandler(os.Stdout, opts)
	} else {
		sh = slog.NewTextHandler(os.Stdout, opts)
	}
	logger := slog.New(sh).With("middleware", name)

	var labelSelectorValues []string
	for k, v := range config.CIDRGroupLabelSelector {
		labelSelectorValues = append(labelSelectorValues, k+"="+v)
	}
	cidrGroupLabelSelector := strings.Join(labelSelectorValues, ",")

	labelSelectorValues = nil
	for k, v := range config.EndpointLabelSelector {
		labelSelectorValues = append(labelSelectorValues, k+"="+v)
	}
	endpointLabelSelector := strings.Join(labelSelectorValues, ",")

	var staticIPs []*net.IPNet
	for _, addr := range config.StaticTrustedCIDRs {
		ipNet, err := parseCIDR(addr)
		if err != nil {
			return nil, fmt.Errorf("invalid static CIDR: %s: %w", addr, err)
		}
		staticIPs = append(staticIPs, ipNet)
	}

	trustedIPs := &ipStore{}
	trustedIPs.Store(staticIPs)
	next = NewXForwarded(logger.WithGroup("xForwarded"), trustedIPs, next)

	ipsCh := make(chan trustedIPSet)
	cti := &CiliumTrustedIPs{
		next:                  next,
		name:                  name,
		endpointLabelSelector: endpointLabelSelector,
		logger:                logger,
	}
	go updateTrustedIPs(ctx, logger, ipsCh, staticIPs, trustedIPs)

	logKey := slogLevel.String() + "@" + logFormat
	// Cilium node-local Envoy
	connectOrSubscribe(ctx, logger, owies, ipsCh, logKey, "/apis/cilium.io/v2/ciliumnodes", "", ciliumNodeCIDRs)

	if cidrGroupLabelSelector != "" {
		connectOrSubscribe(ctx, logger, owies, ipsCh, logKey, "/apis/cilium.io/v2/ciliumcidrgroups", cidrGroupLabelSelector, ciliumCIDRGroupCIDRs)
	} else {
		logger.Warn("cidrGroupLabelSelector is empty, no groups will be trusted")
	}

	if endpointLabelSelector != "" {
		connectOrSubscribe(ctx, logger, owies, ipsCh, logKey, "/apis/cilium.io/v2/ciliumendpoints", endpointLabelSelector, ciliumEndpointCIDRs)
	} else {
		logger.Warn("endpointLabelSelector is empty, no endpoints will be trusted")
	}

	logger.Info(
		"initialized",
		"staticCIDRs", config.StaticTrustedCIDRs,
		"cidrGroupLabelSelector", cidrGroupLabelSelector,
		"endpointLabelSelector", endpointLabelSelector,
	)
	return cti, nil
}

func parseCIDR(addr string) (*net.IPNet, error) {
	_, ipNet, err := net.ParseCIDR(addr)
	return ipNet, err
}

func ciliumNodeCIDRs(logger *slog.Logger, cn CiliumNode) (addrs []*net.IPNet) {
	logger = logger.WithGroup("nodeCIDRs")
	for _, addr := range cn.Spec.Addresses {
		// TODO: impact?
		// if addr.Type != "CiliumInternalIP" {
		// 	continue
		// }

		var cidr string
		if strings.IndexByte(addr.Ip, ':') >= 0 {
			cidr = addr.Ip + "/128"
		} else {
			cidr = addr.Ip + "/32"
		}
		ipNet, err := parseCIDR(cidr)
		if err != nil {
			logger.Debug("failed to parse as cidr", "cidr", cidr, "error", err)
			continue
		}

		addrs = append(addrs, ipNet)
	}

	return
}

func ciliumCIDRGroupCIDRs(logger *slog.Logger, cg CiliumCIDRGroup) (addrs []*net.IPNet) {
	logger = logger.WithGroup("cidrGroupCIDRs")
	for _, cidr := range cg.Spec.ExternalCIDRs {
		ipNet, err := parseCIDR(cidr)
		if err != nil {
			logger.Debug("failed to parse as cidr", "cidr", cidr, "error", err)
			continue
		}

		addrs = append(addrs, ipNet)
	}

	return
}

func ciliumEndpointCIDRs(logger *slog.Logger, cn CiliumEndpoint) (addrs []*net.IPNet) {
	logger = logger.WithGroup("endpointCIDRs")
	for _, addressing := range cn.Status.Networking.Addressing {
		v4 := addressing.IPv4 + "/32"
		v6 := addressing.IPv6 + "/128"

		ipNet, err := parseCIDR(v4)
		if err == nil {
			addrs = append(addrs, ipNet)
		} else {
			logger.Debug("failed to parse as cidr", "cidr", v4, "error", err)
		}

		ipNet, err = parseCIDR(v6)
		if err == nil {
			addrs = append(addrs, ipNet)
		} else {
			logger.Debug("failed to parse as cidr", "cidr", v6, "error", err)
		}
	}

	return
}

func (cti *CiliumTrustedIPs) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	cti.next.ServeHTTP(w, r)
}

func updateTrustedIPs(ctx context.Context, logger *slog.Logger, in <-chan trustedIPSet, staticIPs []*net.IPNet, trustedIPs *ipStore) error {
	sets := make(map[string][]*net.IPNet)

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case set := <-in:
			sets[set.key] = set.ips
			logger.Debug("updated trustedIPSet", "key", set.key, "ips", set.ips)

			allIps := append([]*net.IPNet(nil), staticIPs...)

			for _, ips := range sets {
				allIps = append(allIps, ips...)
			}

			trustedIPs.Store(allIps)
		}
	}
}

type watchManager struct {
	mu      sync.Mutex
	watches map[string]*ongoingWatch
}

func connectOrSubscribe[T any](ctx context.Context, logger *slog.Logger, wm *watchManager, out chan<- trustedIPSet, logKey string, path string, labelSelector string, mapper func(*slog.Logger, T) []*net.IPNet) {
	key := logKey + "@" + path + "@" + labelSelector
	logger = logger.WithGroup("watch").With(slog.Group("k8s", "path", path, "labelSelector", labelSelector))

	wm.mu.Lock()
	defer wm.mu.Unlock()

	if ow, ok := wm.watches[key]; ok {
		ow.subscribe(ctx, out)
		logger.Debug("subscribed to existing watch stream")
		return
	}

	watchCtx, ctxCancel := context.WithCancel(context.Background())
	cancel := func() {
		wm.mu.Lock()
		defer wm.mu.Unlock()
		defer ctxCancel()
		delete(wm.watches, key)
	}

	ow := &ongoingWatch{
		subs:   make(map[chan<- trustedIPSet]struct{}),
		cancel: cancel,
	}
	wm.watches[key] = ow
	go watch(watchCtx, logger, ow, path, labelSelector, mapper)

	ow.subscribe(ctx, out)
}

type (
	// This breaks in yaegi
	// mapperFunc[T any] func(*slog.Logger, T) []*net.IPNet
	ongoingWatch struct {
		mu     sync.Mutex
		subs   map[chan<- trustedIPSet]struct{}
		cancel context.CancelFunc
	}
)

func (ow *ongoingWatch) subscribe(ctx context.Context, ch chan<- trustedIPSet) {
	ow.mu.Lock()
	ow.subs[ch] = struct{}{}
	ow.mu.Unlock()

	go func() {
		<-ctx.Done()

		ow.mu.Lock()
		delete(ow.subs, ch)
		if len(ow.subs) == 0 {
			ow.cancel()
		}
		ow.mu.Unlock()
	}()
}

func (ow *ongoingWatch) publish(ctx context.Context, v trustedIPSet) error {
	ow.mu.Lock()
	defer ow.mu.Unlock()

	for ch := range ow.subs {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case ch <- v:
		}
	}

	return nil
}

type watchEvent[T any] struct {
	Type   string `json:"type"`
	Object T      `json:"object"`
}

func watch[T any](ctx context.Context, logger *slog.Logger, ow *ongoingWatch, path string, labelSelector string, mapper func(*slog.Logger, T) []*net.IPNet) error {
	defer logger.Debug("stopping watch stream after last subscriber")

	nextRetry := func() <-chan time.Time {
		return time.After(3 * time.Second)
	}
	syncList := func(items map[string][]*net.IPNet) error {
		var itemList []*net.IPNet
		for _, item := range items {
			itemList = append(itemList, item...)
		}

		return ow.publish(ctx, trustedIPSet{path, itemList})
	}

	reqUrl := apiServerUrl + path + "?watch=true&sendInitialEvents=true&resourceVersionMatch=NotOlderThan&allowWatchBookmarks=true"
	if labelSelector != "" {
		reqUrl += "&labelSelector=" + url.QueryEscape(labelSelector)
	}

	for {
		r, err := http.NewRequestWithContext(ctx, "GET", reqUrl, nil)
		if err != nil {
			panic(err)
		}

		err = streamOnce(logger, r, mapper, syncList)
		if ctx.Err() != nil {
			return ctx.Err()
		}

		logger.Warn("connection to api server failed or ended, will reconnect", "error", err)
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-nextRetry():
		}
	}
}

type k8sTransport struct {
	transport *http.Transport
	mu        sync.RWMutex
}

var _ http.RoundTripper = &k8sTransport{}

func (kt *k8sTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	kt.mu.RLock()
	transport := kt.transport
	kt.mu.RUnlock()

	// Tying every request to two FS reads isn't the most performant
	// but in our case we don't care all that much because requests should be
	// infrequent: inital connections and retries
	// client-go has more complex logic to cache the token/CA, not worth it for
	// this tiny lil plugin
	pem, err := os.ReadFile(crtPath)
	if err != nil {
		return nil, fmt.Errorf("failed to load kube root CA: %w", err)
	}

	ca := x509.NewCertPool()
	if !ca.AppendCertsFromPEM(pem) {
		return nil, fmt.Errorf("kube root CA is invalid")
	}

	if !ca.Equal(transport.TLSClientConfig.RootCAs) {
		old := transport
		transport = transport.Clone()
		transport.TLSClientConfig.RootCAs = ca

		kt.mu.Lock()
		kt.transport = transport
		kt.mu.Unlock()

		old.CloseIdleConnections()
	}

	raw, err := os.ReadFile(tokenPath)
	if err != nil {
		return nil, fmt.Errorf("failed to load SA token: %w", err)
	}
	token := string(raw)
	req.Header.Set("Authorization", "Bearer "+token)

	return transport.RoundTrip(req)
}

func streamOnce[T any](logger *slog.Logger, req *http.Request, mapper func(*slog.Logger, T) []*net.IPNet, syncList func(map[string][]*net.IPNet) error) error {
	items := make(map[string][]*net.IPNet)

	res, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to connect to api server: %s", err)
	}
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(res.Body)
		return fmt.Errorf("non-200 status: %s: %s", res.Status, string(body))
	}
	logger.Debug("connected to watch stream")

	var initialListComplete bool
	s := bufio.NewScanner(res.Body)
	for s.Scan() {
		line := s.Bytes()
		logger.Debug("watch stream event", "line", string(line))

		var ev watchEvent[PartialObjectMetadata]
		if err := json.Unmarshal(line, &ev); err != nil {
			return fmt.Errorf("invalid json: %w", err)
		}
		key := ev.Object.Namespace + "/" + ev.Object.Name

		switch true {
		case ev.Type == "ERROR":
			return fmt.Errorf("watch stream error: %s", string(line))
		case ev.Type == "BOOKMARK":
			if _, ok := ev.Object.Annotations["k8s.io/initial-events-end"]; ok {
				logger.Debug("initial list complete")
				initialListComplete = true
				if err := syncList(items); err != nil {
					return err
				}
			}
		case ev.Type == "DELETED":
			delete(items, key)

			if initialListComplete {
				if err := syncList(items); err != nil {
					return err
				}
			}
		case ev.Type == "ADDED":
			fallthrough
		case ev.Type == "MODIFIED":
			var tev watchEvent[T]
			if err := json.Unmarshal(line, &tev); err != nil {
				return fmt.Errorf("invalid json: %w", err)
			}

			items[key] = mapper(logger, tev.Object)

			if initialListComplete {
				if err := syncList(items); err != nil {
					return err
				}
			}

		default:
			return fmt.Errorf("unrecognized watch event: %s", ev.Type)

		}
	}

	return s.Err()
}

// https://github.com/kubernetes/kubernetes/blob/master/staging/src/k8s.io/apimachinery/pkg/apis/meta/v1/types.go

type TypeMeta struct {
	Kind       string `json:"kind,omitempty"`
	APIVersion string `json:"apiVersion,omitempty"`
}

type ObjectMeta struct {
	Name        string            `json:"name,omitempty"`
	Namespace   string            `json:"namespace,omitempty"`
	Labels      map[string]string `json:"labels,omitempty"`
	Annotations map[string]string `json:"annotations,omitempty"`
}

type PartialObjectMetadata struct {
	TypeMeta   `json:""`
	ObjectMeta `json:"metadata,omitempty"`
}

type CiliumNode struct {
	PartialObjectMetadata `json:""`
	Spec                  struct {
		Addresses []struct {
			Ip   string `json:"ip,omitempty"`
			Type string `json:"type,omitempty"`
		} `json:"addresses,omitempty"`
	} `json:"spec"`
}

type CiliumCIDRGroup struct {
	PartialObjectMetadata `json:""`
	Spec                  struct {
		ExternalCIDRs []string `json:"externalCIDRs"`
	} `json:"spec"`
}

type CiliumEndpoint struct {
	PartialObjectMetadata `json:""`
	Status                struct {
		Networking struct {
			Addressing []struct {
				IPv4 string `json:"ipv4,omitempty"`
				IPv6 string `json:"ipv6,omitempty"`
			} `json:"addressing"`
		} `json:"networking,omitempty"`
	} `json:"status,omitempty"`
}
