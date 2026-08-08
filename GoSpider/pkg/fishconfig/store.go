package fishconfig

import (
	"encoding/json"
	"sync"
)

// Store holds transient gateway state: thread settings and in-flight scan
// sessions. Credentials are NOT persisted here in production — Swift keeps
// them in Keychain and passes them back in each request payload. The store
// only holds values that have no Keychain counterpart (thread counts) and
// short-lived scan sessions.
type Store struct {
	mu      sync.Mutex
	threads map[string]int
	session map[string]map[string]any
	flags   map[string]bool // e.g. pan115_magnet_switch, community cookies
}

// NewStore builds an empty store.
func NewStore() *Store {
	return &Store{
		threads: map[string]int{},
		session: map[string]map[string]any{},
		flags:   map[string]bool{},
	}
}

// ThreadOptions are the 线程设置 choices exposed by every netdisk section.
var ThreadOptions = []int{1, 2, 4, 8, 16}

// GetThread returns the saved thread count for a netdisk (default 4).
func (s *Store) GetThread(netdisk string) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	if v, ok := s.threads[netdisk]; ok {
		return v
	}
	return 4
}

// SetThread saves a thread count (validated against ThreadOptions).
func (s *Store) SetThread(netdisk string, n int) bool {
	for _, o := range ThreadOptions {
		if o == n {
			s.mu.Lock()
			s.threads[netdisk] = n
			s.mu.Unlock()
			return true
		}
	}
	return false
}

// SaveSession stores a scan session for later login polling.
func (s *Store) SaveSession(netdisk string, sess map[string]any) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.session[netdisk] = sess
}

// TakeSession returns and removes a scan session.
func (s *Store) TakeSession(netdisk string) map[string]any {
	s.mu.Lock()
	defer s.mu.Unlock()
	sess := s.session[netdisk]
	delete(s.session, netdisk)
	return sess
}

// GetFlag / SetFlag are generic booleans (magnet switch, community cookie set).
func (s *Store) GetFlag(key string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.flags[key]
}

func (s *Store) SetFlag(key string, v bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.flags[key] = v
}

// decodePayload unmarshals a raw payload into out; empty payload is a no-op.
func decodePayload(raw json.RawMessage, out any) error {
	if len(raw) == 0 {
		return nil
	}
	return json.Unmarshal(raw, out)
}
