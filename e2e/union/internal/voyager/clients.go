package voyager

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var heightPattern = regexp.MustCompile(`^([1-9][0-9]*-)?[1-9][0-9]*$`)

// ClientCreation describes one create-client write at an expected allocation.
type ClientCreation struct {
	ClientExpectation
	Config string
	Height string
}

// LatestFinalizedHeight returns the chain's positive finalized height.
func (r *Runtime) LatestFinalizedHeight(ctx context.Context, chain string) (string, error) {
	result, err := r.call(ctx, "rpc", "latest-height", chain, "--finalized")
	if err != nil {
		return "", fmt.Errorf("query finalized height: %w", err)
	}
	var height string
	if json.Unmarshal(result.Stdout, &height) != nil || !heightPattern.MatchString(height) ||
		strings.Contains(height, "-") {
		return "", ErrMalformedResponse
	}
	return height, nil
}

// NextClientID returns the first missing positive client ID.
func (r *Runtime) NextClientID(ctx context.Context, chain string) (int64, error) {
	for id := int64(1); ; id++ {
		_, err := r.clientInfo(ctx, chain, id)
		if errors.Is(err, ErrNotFound) {
			return id, nil
		}
		if err != nil {
			return 0, err
		}
	}
}

// ClientHeight returns the validated counterparty height for a client.
func (r *Runtime) ClientHeight(ctx context.Context, chain string, id int64) (string, error) {
	meta, err := r.clientMeta(ctx, chain, id)
	if err != nil {
		return "", err
	}
	if !heightPattern.MatchString(meta.CounterpartyHeight) {
		return "", ErrMalformedResponse
	}
	return meta.CounterpartyHeight, nil
}

// Index enqueues one chain index operation.
func (r *Runtime) Index(ctx context.Context, chain, from string) error {
	args := []string{"index", chain}
	if from != "" {
		args = append(args, "--from", from)
	}
	_, err := r.retryWrite(ctx, append(args, "-e")...)
	return err
}

// CreateClient checks allocation, broadcasts once, and waits for the exact client.
func (r *Runtime) CreateClient(
	ctx context.Context,
	want ClientCreation,
	baseline int64,
	repaired []int64,
	recordRepair func(int64) error,
) error {
	next, err := r.NextClientID(ctx, want.Chain)
	if err != nil {
		return err
	}
	if next != want.ID {
		return fmt.Errorf("client allocation changed: expected %s client ID %d", want.Chain, want.ID)
	}
	args := []string{
		"msg", "create-client", "--on", want.Chain, "--tracking", want.Counterparty,
		"--ibc-interface", want.IBCInterface, "--client-type", want.ClientType,
	}
	if want.Config != "" {
		args = append(args, "--config", want.Config)
	}
	if want.Height != "" {
		args = append(args, "--height", want.Height)
	}
	if _, err := r.retryWrite(ctx, append(args, "-e")...); err != nil {
		return err
	}

	known := append([]int64(nil), repaired...)
	refreshes := 0
	nextRefresh := time.Now().Add(r.cfg.EVMRefreshInterval)
	waitCtx, cancel := context.WithTimeout(ctx, r.cfg.ScenarioTimeout)
	defer cancel()
	for {
		err := r.repairFailedClientEvents(waitCtx, baseline, known, want.ClientExpectation, func(id int64) error {
			if err := recordRepair(id); err != nil {
				return err
			}
			known = append(known, id)
			return nil
		})
		if err != nil {
			return err
		}
		err = r.verifyClient(waitCtx, want.ClientExpectation)
		if err == nil {
			return nil
		}
		if !errors.Is(err, ErrNotFound) {
			return err
		}
		if want.Chain == r.cfg.EVMChainID && refreshes < 3 && !time.Now().Before(nextRefresh) {
			if err := r.restart(waitCtx); err != nil {
				return err
			}
			refreshes++
			nextRefresh = time.Now().Add(r.cfg.EVMRefreshInterval)
		}
		if err := pause(waitCtx, r.cfg.PollInterval); err != nil {
			return fmt.Errorf("%w: %s client %d was not visible",
				classifyContext(waitCtx, err), want.Chain, want.ID)
		}
	}
}

// EVMAllowlists classifies every allocated EVM client by transaction plugin.
func (r *Runtime) EVMAllowlists(ctx context.Context) ([]int64, []int64, error) {
	next, err := r.NextClientID(ctx, r.cfg.EVMChainID)
	if err != nil {
		return nil, nil, err
	}
	var plain, proof []int64
	for id := int64(1); id < next; id++ {
		info, err := r.clientInfo(ctx, r.cfg.EVMChainID, id)
		if err != nil {
			return nil, nil, fmt.Errorf("inspect EVM client %s: %w", strconv.FormatInt(id, 10), err)
		}
		if info.ClientType == "proof-lens" {
			proof = append(proof, id)
		} else {
			plain = append(plain, id)
		}
	}
	if len(plain) == 0 || len(proof) == 0 {
		return nil, nil, fmt.Errorf("EVM plain and Proof Lens client allowlists must both be non-empty")
	}
	return plain, proof, nil
}
