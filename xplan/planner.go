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
	ETag  string `json:"-"`
	ID    string `json:"id"`
	Title string `json:"title"`
}

// UnmarshalJSON reads the etag, which xplan keeps but does not print.
func (pl *plan) UnmarshalJSON(b []byte) error {
	type bare plan
	var v struct {
		bare
		ETag string `json:"@odata.etag"`
	}
	if err := json.Unmarshal(b, &v); err != nil {
		return err
	}
	*pl = plan(v.bare)
	pl.ETag = v.ETag
	return nil
}

type planDetails struct {
	ETag       string            `json:"@odata.etag"`
	Categories map[string]string `json:"categoryDescriptions"`
}

type bucket struct {
	ETag      string `json:"-"`
	ID        string `json:"id"`
	Name      string `json:"name"`
	PlanID    string `json:"planId"`
	OrderHint string `json:"orderHint"`
}

func (b *bucket) UnmarshalJSON(data []byte) error {
	type bare bucket
	var v struct {
		bare
		ETag string `json:"@odata.etag"`
	}
	if err := json.Unmarshal(data, &v); err != nil {
		return err
	}
	*b = bucket(v.bare)
	b.ETag = v.ETag
	return nil
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
	StartDateTime   *time.Time                 `json:"startDateTime"`
	Assignments     map[string]json.RawMessage `json:"assignments"`
	Categories      map[string]bool            `json:"appliedCategories"`
}

type checklistItem struct {
	ID        string `json:"-"`
	Title     string `json:"title"`
	IsChecked bool   `json:"isChecked"`
	OrderHint string `json:"orderHint"`
}

// maxChecklist is Planner's cap on a task's checklist.
const maxChecklist = 20

// items returns the checklist in the order Planner shows it.
func (d taskDetails) items() []checklistItem {
	out := make([]checklistItem, 0, len(d.Checklist))
	for id, item := range d.Checklist {
		item.ID = id
		out = append(out, item)
	}
	sortByHint(out, func(c checklistItem) string { return c.OrderHint })
	return out
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
	labels  map[string]planDetails
	users   map[string]user
}

func newPlanner(g *graphauth.GraphClient) *planner {
	return &planner{g: g, buckets: map[string][]bucket{}, labels: map[string]planDetails{}, users: map[string]user{}}
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
	return t, taskNotFound(id, err)
}

// taskNotFound words Graph's answer to an unknown task ID.
func taskNotFound(id string, err error) error {
	if isStatus(err, http.StatusNotFound) || isStatus(err, http.StatusBadRequest) {
		return fmt.Errorf("no task with ID %q", id)
	}
	return err
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
	return staleAs("task", err)
}

func (p *planner) setDescription(ctx context.Context, id, text string) error {
	d, err := p.getDetails(ctx, id)
	if err != nil {
		return err
	}
	_, err = p.g.PatchIfMatch(ctx, "/planner/tasks/"+url.PathEscape(id)+"/details", d.ETag,
		map[string]any{"description": text, "previewType": "description"})
	return staleAs("task", err)
}

func (p *planner) deleteTask(ctx context.Context, t task) error {
	return staleAs("task", p.g.DeleteIfMatch(ctx, "/planner/tasks/"+url.PathEscape(t.ID), t.ETag))
}

// staleAs reports a lost etag race on the named kind of item.
func staleAs(kind string, err error) error {
	if isStatus(err, http.StatusPreconditionFailed) || isStatus(err, http.StatusConflict) {
		return fmt.Errorf("the %s changed between xplan reading it and writing it; run the command again", kind)
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

func (p *planner) renamePlan(ctx context.Context, pl plan, title string) error {
	_, err := p.g.PatchIfMatch(ctx, "/planner/plans/"+url.PathEscape(pl.ID), pl.ETag, map[string]any{"title": title})
	return staleAs("plan", err)
}

func (p *planner) planDetails(ctx context.Context, planID string) (planDetails, error) {
	if d, ok := p.labels[planID]; ok {
		return d, nil
	}
	d, err := getOne[planDetails](ctx, p.g, "/planner/plans/"+url.PathEscape(planID)+"/details")
	if err != nil {
		return d, err
	}
	p.labels[planID] = d
	return d, nil
}

func (p *planner) nameLabel(ctx context.Context, planID string, slot int, name string) error {
	d, err := p.planDetails(ctx, planID)
	if err != nil {
		return err
	}
	_, err = p.g.PatchIfMatch(ctx, "/planner/plans/"+url.PathEscape(planID)+"/details", d.ETag,
		map[string]any{"categoryDescriptions": map[string]any{categoryKey(slot): name}})
	return staleAs("plan", err)
}

func (p *planner) createBucket(ctx context.Context, planID, name string) (bucket, error) {
	var b bucket
	buckets, err := p.planBuckets(ctx, planID)
	if err != nil {
		return b, err
	}
	resp, err := p.g.Post(ctx, "/planner/buckets", map[string]any{
		"name": name, "planId": planID, "orderHint": afterLast(buckets, func(b bucket) string { return b.OrderHint }),
	})
	if err != nil {
		return b, err
	}
	if err := json.Unmarshal(resp, &b); err != nil {
		return b, fmt.Errorf("decoding the created bucket: %w", err)
	}
	return b, nil
}

func (p *planner) renameBucket(ctx context.Context, b bucket, name string) error {
	_, err := p.g.PatchIfMatch(ctx, "/planner/buckets/"+url.PathEscape(b.ID), b.ETag, map[string]any{"name": name})
	return staleAs("bucket", err)
}

func (p *planner) deleteBucket(ctx context.Context, b bucket) error {
	return staleAs("bucket", p.g.DeleteIfMatch(ctx, "/planner/buckets/"+url.PathEscape(b.ID), b.ETag))
}

// patchChecklist applies changes to a task's checklist, keyed by item ID; a
// nil value removes the item.
func (p *planner) patchChecklist(ctx context.Context, taskID, etag string, changes map[string]any) error {
	_, err := p.g.PatchIfMatch(ctx, "/planner/tasks/"+url.PathEscape(taskID)+"/details", etag,
		map[string]any{"checklist": changes})
	return staleAs("task", err)
}

// afterLast is the orderHint that places a new item after the last of items:
// Planner reads "<previous> <next>!" and computes the real hint itself.
func afterLast[T any](items []T, hint func(T) string) string {
	if len(items) == 0 {
		return " !"
	}
	return hint(items[len(items)-1]) + " !"
}
