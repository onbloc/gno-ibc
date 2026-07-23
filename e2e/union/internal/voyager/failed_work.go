package voyager

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strconv"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
)

const maxDeadlockRetries = 5

type failedQueueItem struct {
	ID   jsonID         `json:"id"`
	Item failedWorkItem `json:"item"`
}

type failedWorkItem struct {
	Value struct {
		Value struct {
			Plugin  string `json:"plugin"`
			Message struct {
				Value struct {
					Event struct {
						Type  string `json:"@type"`
						Value struct {
							ClientID   jsonID `json:"client_id"`
							ClientType string `json:"client_type"`
						} `json:"@value"`
					} `json:"event"`
				} `json:"@value"`
			} `json:"message"`
		} `json:"@value"`
	} `json:"@value"`
}

// FailedWorkID returns the latest unrepaired Voyager failed-work ID.
func (r *Runtime) FailedWorkID(ctx context.Context, baseline int64, repaired []int64) (int64, error) {
	items, err := r.failedQueue(ctx)
	if err != nil {
		return 0, err
	}
	ignored := make(map[int64]struct{}, len(repaired))
	latestSeen := int64(0)
	for _, item := range items {
		if !item.ID.valid {
			return 0, ErrMalformedResponse
		}
		id := item.ID.value
		if id > latestSeen {
			latestSeen = id
		}
	}
	if (len(items) == 0 && baseline != 0) || baseline > latestSeen {
		return 0, fmt.Errorf("saved failed-work ID is ahead of Voyager queue")
	}
	for _, id := range repaired {
		if id > latestSeen {
			return 0, fmt.Errorf("saved repaired failed-work ID is ahead of Voyager queue")
		}
		ignored[id] = struct{}{}
	}
	latest := baseline
	for _, item := range items {
		if _, skip := ignored[item.ID.value]; !skip && item.ID.value > latest {
			latest = item.ID.value
		}
	}
	return latest, nil
}

func (r *Runtime) failedQueue(ctx context.Context) ([]failedQueueItem, error) {
	result, err := r.retryQueue(ctx, "query-failed", "--per-page", "100")
	if err != nil {
		return nil, err
	}
	var items []failedQueueItem
	if json.Unmarshal(result.Stdout, &items) != nil {
		return nil, ErrMalformedResponse
	}
	return items, nil
}

func (r *Runtime) repairFailedClientEvents(
	ctx context.Context,
	baseline int64,
	repaired []int64,
	want ClientExpectation,
	record func(int64) error,
) error {
	items, err := r.failedQueue(ctx)
	if err != nil {
		return err
	}
	ignored := make(map[int64]struct{}, len(repaired))
	for _, id := range repaired {
		ignored[id] = struct{}{}
	}
	var matches []int64
	for _, item := range items {
		id := item.ID.value
		if !item.ID.valid {
			return ErrMalformedResponse
		}
		if _, ok := ignored[id]; id > baseline && !ok && exactFailedCreate(item, want) {
			matches = append(matches, id)
		}
	}
	slices.Sort(matches)
	if len(matches) != 0 {
		if err := r.restart(ctx); err != nil {
			return err
		}
	}
	for _, id := range matches {
		if _, err := r.retryWrite(ctx,
			"queue", "query-failed-by-id", strconv.FormatInt(id, 10), "-e"); err != nil {
			return err
		}
		if err := record(id); err != nil {
			return err
		}
	}
	return nil
}

func exactFailedCreate(item failedQueueItem, want ClientExpectation) bool {
	event := item.Item.Value.Value.Message.Value.Event
	return strings.HasSuffix(item.Item.Value.Value.Plugin, "/"+want.Chain) &&
		event.Type == "create_client" &&
		event.Value.ClientID.valid &&
		event.Value.ClientID.value == want.ID &&
		event.Value.ClientType == want.ClientType
}

func (r *Runtime) retryQueue(ctx context.Context, args ...string) (process.Result, error) {
	return r.retryWrite(ctx, append([]string{"queue"}, args...)...)
}

func (r *Runtime) retryWrite(ctx context.Context, args ...string) (process.Result, error) {
	for attempt := 0; attempt < maxDeadlockRetries; attempt++ {
		result, err := r.call(ctx, args...)
		if err == nil {
			return result, nil
		}
		if !strings.Contains(string(result.Stdout)+string(result.Stderr), "deadlock detected") {
			return process.Result{}, err
		}
		if attempt+1 < maxDeadlockRetries {
			if err := pause(ctx, r.cfg.PollInterval); err != nil {
				return process.Result{}, fmt.Errorf("%w: retry Voyager queue", classifyContext(ctx, err))
			}
		}
	}
	return process.Result{}, fmt.Errorf(
		"%w: Voyager command remained deadlocked after %d attempts", ErrCommand, maxDeadlockRetries,
	)
}
