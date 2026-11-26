package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

const (
	// Internal server origin used strictly for API calls & TCP latency probes.
	// Never display this address or port in any launcher UI text or error message.
	defaultAccountAPIBase = "http://151.242.136.36:30041"
	defaultManilaHostPort = "151.242.136.36:30041"
	apiRequestTimeout     = 8 * time.Second
)

type apiUserProfile struct {
	Username      string `json:"username"`
	Online        bool   `json:"online"`
	LastSeenUnix  int64  `json:"last_seen_unix"`
	LastSeenText  string `json:"last_seen_text"`
	Relation      string `json:"relation,omitempty"`
	AvatarHash    string `json:"avatar_hash"`
	AvatarFrames  int    `json:"avatar_frames"`
	AvatarDelayMs int    `json:"avatar_delay_ms"`
	AvatarB64     string `json:"avatar_b64,omitempty"`
}

type apiRoomInvite struct {
	FromUsername string `json:"from_username"`
	RoomCode     string `json:"room_code"`
}

type apiFriendsOverview struct {
	Friends          []apiUserProfile `json:"friends"`
	IncomingRequests []apiUserProfile `json:"incoming_requests"`
	OutgoingRequests []apiUserProfile `json:"outgoing_requests"`
	RoomInvites      []apiRoomInvite  `json:"room_invites"`
}

type serverError struct {
	msg string
}

func (e serverError) Error() string {
	return e.msg
}

type accountAPIClient struct {
	baseURL    string
	httpClient *http.Client
}

func newAccountAPIClient(baseURL string, client *http.Client) *accountAPIClient {
	base := strings.TrimSpace(baseURL)
	if base == "" {
		base = strings.TrimSpace(os.Getenv("WWP_ACCOUNT_API"))
	}
	if base == "" {
		base = defaultAccountAPIBase
	}
	base = strings.TrimRight(base, "/")
	if client == nil {
		client = &http.Client{Timeout: apiRequestTimeout}
	}
	return &accountAPIClient{baseURL: base, httpClient: client}
}

// sanitizeUserError ensures transport errors never expose internal server IPs, ports, or URLs.
func sanitizeUserError(err error) string {
	if err == nil {
		return ""
	}
	var se serverError
	if errors.As(err, &se) && strings.TrimSpace(se.msg) != "" {
		return se.msg
	}
	return "Unable to reach game servers. Check your connection."
}

func (c *accountAPIClient) doJSON(ctx context.Context, method, path, token string, reqBody any, out any) error {
	var bodyReader io.Reader
	if reqBody != nil {
		raw, err := json.Marshal(reqBody)
		if err != nil {
			return err
		}
		bodyReader = bytes.NewReader(raw)
	}

	reqCtx, cancel := context.WithTimeout(ctx, apiRequestTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(reqCtx, method, c.baseURL+path, bodyReader)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", userAgent)
	if strings.TrimSpace(token) != "" {
		req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(token))
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return err
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var errWrap struct {
			Error string `json:"error"`
		}
		if json.Unmarshal(respBytes, &errWrap) == nil && strings.TrimSpace(errWrap.Error) != "" {
			return serverError{msg: strings.TrimSpace(errWrap.Error)}
		}
		if resp.StatusCode == http.StatusUnauthorized {
			return serverError{msg: "Session expired — please sign in again."}
		}
		return serverError{msg: fmt.Sprintf("Request rejected (status %d)", resp.StatusCode)}
	}

	if out != nil && len(bytes.TrimSpace(respBytes)) > 0 {
		return json.Unmarshal(respBytes, out)
	}
	return nil
}

func (c *accountAPIClient) Register(ctx context.Context, username, password string) (string, apiUserProfile, error) {
	var res struct {
		Token string         `json:"token"`
		User  apiUserProfile `json:"user"`
	}
	err := c.doJSON(ctx, http.MethodPost, "/api/auth/register", "", map[string]string{
		"username": strings.TrimSpace(username),
		"password": password,
	}, &res)
	if err != nil {
		return "", apiUserProfile{}, err
	}
	if res.Token == "" {
		return "", apiUserProfile{}, serverError{msg: "Invalid server response"}
	}
	return res.Token, res.User, nil
}

func (c *accountAPIClient) Login(ctx context.Context, username, password string) (string, apiUserProfile, error) {
	var res struct {
		Token string         `json:"token"`
		User  apiUserProfile `json:"user"`
	}
	err := c.doJSON(ctx, http.MethodPost, "/api/auth/login", "", map[string]string{
		"username": strings.TrimSpace(username),
		"password": password,
	}, &res)
	if err != nil {
		return "", apiUserProfile{}, err
	}
	if res.Token == "" {
		return "", apiUserProfile{}, serverError{msg: "Invalid server response"}
	}
	return res.Token, res.User, nil
}

func (c *accountAPIClient) Me(ctx context.Context, token string) (apiUserProfile, error) {
	var res struct {
		User apiUserProfile `json:"user"`
	}
	err := c.doJSON(ctx, http.MethodGet, "/api/auth/me", token, nil, &res)
	return res.User, err
}

func (c *accountAPIClient) Logout(ctx context.Context, token string) error {
	return c.doJSON(ctx, http.MethodPost, "/api/auth/logout", token, nil, nil)
}

func (c *accountAPIClient) UploadAvatar(ctx context.Context, token string, rawBytes []byte) (apiUserProfile, error) {
	var res struct {
		User apiUserProfile `json:"user"`
	}
	err := c.doJSON(ctx, http.MethodPost, "/api/profile/avatar", token, map[string]string{
		"data_b64": base64.StdEncoding.EncodeToString(rawBytes),
	}, &res)
	return res.User, err
}

func (c *accountAPIClient) FriendsOverview(ctx context.Context, token string) (apiFriendsOverview, error) {
	var res apiFriendsOverview
	err := c.doJSON(ctx, http.MethodGet, "/api/friends", token, nil, &res)
	return res, err
}

func (c *accountAPIClient) SearchUsers(ctx context.Context, token, query string) ([]apiUserProfile, error) {
	var res struct {
		Users []apiUserProfile `json:"users"`
	}
	err := c.doJSON(ctx, http.MethodGet, "/api/users/search?q="+url.QueryEscape(strings.TrimSpace(query)), token, nil, &res)
	return res.Users, err
}

func (c *accountAPIClient) SendFriendRequest(ctx context.Context, token, target string) (string, error) {
	var res struct {
		Message string `json:"message"`
	}
	err := c.doJSON(ctx, http.MethodPost, "/api/friends/request", token, map[string]string{
		"username": strings.TrimSpace(target),
	}, &res)
	return res.Message, err
}

func (c *accountAPIClient) RespondFriendRequest(ctx context.Context, token, from string, accept bool) (string, error) {
	var res struct {
		Message string `json:"message"`
	}
	err := c.doJSON(ctx, http.MethodPost, "/api/friends/respond", token, map[string]any{
		"username": strings.TrimSpace(from),
		"accept":   accept,
	}, &res)
	return res.Message, err
}
