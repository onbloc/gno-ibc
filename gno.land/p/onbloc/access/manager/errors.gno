package manager

import (
	"errors"
	"strings"
)

var (
	errAccessManagerLockedRole        = errors.New("access manager locked role")
	errAccessManagerBadConfirmation   = errors.New("access manager bad confirmation")
	errAccessManagerUnauthorizedCall  = errors.New("access manager unauthorized call")
	errAccessManagerAlreadyScheduled  = errors.New("access manager already scheduled")
	errAccessManagerNotScheduled      = errors.New("access manager not scheduled")
	errAccessManagerNotReady          = errors.New("access manager not ready")
	errAccessManagerExpired           = errors.New("access manager expired")
	errAccessManagerInsufficientDelay = errors.New("access manager insufficient delay")
)

func errorWithDetails(err error, msgs ...string) error {
	if len(msgs) == 0 {
		return err
	}

	return errors.New(err.Error() + ", " + strings.Join(msgs, ", "))
}
