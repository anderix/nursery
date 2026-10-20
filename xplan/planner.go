// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"github.com/excelano/graphauth"
)

type plan struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

type bucket struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	PlanID    string `json:"planId"`
	OrderHint string `json:"orderHint"`
}

type task struct {
	ETag            string                     `json:"@odata.etag"`
	ID              string                     `json:"id"`
	PlanID          string                     `json:"planId"`
	BucketID        string                     `json:"bucketId"`
	Title           string                     `json:"title"`
	PercentComplete int                        `json:"percentComplete"`
	Priority        int                        `json:"priority"`
	DueDateTime     *time.Time                 `json:"dueDateTime"`
	Assignments     map[string]json.RawMessage `json:"assignments"`
}

type checklistItem struct {
	Title     string `json:"title"`
	IsChecked bool   `json:"isChecked"`
	OrderHint string `json:"orderHint"`
}

type taskDetails struct {
	ETag        string                   `json:"@odata.etag"`
	Description string                   `json:"description"`
	Checklist   map[string]checklistItem `json:"checklist"`
}

type user struct {
	ID          string `json:"id"`
	DisplayName string `json:"displayName"`
	UPN         string `json:"userPrincipalName"`
}

// planner is the Graph surface xplan uses, with the per-run lookups it repeats
// held so a listing resolves each plan, bucket and person once.
type planner struct {
	g       *graphauth.GraphClient
	plans   []plan
	buckets map[string][]bucket
	users   map[string]user
}

func newPlanner(g *graphauth.GraphClient) *planner {
	return &planner{g: g, buckets: map[string][]bucket{}, users: map[string]user{}}
}

func getAll[T any](ctx context.Context, g *graphauth.GraphClient, path string) ([]T, error) {
	raw, err := g.GetAll(ctx, path, nil)
	if err != nil {
		return nil, err
	}
	out := make([]T, 0, len(raw))
	for _, r := range raw {
		var v T
		if err := json.Unmarshal(r, &v); err != nil {
			return nil, fmt.Errorf("decoding %s: %w", path, err)
		}
		out = append(out, v)
	}
	return out, nil
}

func getOne[T any](ctx context.Context, g *graphauth.GraphClient, path string) (T, error) {
	var v T
	body, err := g.Get(ctx, path, nil)
	if err != nil {
		return v, err
	}
	if err := json.Unmarshal(body, &v); err != nil {
		return v, fmt.Errorf("decoding %s: %w", path, err)
	}
	return v, nil
}

func isStatus(err error, status int) bool {
	var he *graphauth.HTTPError
	return errors.As(err, &he) && he.Status == status
}

// myPlans lists the plans shared with the signed-in user, sorted by title.
func (p *planner) myPlans(ctx context.Context) ([]plan, error) {
	if p.plans != nil {
		return p.plans, nil
	}
	plans, err := getAll[plan](ctx, p.g, "/me/planner/plans")
	if err != nil {
		return nil, err
	}
	sort.Slice(plans, func(i, j int) bool { return strings.ToLower(plans[i].Title) < strings.ToLower(plans[j].Title) })
	p.plans = plans
	return plans, nil
}

// resolvePlan finds a plan by ID or by case-insensitive title among the
// user's plans, then falls back to fetching the reference as an ID, which
// reaches a plan the user can open but is not listed for.
func (p *planner) resolvePlan(ctx context.Context, ref string) (plan, error) {
	plans, err := p.myPlans(ctx)
	if err != nil {
		return plan{}, err
	}
	var matches []plan
	for _, pl := range plans {
		if pl.ID == ref {
			return pl, nil
		}
		if strings.EqualFold(pl.Title, ref) {
			matches = append(matches, pl)
		}
	}
	switch len(matches) {
	case 1:
		return matches[0], nil
	case 0:
		pl, err := getOne[plan](ctx, p.g, "/planner/plans/"+url.PathEscape(ref))
		if err == nil {
			return pl, nil
		}
		if isStatus(err, http.StatusNotFound) || isStatus(err, http.StatusBadRequest) {
			return plan{}, fmt.Errorf("no plan titled or with ID %q; `xplan plans` lists yours", ref)
		}
		return plan{}, err
	default:
		ids := make([]string, len(matches))
		for i, m := range matches {
			ids[i] = m.ID
		}
		return plan{}, fmt.Errorf("%d plans are titled %q; name one by ID: %s", len(matches), ref, strings.Join(ids, ", "))
	}
}

func (p *planner) planTitle(ctx context.Context, id string) string {
	plans, _ := p.myPlans(ctx)
	for _, pl := range plans {
		if pl.ID == id {
			return pl.Title
		}
	}
	return id
}

// planBuckets lists a plan's buckets in board order.
func (p *planner) planBuckets(ctx context.Context, planID string) ([]bucket, error) {
	if b, ok := p.buckets[planID]; ok {
		return b, nil
	}
	buckets, err := getAll[bucket](ctx, p.g, "/planner/plans/"+url.PathEscape(planID)+"/buckets")
	if err != nil {
		return nil, err
	}
	sortByHint(buckets, func(b bucket) string { return b.OrderHint })
	p.buckets[planID] = buckets
	return buckets, nil
}

func (p *planner) resolveBucket(ctx context.Context, planID, ref string) (bucket, error) {
	buckets, err := p.planBuckets(ctx, planID)
	if err != nil {
		return bucket{}, err
	}
	var matches []bucket
	for _, b := range buckets {
		if b.ID == ref {
			return b, nil
		}
		if strings.EqualFold(b.Name, ref) {
			matches = append(matches, b)
		}
	}
	switch len(matches) {
	case 1:
		return matches[0], nil
	case 0:
		return bucket{}, fmt.Errorf("no bucket named %q in this plan; `xplan buckets <plan>` lists them", ref)
	default:
		return bucket{}, fmt.Errorf("%d buckets are named %q; name one by ID", len(matches), ref)
	}
}

func (p *planner) bucketName(ctx context.Context, planID, bucketID string) string {
	buckets, _ := p.planBuckets(ctx, planID)
	for _, b := range buckets {
		if b.ID == bucketID {
			return b.Name
		}
	}
	return ""
}

// sortByHint orders Planner items the way Planner does: by orderHint compared
// ordinally.
func sortByHint[T any](items []T, hint func(T) string) {
	sort.SliceStable(items, func(i, j int) bool { return hint(items[i]) < hint(items[j]) })
}

func (p *planner) planTasks(ctx context.Context, planID string) ([]task, error) {
	return getAll[task](ctx, p.g, "/planner/plans/"+url.PathEscape(planID)+"/tasks")
}

func (p *planner) myTasks(ctx context.Context) ([]task, error) {
	return getAll[task](ctx, p.g, "/me/planner/tasks")
}

func (p *planner) getTask(ctx context.Context, id string) (task, error) {
	t, err := getOne[task](ctx, p.g, "/planner/tasks/"+url.PathEscape(id))
	if isStatus(err, http.StatusNotFound) || isStatus(err, http.StatusBadRequest) {
		return t, fmt.Errorf("no task with ID %q", id)
	}
	return t, err
}

func (p *planner) getDetails(ctx context.Context, id string) (taskDetails, error) {
	return getOne[taskDetails](ctx, p.g, "/planner/tasks/"+url.PathEscape(id)+"/details")
}

func (p *planner) createTask(ctx context.Context, body map[string]any) (task, error) {
	var t task
	resp, err := p.g.Post(ctx, "/planner/tasks", body)
	if err != nil {
		return t, err
	}
	if err := json.Unmarshal(resp, &t); err != nil {
		return t, fmt.Errorf("decoding the created task: %w", err)
	}
	return t, nil
}

// updateTask applies patch to the task as last read; Planner refuses a write
// that does not carry the etag it replaces.
func (p *planner) updateTask(ctx context.Context, t task, patch map[string]any) error {
	_, err := p.g.PatchIfMatch(ctx, "/planner/tasks/"+url.PathEscape(t.ID), t.ETag, patch)
	return staleAsChanged(err)
}

func (p *planner) setDescription(ctx context.Context, id, text string) error {
	d, err := p.getDetails(ctx, id)
	if err != nil {
		return err
	}
	_, err = p.g.PatchIfMatch(ctx, "/planner/tasks/"+url.PathEscape(id)+"/details", d.ETag,
		map[string]any{"description": text, "previewType": "description"})
	return staleAsChanged(err)
}

func (p *planner) deleteTask(ctx context.Context, t task) error {
	return staleAsChanged(p.g.DeleteIfMatch(ctx, "/planner/tasks/"+url.PathEscape(t.ID), t.ETag))
}

func staleAsChanged(err error) error {
	if isStatus(err, http.StatusPreconditionFailed) || isStatus(err, http.StatusConflict) {
		return errors.New("the task changed between xplan reading it and writing it; run the command again")
	}
	return err
}

// lookupUser resolves a user by object ID, UPN or email, or "me".
func (p *planner) lookupUser(ctx context.Context, ref string) (user, error) {
	if u, ok := p.users[strings.ToLower(ref)]; ok {
		return u, nil
	}
	path := "/users/" + url.PathEscape(ref)
	if strings.EqualFold(ref, "me") {
		path = "/me"
	}
	u, err := getOne[user](ctx, p.g, path+"?$select=id,displayName,userPrincipalName")
	if isStatus(err, http.StatusNotFound) {
		return u, fmt.Errorf("no user %q in this tenant", ref)
	}
	if err != nil {
		return u, err
	}
	p.users[strings.ToLower(ref)] = u
	p.users[strings.ToLower(u.ID)] = u
	return u, nil
}

// assignees resolves a task's assignment keys to users, in name order. A
// lookup that fails leaves the bare ID, so one departed user does not sink a
// listing.
func (p *planner) assignees(ctx context.Context, t task) []user {
	out := make([]user, 0, len(t.Assignments))
	for id := range t.Assignments {
		u, err := p.lookupUser(ctx, id)
		if err != nil {
			u = user{ID: id, DisplayName: id}
		}
		out = append(out, u)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].DisplayName < out[j].DisplayName })
	return out
}
