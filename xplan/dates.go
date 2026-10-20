// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

package main

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

const dateForms = "YYYY-MM-DD, today, tomorrow, a weekday, +Nd or +Nw"

// parseDate reads a date relative to now and returns local midnight on it,
// which Planner shows as that date. A weekday means the next one after today.
func parseDate(s string, now time.Time) (time.Time, error) {
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	lower := strings.ToLower(s)
	switch lower {
	case "today":
		return today, nil
	case "tomorrow":
		return today.AddDate(0, 0, 1), nil
	}
	if d, err := time.ParseInLocation(time.DateOnly, s, now.Location()); err == nil {
		return d, nil
	}
	if rest, ok := strings.CutPrefix(lower, "+"); ok && len(rest) > 1 {
		n, err := strconv.Atoi(rest[:len(rest)-1])
		if err == nil && n >= 0 {
			switch rest[len(rest)-1] {
			case 'd':
				return today.AddDate(0, 0, n), nil
			case 'w':
				return today.AddDate(0, 0, 7*n), nil
			}
		}
	}
	for wd := time.Sunday; wd <= time.Saturday; wd++ {
		name := strings.ToLower(wd.String())
		if len(lower) >= 3 && strings.HasPrefix(name, lower) {
			ahead := (int(wd) - int(today.Weekday()) + 7) % 7
			if ahead == 0 {
				ahead = 7
			}
			return today.AddDate(0, 0, ahead), nil
		}
	}
	return time.Time{}, fmt.Errorf("%q is not a date; write %s", s, dateForms)
}

// dateField turns a date flag into the value Graph takes: an RFC 3339 UTC
// time, or nil for "none", which clears the date.
func dateField(flagName, s string, now time.Time) (any, error) {
	if strings.EqualFold(s, "none") {
		return nil, nil
	}
	d, err := parseDate(s, now)
	if err != nil {
		return nil, fmt.Errorf("--%s: %w, or none to clear it", flagName, err)
	}
	return d.UTC().Format(time.RFC3339), nil
}
