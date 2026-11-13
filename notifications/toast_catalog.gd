extends RefCounted
## ToastCatalog - registered achievement and reaction toasts for developer tooling.
##
## Builds display entries from catalog/brain_rot_catalog.gd, so the dev toast
## preview always matches what gameplay can actually show. Pure data: no nodes, no
## game state, no achievement store. Previewing an entry never changes progress or
## save data; it only builds a NotificationRequest with duplicate display allowed.

const Catalog = preload("../catalog/brain_rot_catalog.gd")
const NotificationRequest = preload("../notifications/notification_request.gd")

const KIND_ACHIEVEMENT := NotificationRequest.KIND_ACHIEVEMENT
const KIND_REACTION := NotificationRequest.KIND_REACTION


## Every registered achievement and reaction as
## {kind, id, label, title, description}. Achievements come first, in catalog
## order; reactions follow in catalog order.
static func entries() -> Array:
	var out: Array = []

	for definition in Catalog.achievements():
		var id := str(definition.get("id", ""))
		if id.is_empty():
			continue
		var title := str(definition.get("title", id))
		out.append({
			"kind": KIND_ACHIEVEMENT,
			"id": id,
			"label": "Achievement - %s" % title,
			"title": title,
			"description": str(definition.get("description", "")),
		})

	for definition in Catalog.reactions():
		var id := str(definition.get("id", ""))
		if id.is_empty():
			continue
		var title := str(definition.get("title", id))
		out.append({
			"kind": KIND_REACTION,
			"id": id,
			"label": "Reaction - %s" % title,
			"title": title,
			"description": Catalog.describe_entry(definition),
		})

	return out


## Build the NotificationRequest used to preview an entry.
##
## allow_duplicate is true so repeated previews are shown even while the same
## toast is visible or queued. Nothing else is touched: no achievement store, no
## save data, and no game state.
static func make_request(entry: Dictionary) -> NotificationRequest:
	return NotificationRequest.new(
		str(entry.get("kind", "")),
		str(entry.get("id", "")),
		str(entry.get("title", "")),
		str(entry.get("description", "")),
		NotificationRequest.DEFAULT_DURATION_MS,
		true,
	)


## Entry matching kind + id, or {} when absent.
static func find(all_entries: Array, kind: String, id: String) -> Dictionary:
	for entry in all_entries:
		if str(entry.get("kind", "")) == kind and str(entry.get("id", "")) == id:
			return entry
	return {}
